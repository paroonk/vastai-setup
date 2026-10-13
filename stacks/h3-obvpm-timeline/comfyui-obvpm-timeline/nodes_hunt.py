"""Seed hunting: one Run, several takes from different seeds, pick one.

A hunt is a LOOP inside one Run. H3 Seed Hunt passes out one seed; the
Result Preview fed by the save node closes the loop: once it has shown a
take, it hands ComfyUI a copy of every node between H3 Seed Hunt and
itself -- the noise, the sampler(s), the decode, the save, the preview --
with the copied H3 Seed Hunt set to the next take (a graph expansion,
the mechanism of ComfyUI's own while loop). So each take is sampled,
decoded, saved and shown before the next one starts, and can be looked
at while the others sample. Whatever the loop does not reach (models,
the timeline, the pins, the text encoders) runs once. A hunt needs no
more memory than one take and takes `count` times as long. A count of 1
is an ordinary Run.

While hunting, the save node files each take as a CANDIDATE in a folder
of its own Run: <base_folder>/_candidates/<run>/, out of the clip picker and
the seam menus, named for the hunt (take_01_seed_1234.mp4); its sidecar
keeps the save prefix it would have had (`save_prefix`). The Result Preview shows a Run's candidates side by side;
the one you add is moved out next to the other takes under the next clip
number (promote), and discarding deletes the Run's folder with whatever
is left in it (the takes not added, their cached previews). A take's
identity is the hash of its MP4, not its name, so a move keeps every
lineage edge.
"""

import logging
import os
import re
import shutil
import threading
import time

import folder_paths

from . import condstore, mctx

_LOG = logging.getLogger("obvpm.h3")

CANDIDATE_DIR = "_candidates"
# a candidate's name: its place in the hunt and its seed
TAKE_NAME = re.compile(r"^take_\d+(?:_seed_\d+)?\.mp4$", re.IGNORECASE)
# Seeds of one hunt: seed, seed + STRIDE, seed + 2 * STRIDE, ... The
# stride keeps a hunt's seeds clear of the next Run's when the seed
# widget increments by one, and keeps them readable on the tiles.
STRIDE = 10000
MAX_COUNT = 16
_SEED_MAX = 0xFFFFFFFFFFFFFFFF

# prompt id -> its Run's folder name: every candidate of one Run (the save
# node is called once per seed) lands in the same folder
_RUN_FOLDERS = {}
_RUN_FOLDERS_MAX = 64
_RUN_GUARD = threading.Lock()


def hunt_seeds(seed, count):
    """The seeds one hunt samples: `seed` first, so a count of 1 -- and
    the first candidate of any hunt -- is exactly an ordinary Run."""
    n = max(1, min(MAX_COUNT, int(count)))
    return [take_seed(seed, i) for i in range(n)]


def take_seed(seed, index):
    """The seed of a hunt's take `index` (0 = the seed itself)."""
    return (int(seed) + int(index) * STRIDE) % (_SEED_MAX + 1)


# ---- the loop ------------------------------------------------------------
# A copy of H3 Seed Hunt made for take k carries k under this key in its
# own prompt entry. Not a declared input, so it has no socket and never
# reaches hunt(); the node reads it back through DYNPROMPT. It is part of
# the cache signature, so every take is its own cache entry.
TAKE_KEY = "obvpm_take"
SEED_HUNT = "H3SeedHunt"
CLOSER = "H3ResultPreview"

# Seed Hunt node id (as executed, a loop copy's own id) -> (take, count).
# Keyed by node id, not by Run: a Seed Hunt served from ComfyUI's cache
# does not run again, and a cached node had exactly these inputs last
# time. Copies' ids are stable across Runs too (prefix + original id).
_TAKES = {}
_TAKES_MAX = 512
# (prompt id, Seed Hunt id) whose next take has been queued: a second
# Result Preview on the same save must not start a second loop
_LOOPED = {}
_LOOPED_MAX = 512


def _is_link(v):
    return (isinstance(v, list) and len(v) == 2 and isinstance(v[0], str)
            and isinstance(v[1], (int, float)))


def take_index(dynprompt, unique_id):
    """Which take this H3 Seed Hunt (or loop copy of it) samples."""
    try:
        v = dynprompt.get_node(unique_id)["inputs"].get(TAKE_KEY, 0)
        return max(0, int(v))
    except Exception:
        return 0


def _record(unique_id, take, count):
    with _RUN_GUARD:
        _TAKES.pop(unique_id, None)
        _TAKES[unique_id] = (int(take), int(count))
        while len(_TAKES) > _TAKES_MAX:
            _TAKES.pop(next(iter(_TAKES)))


def _upstream(dynprompt, node_id):
    """{ancestor id: [ids it feeds]} for everything node_id depends on."""
    feeds = {}
    stack = [node_id]
    seen = {node_id}
    while stack:
        nid = stack.pop()
        try:
            inputs = dynprompt.get_node(nid).get("inputs", {})
        except Exception:
            continue
        for v in inputs.values():
            if not _is_link(v):
                continue
            parent = v[0]
            feeds.setdefault(parent, []).append(nid)
            if parent not in seen:
                seen.add(parent)
                stack.append(parent)
    return feeds


def hunt_of(dynprompt, node_id):
    """The H3 Seed Hunt node (id) node_id depends on, or None. With
    several, the nearest."""
    stack = [node_id]
    seen = {node_id}
    while stack:
        nxt = []
        for nid in stack:
            try:
                inputs = dynprompt.get_node(nid).get("inputs", {})
            except Exception:
                continue
            for v in inputs.values():
                if not _is_link(v) or v[0] in seen:
                    continue
                seen.add(v[0])
                try:
                    if dynprompt.get_node(v[0])["class_type"] == SEED_HUNT:
                        return v[0]
                except Exception:
                    continue
                nxt.append(v[0])
        stack = nxt
    return None


def hunt_state(dynprompt, node_id):
    """(Seed Hunt id, take, count) of the hunt node_id belongs to, or None
    when it is not in one (no H3 Seed Hunt upstream). A count of 1 is a
    hunt of one take: shown like one, never looped."""
    if dynprompt is None or node_id is None:
        return None
    hid = hunt_of(dynprompt, node_id)
    if hid is None:
        return None
    take, count = _TAKES.get(hid, (take_index(dynprompt, hid), 1))
    return hid, take, count


def next_take(dynprompt, closer_id):
    """The graph that makes the next take, for the closer (the Result
    Preview) to hand to ComfyUI as an expansion, or None when the hunt is
    done -- or when this node is not in a hunt.

    Copies every node between the hunt's H3 Seed Hunt and the closer (both
    included), wired among themselves as the originals are; inputs from
    outside that span keep pointing at the original nodes, which are
    cached. The copied H3 Seed Hunt gets the next take's index."""
    st = hunt_state(dynprompt, closer_id)
    if st is None:
        return None
    hid, take, count = st
    if take + 1 >= count:
        return None
    key = (run_id(), hid)
    with _RUN_GUARD:
        if key in _LOOPED:
            return None
        _LOOPED[key] = True
        while len(_LOOPED) > _LOOPED_MAX:
            _LOOPED.pop(next(iter(_LOOPED)))
    feeds = _upstream(dynprompt, closer_id)
    # the span: downstream of the Seed Hunt, upstream of the closer
    contained = {hid, closer_id}
    stack = [hid]
    while stack:
        for child in feeds.get(stack.pop(), ()):
            if child not in contained:
                contained.add(child)
                stack.append(child)
    from comfy_execution.graph_utils import GraphBuilder
    graph = GraphBuilder()
    # the copy of the closer gets a short fixed name, so ids do not grow
    # by the closer's own id at every take
    name = {nid: ("next" if nid == closer_id else nid) for nid in contained}
    for nid in contained:
        node = graph.node(dynprompt.get_node(nid)["class_type"], name[nid])
        node.set_override_display_id(dynprompt.get_display_node_id(nid))
    for nid in contained:
        node = graph.lookup_node(name[nid])
        for k, v in dynprompt.get_node(nid)["inputs"].items():
            if _is_link(v) and v[0] in contained:
                node.set_input(k, graph.lookup_node(name[v[0]]).out(v[1]))
            else:
                node.set_input(k, v)
    graph.lookup_node(name[hid]).set_input(TAKE_KEY, take + 1)
    _LOG.info("obvpm.h3: seed hunt: take %d of %d done, next %d (%d nodes "
              "re-run)", take + 1, count, take + 2, len(contained))
    return graph.finalize()


def run_id():
    """The id of the Run executing now (its prompt id), or "" outside one."""
    try:
        from comfy_execution.utils import get_executing_context
        ctx = get_executing_context()
    except Exception:
        return ""
    return str(getattr(ctx, "prompt_id", "") or "") if ctx else ""


def run_folder(hunts_abs):
    """The folder (a name inside `hunts_abs`) this Run's candidates go to:
    the time the Run's first candidate was saved, so the folders sort in
    the order the hunts were made. Outside a Run every call gets its own."""
    rid = run_id()
    with _RUN_GUARD:
        if rid and rid in _RUN_FOLDERS:
            return _RUN_FOLDERS[rid]
        base = time.strftime("%Y%m%d-%H%M%S")
        name, k = base, 1
        while os.path.exists(os.path.join(hunts_abs, name)):
            k += 1
            name = "%s-%d" % (base, k)
        os.makedirs(os.path.join(hunts_abs, name), exist_ok=True)
        if rid:
            _RUN_FOLDERS[rid] = name
            while len(_RUN_FOLDERS) > _RUN_FOLDERS_MAX:
                _RUN_FOLDERS.pop(next(iter(_RUN_FOLDERS)))
        return name


def candidate_name(run_dir, seed=None):
    """The next candidate's file name in a Run's folder: take_01_seed_N.mp4
    for the first, take_02_... for the second (the loop saves them one
    after the other), never one already there."""
    try:
        names = os.listdir(run_dir)
    except OSError:
        names = []
    n = sum(1 for x in names if TAKE_NAME.match(x)) + 1
    while True:
        name = ("take_%02d_seed_%d.mp4" % (n, int(seed)) if seed is not None
                else "take_%02d.mp4" % n)
        full = os.path.join(run_dir, name)
        if not any(os.path.exists(f) for f in _files_of(full)):
            return name
        n += 1


def save_prefix_of(ap):
    """The save prefix a take recorded (output-relative), or None."""
    try:
        return mctx.read_header(mctx.sidecar_path(ap)).get("save_prefix") or None
    except Exception:
        return None


def belongs(full, take_re, prefix=None):
    """Is the candidate at `full` one of the save prefix's takes? Named
    by the save itself (`take_re`, from before takes were named for the
    hunt), or a hunt name whose sidecar records that prefix."""
    name = os.path.basename(full)
    if take_re.match(name):
        return True
    if not TAKE_NAME.match(name):
        return False
    own = save_prefix_of(full)
    return own is None or prefix is None or own == prefix


def is_candidate(rel):
    """Is this output-relative path a hunt candidate (<x>/_candidates/<run>/f)?"""
    parts = str(rel or "").replace("\\", "/").split("/")
    return len(parts) >= 3 and parts[-3] == CANDIDATE_DIR


def home_of(ap):
    """The folder a candidate (absolute path) goes to when it is added."""
    return os.path.dirname(os.path.dirname(os.path.dirname(ap)))


def _files_of(ap):
    """A take's files: the MP4, its mctx sidecar, its conditioning cache."""
    return (ap, mctx.sidecar_path(ap), condstore.cond_path(ap))


def _candidate(rel, what):
    """(root, absolute path) of an existing candidate MP4, else ValueError."""
    root = os.path.abspath(folder_paths.get_output_directory())
    ap = os.path.abspath(os.path.join(root, str(rel or "").strip()))
    if os.path.commonpath([root, ap]) != root:
        raise ValueError("hunt %s: %r escapes the output folder" % (what, rel))
    if not is_candidate(os.path.relpath(ap, root)):
        raise ValueError("hunt %s: %r is not a hunt candidate" % (what, rel))
    if not ap.lower().endswith(".mp4") or not os.path.isfile(ap):
        raise ValueError("hunt %s: not found: %r" % (what, rel))
    return root, ap


def _takes_left(run_dir):
    try:
        return any(n.lower().endswith(".mp4") and os.path.isfile(
                       mctx.sidecar_path(os.path.join(run_dir, n)))
                   for n in os.listdir(run_dir))
    except OSError:
        return False


def tidy_run(run_dir):
    """A Run's folder with no candidate left goes, cached previews and all;
    so does the _candidates folder once it holds no Run."""
    if _takes_left(run_dir):
        return
    shutil.rmtree(run_dir, ignore_errors=True)
    try:
        os.rmdir(os.path.dirname(run_dir))      # only when it is empty
    except OSError:
        pass


def promote(rel):
    """Move a candidate out of its Run's folder, next to the other takes,
    under the next clip number. Returns the new output-relative path."""
    root, ap = _candidate(rel, "promote")
    run_dir = os.path.dirname(ap)
    home = home_of(ap)
    # the name the save would have given it: its recorded prefix, else
    # (named before takes were named for the hunt) its own name's stem
    own = save_prefix_of(ap)
    m = re.match(r"^(.*)_\d+\.mp4$", os.path.basename(ap), re.IGNORECASE)
    stem = (own.replace("\\", "/").split("/")[-1] if own
            else m.group(1) if m
            else os.path.splitext(os.path.basename(ap))[0])
    prefix = os.path.relpath(os.path.join(home, stem), root).replace(os.sep, "/")
    full_folder, filename, counter, _sub, _ = folder_paths.get_save_image_path(
        prefix, root, 0, 0)
    dest = os.path.join(full_folder, "%s_%05d.mp4" % (filename, counter))
    # never overwrite: the counter scan and a concurrent save could agree
    while any(os.path.exists(f) for f in _files_of(dest)):
        counter += 1
        dest = os.path.join(full_folder, "%s_%05d.mp4" % (filename, counter))
    # the MP4 last: the sidecar is the commit point of a take, and a
    # half-moved one must not look like a take without its latents
    for src, dst in list(zip(_files_of(ap), _files_of(dest)))[1:]:
        if os.path.isfile(src):
            os.replace(src, dst)
    os.replace(ap, dest)
    tidy_run(run_dir)
    new_rel = os.path.relpath(dest, root).replace(os.sep, "/")
    _LOG.info("obvpm.h3: hunt candidate %s kept as %s", rel, new_rel)
    return new_rel


def discard(rel):
    """Delete the Run folder a candidate sits in: the takes not added, and
    their cached previews. Returns the output-relative folder removed."""
    root, ap = _candidate(rel, "discard")
    run_dir = os.path.dirname(ap)
    shutil.rmtree(run_dir)
    try:
        os.rmdir(os.path.dirname(run_dir))
    except OSError:
        pass
    gone = os.path.relpath(run_dir, root).replace(os.sep, "/")
    _LOG.info("obvpm.h3: discarded hunt %s", gone)
    return gone


def candidates_in(folder):
    """Every hunt candidate waiting under an output-relative project
    folder (all its Runs), output-relative paths, newest first. The seam
    browser offers them beside the folder's takes."""
    root = os.path.abspath(folder_paths.get_output_directory())
    base = os.path.abspath(os.path.join(root, str(folder or "").strip()))
    if os.path.commonpath([root, base]) != root:
        raise ValueError("hunt candidates: %r escapes the output folder"
                         % folder)
    hunts = os.path.join(base, CANDIDATE_DIR)
    found = []
    try:
        runs = os.listdir(hunts)
    except OSError:
        return []
    for run in runs:
        rd = os.path.join(hunts, run)
        if not os.path.isdir(rd):
            continue
        for name in os.listdir(rd):
            full = os.path.join(rd, name)
            if not (name.lower().endswith(".mp4")
                    and os.path.isfile(mctx.sidecar_path(full))):
                continue
            try:
                found.append((os.stat(full).st_mtime_ns, full))
            except OSError:
                continue
    found.sort(reverse=True)
    return [os.path.relpath(f, root).replace(os.sep, "/") for _t, f in found]


def runs_of(folder_abs, take_re, prefix=None):
    """[(run, [(full path, stat)])] of every Run folder under
    folder_abs/_candidates holding takes of the save prefix (`belongs`),
    newest Run first, each Run's takes by name (= take order)."""
    hunts = os.path.join(folder_abs, CANDIDATE_DIR)
    out = []
    try:
        runs = os.listdir(hunts)
    except OSError:
        return []
    for run in runs:
        rd = os.path.join(hunts, run)
        if not os.path.isdir(rd):
            continue
        takes = []
        for name in sorted(os.listdir(rd)):
            full = os.path.join(rd, name)
            if not (name.lower().endswith(".mp4")
                    and os.path.isfile(mctx.sidecar_path(full))
                    and belongs(full, take_re, prefix)):
                continue
            try:
                takes.append((full, os.stat(full)))
            except OSError:
                continue
        if takes:
            out.append((max(t[1].st_mtime_ns for t in takes), run, takes))
    out.sort(key=lambda r: r[0], reverse=True)
    return [(run, takes) for _t, run, takes in out]


def latest_hunt(folder_abs, take_re, prefix=None):
    """[(full path, stat)] of the candidates in the newest Run folder under
    folder_abs/_candidates that are the save prefix's, oldest name first."""
    runs = runs_of(folder_abs, take_re, prefix)
    return runs[0][1] if runs else []


class H3SeedHunt:
    CATEGORY = "obvpm/h3"
    FUNCTION = "hunt"
    RETURN_TYPES = ("INT", "BOOLEAN")
    RETURN_NAMES = ("seed", "hunting")
    DESCRIPTION = (
        "Seed hunting: one Run makes several takes from different seeds, "
        "so you can keep the best. Wire the timeline's hunt_count here "
        "and the seed output to the sampler's noise (and to the save "
        "node's seed). Everything between this node and the Result "
        "Preview the save feeds runs once per take, one take after the "
        "other -- sampled, decoded, saved and shown before the next "
        "starts -- while the models, the timeline and the pins run once. "
        "With a count of 1 it passes the seed straight through: one take, "
        "which waits among the candidates like a hunt's until it is kept "
        "or added."
    )
    OUTPUT_TOOLTIPS = (
        "This take's seed: the seed itself, then seed + 10000, "
        "seed + 20000, ... one per take.",
        "Always true: wire to the save node's hunting input, so every "
        "take -- a hunt's, or a single one -- is filed as a candidate in "
        "a folder of its Run until it is kept or added.",
    )

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "seed": ("INT", {
                    "default": 0, "min": 0, "max": _SEED_MAX,
                    "control_after_generate": True,
                    "tooltip": "The first take's seed. The others step "
                               "by 10000 from it, so a seed that "
                               "increments by one each Run never repeats "
                               "an earlier hunt's takes."}),
                "count": ("INT", {
                    "default": 1, "min": 1, "max": MAX_COUNT,
                    "tooltip": "How many takes one Run makes. Wire the "
                               "timeline's hunt_count, which its header's "
                               "hunt toggle sets. 1 = a single take, "
                               "still filed as a candidate."}),
            },
            "hidden": {"unique_id": "UNIQUE_ID", "dynprompt": "DYNPROMPT"},
        }

    def hunt(self, seed, count, unique_id=None, dynprompt=None):
        n = max(1, min(MAX_COUNT, int(count)))
        take = take_index(dynprompt, unique_id) if dynprompt else 0
        if unique_id is not None:
            _record(unique_id, take, n)
        if n > 1 and take == 0:
            _LOG.info("obvpm.h3: seed hunt: %d takes, seeds %s", n,
                      ", ".join(str(s) for s in hunt_seeds(seed, n)))
            if dynprompt is not None and not _closed(dynprompt, unique_id):
                _LOG.warning(
                    "obvpm.h3: seed hunt: no H3 Result Preview is fed by "
                    "this hunt's save node, so only the first take is "
                    "made -- the preview is what starts each next take")
        # every take waits as a candidate, a single one too: what has not
        # been decided on stays out of the project folder
        return (take_seed(seed, take), True)


def _closed(dynprompt, hid):
    """Does a Result Preview downstream of this Seed Hunt close its loop?"""
    for nid in dynprompt.all_node_ids():
        try:
            if dynprompt.get_node(nid)["class_type"] != CLOSER:
                continue
        except Exception:
            continue
        if hunt_of(dynprompt, nid) == hid:
            return True
    return False
