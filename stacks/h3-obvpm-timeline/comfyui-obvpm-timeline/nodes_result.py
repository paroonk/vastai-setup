"""H3ResultPreview: a run's take shown beside its lineage neighbor.

Wire the Save node's `path` output in; after the run the node's widget
shows a MINI timeline -- the fresh take together with the parent it
extends (parent first) or the clip it prepends (take first) -- and plays
the pair seamlessly through the same server-built smart-cut route the
Timeline node uses. The answer it exists for: "did this take actually
connect?", one glance, right where the generation happened.

Lineage is resolved server-side from the take's sidecar (parent_id ->
scan the take's folder for the matching sidecar); everything visual
happens in web/h3_mctx_ui.js from the ui payload returned here.
"""

import json
import logging
import os
import threading

import folder_paths

from . import frames as fr
from . import mctx

_LOG = logging.getLogger("obvpm.h3")


# Identifies the seam measurement in IS_CHANGED. "2" = phase-normalised
# latent scan + pixel-domain cut detection (2026-08-17). "3" = the cut
# detection judges an extend's opening ACROSS the join, against the
# parent's own motion, rather than against the take's later content
# (2026-08-24). "4" = the latent seam is measured at the pinned WINDOW
# edge rather than the trim point (a soft hold makes them differ, and
# the old reading swept the window opening and called it a cut), and a
# prepend's frame scan now gets its target's frames as the baseline the
# way an extend always got its parent's (2026-08-27). Bumped because the
# numbers a take was shown with are no longer the numbers it would get:
# without this, a take measured under an older rule keeps its stale
# verdict when the node is shown again.
_MEASURE_VERSION = "4"

_SEVERITY = {"seamless": 0, "soft bump": 1, "hard cut": 2}

# What a take was shown with, kept on disk beside it (in its folder's
# _previews): measuring a join decodes frames on both sides of it, seconds
# per take, and a take is shown again and again -- every earlier hunt
# picked from the Result Preview's list of runs, every workflow opened.
# Keyed by the file's size and time and _MEASURE_VERSION, so a changed
# file or a changed metric measures again.
_PAYLOAD_FILE = "obvpm_h3_payloads.json"
_PAYLOAD_LOCK = threading.Lock()


def _payload_store(ap):
    from .preview_route import PREVIEW_DIR
    return os.path.join(os.path.dirname(ap), PREVIEW_DIR, _PAYLOAD_FILE)


def _read_store(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _file_state(rel):
    """"size:mtime" of an output-relative file, or None when it is gone."""
    root = os.path.abspath(folder_paths.get_output_directory())
    try:
        st = os.stat(os.path.join(root, rel))
    except OSError:
        return None
    return "%d:%d" % (st.st_size, st.st_mtime_ns)


def _neighbours(item):
    return {nb: _file_state(nb) for nb in (item.get("parent"),
                                           item.get("parent2")) if nb}


def _stored_payload(ap, key):
    """The payload kept for this file state, or None. Its neighbours must
    be as they were too: the lineage and the join were judged against
    them, and a neighbour gone or replaced is judged again."""
    hit = _read_store(_payload_store(ap)).get(os.path.basename(ap))
    if not isinstance(hit, dict) or hit.get("key") != key:
        return None
    item = hit.get("payload")
    if not isinstance(item, dict):
        return None
    if hit.get("neighbours") != _neighbours(item):
        return None
    return item


def _store_payload(ap, key, item):
    path = _payload_store(ap)
    with _PAYLOAD_LOCK:
        data = _read_store(path)
        data[os.path.basename(ap)] = {"key": key, "payload": item,
                                      "neighbours": _neighbours(item)}
        # takes deleted or moved since leave
        folder = os.path.dirname(ap)
        data = {k: v for k, v in data.items()
                if os.path.isfile(os.path.join(folder, k))}
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            tmp = path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(data, f)
            os.replace(tmp, path)
        except OSError as exc:
            _LOG.info("obvpm.h3: could not keep the measurements of %s (%s)",
                      ap, exc)


def _severity(m):
    """How bad a measurement reads, for comparing the two metrics.

    Their ratios are on different scales (a latent ratio tops out near
    3, a pixel one reaches 17), so they are compared by verdict.
    """
    return _SEVERITY.get((m or {}).get("verdict"), -1)


def _pinned_window(meta, place):
    """Frames PINNED on one side, from the recipe (0 when none).

    Distinct from pinned_head/tail_frames, which are what was TRIMMED:
    with a soft hold the take delivers part of its window, so the two
    differ and only this one marks where generated content ends.
    """
    return sum(int(s.get("source_frames", 0) or 0)
               for s in mctx.parse_pins(meta)
               if s.get("place") == place)


def _measure_seam(side, which=None):
    """Measured seam quality where generated content meets pinned.

    Delegates the metric to seam_report.measure_seam (one implementation,
    so the node and the CLI report can never disagree): the worst
    adjacent-latent-step difference from the boundary through the next
    ~1s of GENERATED content, as a ratio of the clip's median step
    difference. Scanning past the boundary is what catches the common
    failure -- a run that holds the pinned window faithfully and only
    then breaks away looks perfect measured at the join alone.
    Metadata can only say the join coordinates line up; this says
    whether motion actually flows through them. ~1x = seamless, >>1x =
    the model planted the anchor and cut to it. `which` picks the
    boundary ("head"/"tail") for multi-pin takes; None derives it from
    the relation summary. Returns {"ratio", "verdict", "at", "boundary"}
    (`at` = seconds from the join to the worst point) or None when not
    measurable.
    """
    from .seam_report import measure_seam, verdict_for
    video, _audio, meta = mctx.load_sidecar(side)
    video = video.float()
    rel = meta.get("relation")
    # The boundary this metric wants is where GENERATED content meets
    # PINNED content -- the window edge. pinned_head/tail_frames are the
    # TRIM amounts, which a softly-held window makes smaller than the
    # window (the take delivers its ramped frames). Reading them as the
    # edge put the seam frames late, inside verbatim content, and the
    # backward scan then swept over the window opening and called it a
    # cut. Prefer the window from the recipe; fall back to the trim for
    # recipes that predate the pins list.
    head = _pinned_window(meta, "before") or int(
        meta.get("pinned_head_frames", 0) or 0)
    tail = _pinned_window(meta, "after") or int(
        meta.get("pinned_tail_frames", 0) or 0)
    lt = video.shape[2]
    if which is None:
        which = ("head" if rel == "extends" else
                 "tail" if rel == "prepends" else None)
    if which == "head" and head:
        # pinned run first: the generated content follows the boundary
        seam, into = fr.frames_to_latents(head) - 1, 1
    elif which == "tail" and tail:
        # generated first, pinned run last: look back from the boundary
        seam, into = lt - fr.frames_to_latents(tail) - 1, -1
    else:
        return None
    if not 0 <= seam < lt - 1:
        return None
    m = measure_seam(video, seam, into)
    if m is None:
        return None
    ratio = m["ratio"]
    return {
        "ratio": round(ratio, 2),
        "verdict": verdict_for(ratio),
        "at": round(m["at_frames"] / float(fr.FPS), 2),
        "boundary": round(m["boundary"], 2),
    }


def _join_context(parent_path, header, place):
    """(neighbour clip, the delivered frame the join sits at).

    What measure_cuts needs to judge a join against the motion on the
    OTHER side of it, rather than against the take's own content. An
    extend without it reads a take that joins mid-action and then
    settles as a lurch -- which is what extending from a trim point
    produces, since people cut where something is happening.

    A prepend needs it just as much, in mirror image: it ends by
    arriving at a clip that may be moving faster than it was, and
    measured against its own calmer opening that acceleration reads as
    a burst (clip_00085 scored 6.5x on a join the eye calls seamless).
    `place` says which end: "before" for an extend's opening, "after"
    for a prepend's close.
    """
    try:
        from .nodes_assemble import _extend_parent, _prepend_child
        # the same two readers assembly cuts with, so the frame measured
        # is the frame the viewer will actually see joined; both are
        # handover-aware and both fall through to the pins recipe when
        # the single-pin summary cannot express the take (a bridge)
        found = (_prepend_child(header) if place == "after"
                 else _extend_parent(header))
        if not found:
            return None
        head = int(mctx.read_header(
            mctx.sidecar_path(parent_path)).get(
                "pinned_head_frames", 0) or 0)
        join = int(found[1]) - head
        # 0 is a real answer for a prepend (a hard hold enters at the
        # target's own frame 0); measure_cuts falls back on its own if
        # too few frames come back.
        return (parent_path, join) if join >= 0 else None
    except Exception:
        return None


class H3ResultPreview:
    CATEGORY = "obvpm/h3"
    FUNCTION = "show"
    OUTPUT_NODE = True
    RETURN_TYPES = ()
    DESCRIPTION = (
        "Mini timeline of a just-saved take and the clip it continues: "
        "name the Set node carrying a Save node's path in "
        "result_constant, and after each run this shows the take beside "
        "its parent (extend) or its target (prepend), seam derived from "
        "the sidecars, playable as one seamless preview."
    )

    @classmethod
    def INPUT_TYPES(cls):
        return {
            # The save's path arrives on result_constant: the widget holds
            # the NAME of the Set node (KJNodes' Set) carrying it, and the
            # browser puts that Set node's feed in its place when the
            # prompt is made, as a KJ Get would (rpFillConstants) -- or ""
            # when it cannot, e.g. the save is muted for this Run (the
            # timeline mutes the half a Run does not use). With nothing,
            # the preview keeps showing what it showed.
            "optional": {
                "result_constant": ("STRING", {
                    "default": "gen_result",
                    "tooltip": "The name of the Set node (KJNodes' Set) "
                               "that carries the save's path. Empty: "
                               "nothing is shown."}),
            },
            # a seed hunt's loop closes here (nodes_hunt.next_take)
            "hidden": {"unique_id": "UNIQUE_ID", "dynprompt": "DYNPROMPT"},
        }

    @classmethod
    def IS_CHANGED(cls, result_constant=None, **_hidden):
        path = result_constant
        # The measurement version rides along so that changing how seams
        # are judged re-runs every preview once. Without it a clip whose
        # file has not moved keeps showing a verdict from the old metric
        # for good: the node is cached, and show() is never called again
        # (the widget's latest_result lookup is keyed on the same version,
        # so it re-judges too). Bump
        # _MEASURE_VERSION whenever the numbers or thresholds change.
        try:
            st = os.stat(cls._abs(path))
            return "%s:%d:%d" % (_MEASURE_VERSION, st.st_size, st.st_mtime_ns)
        except (OSError, ValueError):
            return "absent:" + _MEASURE_VERSION

    @staticmethod
    def _abs(path):
        p = str(path or "").strip()
        if not os.path.isabs(p):
            p = os.path.join(folder_paths.get_output_directory(), p)
        return os.path.abspath(p)

    def show(self, result_constant=None, unique_id=None, dynprompt=None):
        # by now the save's path: the browser put the named Set node's
        # feed on result_constant when the prompt was made
        out = self._show(result_constant)
        # In a seed hunt, this take is shown and the next one starts: the
        # nodes between H3 Seed Hunt and here run again for it, and this
        # preview's copy shows it in turn (nodes_hunt.next_take).
        from . import nodes_hunt
        st = nodes_hunt.hunt_state(dynprompt, unique_id)
        if st is None:
            return out
        _hid, take, count = st
        for item in out["ui"].get("h3_result", []):
            if item.get("candidate"):
                item.update(hunt_run=nodes_hunt.run_id(), hunt_index=take,
                            hunt_count=count)
        graph = nodes_hunt.next_take(dynprompt, unique_id)
        if graph:
            out["result"] = ()
            out["expand"] = graph
        return out

    def _show(self, path=None):
        """_measure(path), or what it gave for this file state before."""
        if not path:
            return {"ui": {}}
        root = os.path.abspath(folder_paths.get_output_directory())
        ap = self._abs(path)
        if os.path.commonpath([root, ap]) != root or not os.path.isfile(ap):
            return self._measure(path)          # says what is wrong
        st = os.stat(ap)
        key = "%d:%d:%s" % (st.st_size, st.st_mtime_ns, _MEASURE_VERSION)
        hit = _stored_payload(ap, key)
        if hit is not None:
            return {"ui": {"h3_result": [hit]}}
        out = self._measure(path)
        items = out["ui"].get("h3_result") or []
        if items:
            _store_payload(ap, key, items[0])
        return out

    def _measure(self, path):
        root = os.path.abspath(folder_paths.get_output_directory())
        ap = self._abs(path)
        if os.path.commonpath([root, ap]) != root:
            raise ValueError(
                "H3ResultPreview: %s is outside the output folder" % path)
        if not os.path.isfile(ap):
            raise ValueError("H3ResultPreview: clip not found: %s" % path)
        rel = os.path.relpath(ap, root).replace(os.sep, "/")

        relation, parent_rel, parent2_rel = "", None, None
        seam, seam2 = None, None
        from .nodes_hunt import is_candidate
        candidate = is_candidate(rel)
        seed = None
        prefix = None   # the save prefix the take recorded
        render = None   # "joint" for a rendered cut (H3 Joint VAE Decode and Save)

        def _clip_for(pid, recorded_path=None):
            """The parent clip, output-relative. None when not findable.

            Two routes, because a parent does not have to own a sidecar:
            the usual one scans the folder for the sidecar whose self_id
            matches, and the fallback follows the path the pins recipe
            recorded -- which is how a take reaches the plain video it
            was encoded from. The hash still decides: a file at that path
            that is not the file we pinned is not the parent.
            """
            pside = mctx.scan_for_parent(os.path.dirname(ap), pid)
            if not pside and candidate:
                # a hunt candidate waits in its Run's folder under
                # _candidates; its parent sits with the other takes
                from .nodes_hunt import home_of
                pside = mctx.scan_for_parent(home_of(ap), pid)
            if pside:
                pclip = pside[:-len(mctx.SIDECAR_SUFFIX)] + ".mp4"
                if os.path.isfile(pclip):
                    return os.path.relpath(pclip, root).replace(os.sep, "/")
            if not recorded_path:
                return None
            cand = os.path.abspath(os.path.join(root, recorded_path))
            if os.path.commonpath([root, cand]) != root:
                return None
            if not os.path.isfile(cand):
                return None
            from .nodes_load import _cached_hash
            if pid and _cached_hash(cand) != pid:
                _LOG.warning("obvpm.h3: %s records a parent at %s, but that "
                             "file has changed since; previewing the take "
                             "alone", rel, recorded_path)
                return None
            return os.path.relpath(cand, root).replace(os.sep, "/")

        def _recorded_path(pins, place):
            for s in pins:
                if s.get("place") == place and s.get("source_path"):
                    return s["source_path"]
            return None

        side = mctx.sidecar_path(ap)
        if os.path.isfile(side):
            try:
                header = mctx.read_header(side)
                relation = header.get("relation") or ""
                prefix = header.get("save_prefix") or None
                try:
                    seed = int(header["seed"]) if header.get("seed") else None
                except (TypeError, ValueError):
                    seed = None
                try:
                    render = (json.loads(header.get("user_meta") or "{}")
                              or {}).get("render") or None
                except (TypeError, ValueError):
                    render = None
                pid = header.get("parent_id") or ""
                if not relation:
                    # multi-pin take: derive lineage from the pins
                    # recipe (a BRIDGE has a before-parent it extends
                    # and an after-parent it prepends into)
                    pins = mctx.parse_pins(header)
                    bpin = next((p for p in pins
                                 if p.get("place") == "before" and
                                 p.get("source_kind") in mctx.LINEAGE_KINDS
                                 and p.get("source_id")), None)
                    apin = next((p for p in pins
                                 if p.get("place") == "after" and
                                 p.get("source_kind") in mctx.LINEAGE_KINDS
                                 and p.get("source_id")), None)
                    if bpin and apin:
                        relation = "bridges"
                        parent_rel = _clip_for(bpin["source_id"],
                                               bpin.get("source_path"))
                        parent2_rel = _clip_for(apin["source_id"],
                                                apin.get("source_path"))
                        try:
                            seam = _measure_seam(side, "head")
                            seam2 = _measure_seam(side, "tail")
                        except Exception:
                            _LOG.exception("obvpm.h3: seam measurement "
                                           "failed for %s", rel)
                if relation in ("extends", "prepends"):
                    try:
                        seam = _measure_seam(side)
                    except Exception:
                        _LOG.exception(
                            "obvpm.h3: seam measurement failed for %s", rel)
                    if pid:
                        parent_rel = _clip_for(
                            pid, _recorded_path(
                                mctx.parse_pins(header),
                                "before" if relation == "extends"
                                else "after"))
            except Exception:
                _LOG.exception(
                    "H3ResultPreview: unreadable sidecar for %s", rel)

        # The latent metric cannot see a jump cut -- one latent step spans
        # 3.4 frames, so a single-frame jump averages away inside it. Look
        # at the delivered frames too, which is what actually gets watched,
        # and let the worse of the two speak. Only the take's opening is
        # covered, which is where an extend joins; a prepend joins at its
        # end and still relies on the latent number alone.
        # Which end carries the join: an extend begins at its parent, a
        # prepend runs INTO its target so the failure shows at its close,
        # and a bridge has one of each.
        if relation in ("extends", "prepends", "bridges"):
            try:
                from .seam_report import measure_cuts
                if relation == "bridges":
                    scans = (("start", "seam"), ("end", "seam2"))
                elif relation == "prepends":
                    scans = (("end", "seam"),)
                else:
                    scans = (("start", "seam"),)
                for where, slot in scans:
                    # The neighbour's own frames are the baseline a join
                    # is judged against, in BOTH directions: an extend
                    # opens at its parent, a prepend closes into its
                    # target. Which neighbour depends on the end -- a
                    # bridge has a different one at each.
                    nb = (parent2_rel if where == "end" and parent2_rel
                          else parent_rel)
                    ctx = (_join_context(
                        self._abs(nb), header,
                        "after" if where == "end" else "before")
                        if nb else None)
                    cuts = measure_cuts(ap, where=where, context=ctx)
                    current = seam if slot == "seam" else seam2
                    # Worse-of-the-two, EXCEPT when the frame scan had
                    # the parent to compare against: then it is the only
                    # measurement that actually spans the join, while the
                    # latent one still judges the opening against the
                    # take's own later content -- which reads any join
                    # into a moving moment as a break. The latent ratio
                    # rides along either way.
                    if cuts and (ctx or
                                 _severity(cuts) > _severity(current)):
                        cuts["latent"] = current and current.get("ratio")
                        if slot == "seam":
                            seam = cuts
                        else:
                            seam2 = cuts
            except Exception:
                _LOG.exception("obvpm.h3: cut scan failed for %s", rel)

        if relation == "bridges":
            parts = ([parent_rel] if parent_rel else []) + [rel] + \
                ([parent2_rel] if parent2_rel else [])
            sequence = "\n".join(parts)
        elif parent_rel and relation == "extends":
            sequence = parent_rel + "\n" + rel
        elif parent_rel and relation == "prepends":
            sequence = rel + "\n" + parent_rel
        else:
            sequence = rel
        if parent_rel is None and relation in ("extends", "prepends"):
            _LOG.warning("obvpm.h3: %s %s a parent whose clip could not be "
                         "found (not in its folder, and no recorded path "
                         "leads to it); previewing the take alone",
                         rel, relation)
        # the take's file time, by the SERVER's clock: a preview that was
        # cleared (delete, dismiss) remembers the time of what it cleared
        # and shows a take on open only when it is newer. Names cannot say
        # that -- a deleted take's number is reused by the next save.
        try:
            mtime_ms = os.stat(ap).st_mtime_ns // 1_000_000
        except OSError:
            mtime_ms = None
        return {"ui": {"h3_result": [{
            "clip": rel, "parent": parent_rel, "parent2": parent2_rel,
            "relation": relation, "sequence": sequence,
            "seam": seam, "seam2": seam2, "render": render,
            "mtime_ms": mtime_ms,
            # a seed hunt's take: shown among its Run's other candidates,
            # and moved out of its Run's folder when it is added
            "seed": seed, "candidate": candidate, "prefix": prefix,
        }]}}


class H3UpscalePreview:
    """The finished upscale, played as it is.

    A rendered cut (H3 Joint VAE Decode and Save) is the end product: it
    has no parent to sit beside, no seam to judge and no timeline to go
    into, so this node only plays the file.
    """

    CATEGORY = "obvpm/h3"
    FUNCTION = "show"
    OUTPUT_NODE = True
    RETURN_TYPES = ()
    DESCRIPTION = (
        "Plays a finished upscale: name the Set node carrying the path "
        "of H3 Joint VAE Decode and Save in result_constant. Shows the "
        "rendered file itself (nothing is rebuilt or re-encoded), with "
        "delete and dismiss. When the workflow is opened it shows the "
        "newest upscale that save writes."
    )

    @classmethod
    def INPUT_TYPES(cls):
        return {
            # as the take preview's: the path arrives on result_constant,
            # or "" when the render's save is muted for a Run (generation)
            "optional": {
                "result_constant": ("STRING", {
                    "default": "upscale_result",
                    "tooltip": "The name of the Set node (KJNodes' Set) "
                               "that carries the render's path. Empty: "
                               "nothing is shown."}),
            },
        }

    @classmethod
    def IS_CHANGED(cls, result_constant=None, **_kw):
        path = result_constant
        if not path:
            return "none"
        try:
            st = os.stat(H3ResultPreview._abs(path))
            return "%d:%d" % (st.st_size, st.st_mtime_ns)
        except (OSError, ValueError):
            return "absent"

    def show(self, result_constant=None):
        path = result_constant      # the browser put the path here
        if not path:
            return {"ui": {}}
        root = os.path.abspath(folder_paths.get_output_directory())
        ap = H3ResultPreview._abs(path)
        if os.path.commonpath([root, ap]) != root:
            raise ValueError(
                "H3UpscalePreview: %s is outside the output folder" % path)
        if not os.path.isfile(ap):
            raise ValueError("H3UpscalePreview: file not found: %s" % path)
        rel = os.path.relpath(ap, root).replace(os.sep, "/")
        try:
            mtime_ms = os.stat(ap).st_mtime_ns // 1_000_000
        except OSError:
            mtime_ms = None
        return {"ui": {"h3_upscale": [{"clip": rel, "mtime_ms": mtime_ms}]}}


# ---------------------------------------------------------------------------
# what a Result Preview shows when its workflow is opened
#
# Its result is not stored in the workflow any more: that made every
# finished run an undo step (and an undo brought an older result back),
# changed the file on every run, and shipped the author's last result in
# every workflow they shared. So a preview that opens with nothing from
# this session asks for the newest take its Save node writes: the newest
# `<prefix>_NNNNN.mp4` -- a joint render's `_s01` segments and an HQ
# copy's `<prefix>_hq_...` do not match -- judged exactly as a run would
# have judged it (show()). Cached per file state, because the seam
# measurement decodes frames and a workflow is opened far more often
# than a take changes.
# ---------------------------------------------------------------------------

_LATEST_CACHE = {}
_LATEST_CACHE_MAX = 64


def _prefix_place(prefix, what):
    """(normalised prefix, root, its folder, the save's own take names) of
    a save prefix ("folder/name", output-relative), or None."""
    import posixpath
    import re
    p = str(prefix or "").replace("\\", "/").strip().strip("/")
    if not p:
        return None
    folder, base = posixpath.split(p)
    if not base:
        return None
    root = os.path.abspath(folder_paths.get_output_directory())
    d = os.path.abspath(os.path.join(root, folder))
    if os.path.commonpath([root, d]) != root:
        raise ValueError("%s: %r escapes the output folder" % (what, prefix))
    if not os.path.isdir(d):
        return None
    return p, root, d, re.compile(r"^%s_\d+\.mp4$" % re.escape(base))


def _payload(root, full, st):
    """What a run would have shown for one take, cached per file state."""
    rel = os.path.relpath(full, root).replace(os.sep, "/")
    key = (rel, st.st_size, st.st_mtime_ns, _MEASURE_VERSION)
    hit = _LATEST_CACHE.get(key)
    if hit is None:
        hit = H3ResultPreview().show(rel)["ui"]["h3_result"][0]
        _LATEST_CACHE[key] = hit
        while len(_LATEST_CACHE) > _LATEST_CACHE_MAX:
            _LATEST_CACHE.pop(next(iter(_LATEST_CACHE)))
    return hit


def _hunt_payload(root, run, takes, extras=()):
    hunt = [dict(_payload(root, full, st), hunt_index=k, hunt_folder=run)
            for k, (full, st) in enumerate(takes)]
    # another pack's takes come after the Run's own, in their own order
    for k, item in enumerate(extras):
        hunt.append(dict(item, hunt_index=item.get("hunt_index", len(takes) + k),
                         hunt_folder=run))
    hunt.sort(key=lambda h: h["hunt_index"])
    return dict(hunt[0], hunt=hunt, hunt_folder=run)


def run_extras(run_dir, prefix):
    """Takes of another kind that another pack keeps in a Run's folder: a
    node class with an `obvpm_run_takes(run_dir, prefix)` classmethod is
    asked for each Run, and the payloads it returns (each with its
    output-relative `clip` and `mtime_ms`, shown as they are) join the
    Run's takes. Asked of the classes ComfyUI has loaded, so the order
    the packs load in does not matter."""
    import sys
    nodes = sys.modules.get("nodes")
    out = []
    seen = set()
    for cls in list(getattr(nodes, "NODE_CLASS_MAPPINGS", {}).values()):
        fn = getattr(cls, "obvpm_run_takes", None)
        key = getattr(fn, "__func__", fn)
        if fn is None or key in seen:
            continue
        seen.add(key)
        try:
            out.extend(fn(run_dir, prefix) or [])
        except Exception:
            _LOG.warning("obvpm.h3: %s could not list the takes in %s",
                         getattr(cls, "__name__", cls), run_dir, exc_info=True)
    return out


def _waiting_runs(prefix, what):
    """(root, [(run, takes, extras, newest ms)]) of the Runs waiting under
    a save prefix, newest first -- its own takes (nodes_hunt.runs_of) and
    any other pack's (run_extras) -- or None when the prefix has no folder."""
    from .nodes_hunt import CANDIDATE_DIR, runs_of
    place = _prefix_place(prefix, what)
    if place is None:
        return None
    p, root, d, take = place
    own = dict(runs_of(d, take, p))
    hunts = os.path.join(d, CANDIDATE_DIR)
    try:
        names = [n for n in os.listdir(hunts)
                 if os.path.isdir(os.path.join(hunts, n))]
    except OSError:
        names = []
    out = []
    for run in names:
        takes = own.get(run, [])
        extras = run_extras(os.path.join(hunts, run), p)
        if not takes and not extras:
            continue
        newest = max([t[1].st_mtime_ns // 1_000_000 for t in takes]
                     + [int(x.get("mtime_ms") or 0) for x in extras])
        out.append((run, takes, extras, newest))
    out.sort(key=lambda r: r[3], reverse=True)
    return root, out


def hunt_runs(prefix):
    """The seed hunts still waiting under a save prefix, newest first:
    [{"run": folder name, "takes": count, "mtime_ms": newest take,
    "noun": what they are}] -- "take", or the `noun` every take of the Run
    names itself by (another pack's kind: "draft")."""
    found = _waiting_runs(prefix, "hunt_runs")
    if found is None:
        return []
    out = []
    for run, takes, extras, newest in found[1]:
        nouns = {x.get("noun") or "take" for x in extras}
        if takes:
            nouns.add("take")
        out.append({"run": run, "takes": len(takes) + len(extras),
                    "mtime_ms": newest,
                    "noun": nouns.pop() if len(nouns) == 1 else "take"})
    return out


def hunt_run(prefix, run):
    """The payload of one waiting seed hunt (as a run shows it), or None."""
    found = _waiting_runs(prefix, "hunt_run")
    if found is None:
        return None
    root, runs = found
    for name, takes, extras, _newest in runs:
        if name == str(run):
            return _hunt_payload(root, name, takes, extras)
    return None


def latest_result(prefix):
    """The payload a run would have shown for the newest take under
    `prefix` ("folder/name", output-relative), or None."""
    place = _prefix_place(prefix, "latest_result")
    if place is None:
        return None
    p, root, d, take = place

    def takes_in(folder):
        """[(full path, stat)] of the takes in `folder`, by name."""
        out = []
        try:
            names = sorted(os.listdir(folder))
        except OSError:
            return out
        for name in names:
            if not take.match(name):
                continue
            full = os.path.join(folder, name)
            try:
                out.append((full, os.stat(full)))
            except OSError:
                continue
        return out

    takes = takes_in(d)
    best = max(takes, key=lambda t: t[1].st_mtime_ns, default=None)
    # A seed hunt still waiting for its pick: the takes of the newest
    # Run folder under _candidates. Newer than the newest take, they are what
    # the preview was showing -- side by side, as the Run left them.
    runs = _waiting_runs(p, "latest_result")[1]
    if runs and (best is None
                 or runs[0][3] > best[1].st_mtime_ns // 1_000_000):
        run, cands, extras, _newest = runs[0]
        return _hunt_payload(root, run, cands, extras)
    if best is None:
        return None
    return _payload(root, *best)
