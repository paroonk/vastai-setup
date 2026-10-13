"""Two-stage generation: a small first stage, a latent upscale, a full-size
second stage that finishes it.

The first stage samples the start of the schedule at a fraction of the
size, where composition and motion are cheap and H3 invents fine texture
consistently; its x0 is latent-upscaled to the full size and the second
stage re-noises it to where its own schedule starts and finishes it. The
three nodes here are the pieces the stock nodes do not cover:

  * H3SamplingSchedule -- the sigmas of one stage or of both, from one set
    of engine settings: the full schedule, its first or last steps, or
    typed sigmas. Single stage, it is BasicScheduler line for line on
    `full`, so a workflow that never turns dual_stage on samples exactly
    what it did before.
  * H3MCtxPinsFromPixels -- the first stage is smaller than the clip it
    continues, and a latent cannot be resized, so its pins are re-encoded
    from the parent's frames at the first stage's size (the pixel route
    Apply already has), SQUASHED onto it as the latent upscale will
    stretch it back. The second stage pins the parent's own latents, so
    the join the take is saved with is exact as before.
  * H3StageLatent -- the upscaled video with the first stage's audio, and
    no denoise mask: Apply lays the second stage's own pins.
"""

import logging
import math
import re

import torch

import comfy.samplers

from . import wiretypes as wt
from .avpack import pack_av, unpack_av

_LOG = logging.getLogger("obvpm.h3")

SCHEDULES = ["full", "first_x_steps", "last_x_steps", "step_range", "manual"]

# a first stage's size is rounded to this, as the generation sizes are
SIZE_MULTIPLE = 32

# picking a first stage's size: how far a side may stray from the asked
# scale, and what a change in pixel count weighs against a change in shape
# (a 1% squash costs as much as 4% more or fewer pixels)
SCALE_SLACK = 0.1
PIXELS_WEIGHT = 0.25

# the three schedules a run can name: (field prefix, its defaults)
STAGES = {
    "": {"schedule": "full"},
    "first_stage_": {"schedule": "first_x_steps"},
    "second_stage_": {"schedule": "last_x_steps"},
}
_PER_STAGE = ("schedule", "x_steps", "from_step", "to_step", "sigmas",
              "extra_steps")
_DEFAULTS = {"x_steps": 4, "from_step": 1, "to_step": 4, "sigmas": "",
             "extra_steps": 0}

_NUMBER = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")


def parse_sigmas(text, what="sigmas"):
    """Typed sigmas -> a list of floats. Any separators: commas, spaces,
    new lines, brackets ("[1.0, 0.9, ...]" pasted from a log works)."""
    leftover = _NUMBER.sub(" ", str(text or ""))
    odd = re.sub(r"[\s,;\[\]()]+", "", leftover)
    if odd:
        raise ValueError(
            "H3 Sampling Schedule: %s has text that is not a number (%r). "
            "Type the sigmas as numbers separated by commas, from high to "
            "low, for example 1.0, 0.95, 0.8, 0.0" % (what, odd[:20]))
    values = [float(v) for v in _NUMBER.findall(str(text or ""))]
    if len(values) < 2:
        raise ValueError(
            "H3 Sampling Schedule: %s needs at least two sigmas (one "
            "step goes from the first to the second); got %d."
            % (what, len(values)))
    return values


def slice_steps(n_steps, schedule, x_steps=4, from_step=1, to_step=4):
    """The slice of an n_steps curve (n_steps + 1 sigmas) that `schedule`
    keeps: first_x_steps -> the first x steps, last_x_steps -> the last x,
    step_range -> steps from_step..to_step (1 = the first step). Clamped
    to the curve, never empty."""
    n_steps = int(n_steps)
    if schedule == "step_range":
        a = max(1, min(int(from_step), n_steps))
        b = max(a, min(int(to_step), n_steps))
        if (a, b) != (int(from_step), int(to_step)):
            _LOG.warning("obvpm.h3: step_range %d-%d of %d steps; using %d-%d",
                         int(from_step), int(to_step), n_steps, a, b)
        return slice(a - 1, b + 1)
    x = max(1, min(int(x_steps), n_steps))
    if x != int(x_steps):
        _LOG.warning("obvpm.h3: %s of %d steps wants %d; using %d",
                     schedule, n_steps, int(x_steps), x)
    if schedule == "last_x_steps":
        return slice(n_steps - x, n_steps + 1)
    return slice(0, x + 1)


def add_extra_steps(sigmas, extra):
    """The last step split into `extra` + 1 equal ones: 0.235 -> 0 with
    one extra step runs 0.235 -> 0.1175 -> 0."""
    extra = int(extra or 0)
    if extra <= 0 or len(sigmas) < 2:
        return sigmas
    a, b = float(sigmas[-2]), float(sigmas[-1])
    inner = torch.tensor([a + (b - a) * k / (extra + 1)
                          for k in range(1, extra + 1)], dtype=sigmas.dtype)
    return torch.cat([sigmas[:-1], inner, sigmas[-1:]])


def basic_sigmas(model, scheduler, steps, denoise=1.0):
    """comfy_extras BasicScheduler, line for line."""
    total_steps = steps
    if denoise < 1.0:
        if denoise <= 0.0:
            return torch.FloatTensor([])
        total_steps = int(steps / denoise)
    sigmas = comfy.samplers.calculate_sigmas(
        model.get_model_object("model_sampling"), scheduler,
        total_steps).cpu()
    return sigmas[-(steps + 1):]


def stage_sigmas(curve, fields, prefix, steps):
    """One schedule's sigmas. `curve` is the scheduler's (refine_amount
    already applied: it shapes the curve before anything is cut from it);
    `fields` the settings, `prefix` which schedule ("" / first_stage_ /
    second_stage_). Typed sigmas are taken exactly as typed."""
    what = prefix + "schedule"
    get = lambda name: _given(fields.get(prefix + name),
                              _DEFAULTS.get(name, STAGES[prefix].get(name)))
    schedule = get("schedule")
    if schedule == "manual":
        return torch.FloatTensor(parse_sigmas(get("sigmas"), prefix + "sigmas"))
    if schedule not in SCHEDULES:
        raise ValueError(
            "H3 Sampling Schedule: unknown %s %r; it is one of %s."
            % (what, schedule, ", ".join(SCHEDULES)))
    out = curve
    if schedule != "full" and len(curve):
        out = curve[slice_steps(steps, schedule, get("x_steps"),
                                get("from_step"), get("to_step"))]
    return add_extra_steps(out, get("extra_steps"))


def shape_error(width, height, w1, h1):
    """How far w1 x h1 is from the shape of width x height: 0.063 is 6.3%."""
    return abs(math.log((w1 / float(h1)) / (width / float(height))))


def stage_size(width, height, scale):
    """A first stage's (width, height): about `scale` of the video's, on
    the 32 grid, in the video's shape as nearly as the grid allows.

    Rounding each side alone changes the shape: 960x544 at 0.5 is
    480x272, and 272 is not on the grid, so it was 480x256 -- 6% wider
    than the video. The latent upscale maps the first stage onto the
    video corner to corner, so everything came out 6% taller, and an
    extend jumped at its seam, where the second stage's exact pins meet
    it. Sides within SCALE_SLACK of the scale are tried, and the size
    closest in shape wins, a change in pixel count weighing
    PIXELS_WEIGHT: 960x544 at 0.5 gets 512x288, 0.7% off. The rest of
    the error the first stage's pins carry (squashed onto this size,
    see H3MCtxPinsFromPixels), so the upscale undoes it exactly."""
    m = SIZE_MULTIPLE
    width, height = int(width), int(height)

    def plain(v):
        return max(1, int(round(v * scale / m)))

    def near(v):
        lo = max(1, int(math.ceil(v * scale * (1 - SCALE_SLACK) / m)))
        hi = int(math.floor(v * scale * (1 + SCALE_SLACK) / m))
        return lo, max(lo, min(hi, max(1, v // m)))

    sizes = {(plain(width), plain(height))}
    w_lo, w_hi = near(width)
    h_lo, h_hi = near(height)
    for wu in range(w_lo, w_hi + 1):
        hv = wu * height / float(width)
        for hu in {int(math.floor(hv)), int(math.ceil(hv))}:
            if h_lo <= hu <= h_hi:
                sizes.add((wu, hu))
    target = width * height * scale * scale

    def cost(wh):
        w1, h1 = wh[0] * m, wh[1] * m
        return (shape_error(width, height, w1, h1)
                + PIXELS_WEIGHT * abs(math.log(w1 * h1 / target)),
                wh)
    wu, hu = min(sizes, key=cost)
    return wu * m, hu * m


def _given(value, default):
    # a Value Presets field hidden by its `when` (or switched off on its
    # node) arrives as None
    return default if value is None else value


def _sigma_text(sigmas):
    return ", ".join("%.3f" % float(s) for s in sigmas)


def compute_schedule(model, scheduler, steps, fields):
    """What H3 Sampling Schedule samples, without its logging: {"dual",
    "sigmas" (the run's, or the second stage's), "first" (the first
    stage's; None single stage), "scale", "denoise", "second_renoises"}. `fields` holds the settings by
    name; one that is None takes its default.

    `refine_amount` (the upscale's; switched off on the generation's node)
    is BasicScheduler's denoise, and applied FIRST: the curve is the last
    `steps` of a longer schedule, and the schedule choice cuts from that.
    The node's own `denoise` stands in when the settings have none.

    Other packs plan schedules with this, basic_sigmas, STAGES and _given
    (found through the H3SamplingSchedule node id): keep their
    signatures."""
    steps = int(steps)
    denoise = float(_given(fields.get("refine_amount"),
                           _given(fields.get("denoise"), 1.0)))
    curve = basic_sigmas(model, scheduler, steps, denoise)
    if not _given(fields.get("dual_stage"), False):
        return {"dual": False, "sigmas": stage_sigmas(curve, fields, "", steps),
                "first": None, "scale": 1.0, "denoise": denoise,
                "second_renoises": False}
    first = stage_sigmas(curve, fields, "first_stage_", steps)
    second = stage_sigmas(curve, fields, "second_stage_", steps)
    return {"dual": True, "sigmas": second, "first": first,
            "scale": float(_given(fields.get("first_stage_scale"), 0.5)),
            "denoise": denoise,
            "second_renoises": len(second) > 0 and float(second[0]) >= 0.999}


# H3 Sampling Schedule's widgets that a wired `settings` replaces (all but
# width and height); a test keeps this in step with its inputs
_FROM_SETTINGS = (
    "scheduler", "steps", "schedule", "x_steps", "sigmas", "denoise",
    "dual_stage", "first_stage_scale", "first_stage_schedule",
    "first_stage_x_steps", "first_stage_sigmas", "second_stage_schedule",
    "second_stage_x_steps", "second_stage_sigmas", "from_step", "to_step",
    "first_stage_from_step", "first_stage_to_step", "second_stage_from_step",
    "second_stage_to_step", "extra_steps", "first_stage_extra_steps",
    "second_stage_extra_steps")


class H3SamplingSchedule:
    CATEGORY = "obvpm/h3"
    FUNCTION = "plan"
    # the first stage's outputs together, dual_stage last (0.3.0 -- a
    # save with the old order is rewired by name in the browser,
    # web/h3_sampling_schedule.js)
    RETURN_TYPES = ("SIGMAS", "SIGMAS", "INT", "INT", "BOOLEAN")
    RETURN_NAMES = ("sigmas", "first_stage_sigmas", "first_stage_width",
                    "first_stage_height", "dual_stage")
    DESCRIPTION = (
        "The sigmas a run samples, from one set of engine settings -- wire "
        "the settings bundle to `settings` (it then replaces the widgets, "
        "which hide), or set the widgets. "
        "schedule picks them: full = the scheduler's whole curve; "
        "first_x_steps / last_x_steps = only that end of it; step_range = "
        "steps from_step..to_step; manual = the sigmas you type. "
        "refine_amount (the upscale's) shapes the curve first, as "
        "BasicScheduler's denoise; extra_steps splits the last step into "
        "equal ones. With dual_stage on, the run is two stages: the first "
        "samples first_stage_sigmas at first_stage_scale of the size, its "
        "result is latent-upscaled, and the second samples `sigmas` at the "
        "full size from there. Fields hidden or left out take their defaults."
    )
    OUTPUT_TOOLTIPS = (
        "The sigmas of the run, or of its second stage when dual_stage is "
        "on.",
        "The first stage's sigmas when dual_stage is on (otherwise the "
        "same as sigmas).",
        "The first stage's width: about width x first_stage_scale, on the "
        "32 pixel grid, picked to keep the video's shape.",
        "The first stage's height, likewise.",
        "Whether the run is two stages. Drives the switch between the "
        "upscaled first stage and the plain empty latent.",
    )

    @classmethod
    def INPUT_TYPES(cls):
        schedule_tip = (
            "full: the scheduler's whole curve. first_x_steps / "
            "last_x_steps: only the first or last x steps of it. "
            "step_range: steps from_step to to_step. manual: the sigmas "
            "typed below.")
        step = lambda d: ("INT", {"default": d, "min": 1, "max": 10000})
        extra = ("INT", {"default": 0, "min": 0, "max": 64,
                         "tooltip": "Split the last step into this many "
                                    "more equal steps."})
        return {
            "required": {
                "model": ("MODEL", {
                    "tooltip": "The model the run samples with: its sigma "
                               "shift decides the schedule."}),
                "scheduler": (comfy.samplers.SCHEDULER_NAMES,),
                "steps": ("INT", {"default": 20, "min": 1, "max": 10000,
                                  "tooltip": "Steps of the curve the x "
                                             "steps and step ranges are "
                                             "counted in."}),
                "schedule": (SCHEDULES, {
                    "default": "full",
                    "tooltip": "Single stage. " + schedule_tip}),
                "x_steps": step(4),
                "sigmas": ("STRING", {"default": ""}),
                "denoise": ("FLOAT", {
                    "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.01,
                    "tooltip": "As BasicScheduler's: shapes the curve "
                               "before any steps are cut from it. The "
                               "settings' refine_amount takes its place "
                               "when they have one."}),
            },
            "optional": {
                "dual_stage": ("BOOLEAN", {"default": False}),
                "first_stage_scale": ("FLOAT", {
                    "default": 0.5, "min": 0.05, "max": 1.0, "step": 0.05,
                    "tooltip": "The first stage's width and height as a "
                               "fraction of the video's -- about: the size "
                               "lands on the 32 pixel grid in the video's "
                               "shape, so 960x544 at 0.5 runs 512x288. "
                               "0.5 is the latent upscaler's own 2x; 0.7 "
                               "is about half the pixels."}),
                "first_stage_schedule": (SCHEDULES, {
                    "default": "first_x_steps",
                    "tooltip": "Before the latent upscale. "
                               + schedule_tip}),
                "first_stage_x_steps": step(4),
                "first_stage_sigmas": ("STRING", {"default": ""}),
                "second_stage_schedule": (SCHEDULES, {
                    "default": "last_x_steps",
                    "tooltip": "After the latent upscale. "
                               + schedule_tip}),
                "second_stage_x_steps": step(4),
                "second_stage_sigmas": ("STRING", {"default": ""}),
                "width": ("INT", {
                    "default": 0, "min": 0, "max": 16384, "step": 32,
                    "tooltip": "The video's width. Only dual_stage reads "
                               "it."}),
                "height": ("INT", {
                    "default": 0, "min": 0, "max": 16384, "step": 32}),
                # from here on: inputs after the first release. Always
                # appended -- widgets_values is positional, and a node
                # saved before holds only the inputs above
                "from_step": step(1),
                "to_step": step(4),
                "first_stage_from_step": step(1),
                "first_stage_to_step": step(4),
                "second_stage_from_step": step(5),
                "second_stage_to_step": step(8),
                "extra_steps": extra,
                "first_stage_extra_steps": extra,
                "second_stage_extra_steps": extra,
                "settings": ("OBVPM_BUNDLE", {
                    "tooltip": "The engine settings (a Value Presets "
                               "bundle). While it is wired, the schedule "
                               "comes from it alone -- the widgets it "
                               "replaces are hidden, and a field it lacks "
                               "takes its default; its refine_amount "
                               "replaces denoise. width and height stay on "
                               "the node. One wire instead of twenty.",
                    # the widgets the bundle replaces, for the UI to hide
                    "obvpm_replaces": cls._from_settings()}),
            },
        }

    @classmethod
    def _from_settings(cls):
        """The inputs a wired `settings` replaces: every widget but the
        video's size (which the workflow wires from its input)."""
        return list(_FROM_SETTINGS)

    def plan(self, model, scheduler, steps, settings=None, width=0, height=0,
             **fields):
        if settings:
            # the bundle alone, by name: a field it lacks, or holds as None
            # (hidden, or switched off on its node), takes its default --
            # the widgets are hidden, so none of them may decide the run
            bundle = dict(settings)
            steps = int(_given(bundle.get("steps"), 20))
            scheduler = _given(bundle.get("scheduler"),
                               comfy.samplers.SCHEDULER_NAMES[0])
            fields = {name: bundle.get(name) for name in self._from_settings()
                      if name not in ("steps", "scheduler")}
            fields["refine_amount"] = bundle.get("refine_amount")
        p = compute_schedule(model, scheduler, steps, fields)
        if not p["dual"]:
            _LOG.info("obvpm.h3: schedule %s: %d steps (%s)",
                      _given(fields.get("schedule"), "full"),
                      len(p["sigmas"]) - 1, _sigma_text(p["sigmas"]))
            return (p["sigmas"], p["sigmas"], int(width or 0),
                    int(height or 0), False)
        width, height = int(width or 0), int(height or 0)
        if width < 1 or height < 1:
            raise ValueError(
                "H3 Sampling Schedule: dual_stage needs the video's width "
                "and height to size the first stage; connect them.")
        first, second = p["first"], p["sigmas"]
        w1, h1 = stage_size(width, height, p["scale"])
        if p["second_renoises"]:
            _LOG.warning(
                "obvpm.h3: the second stage starts at sigma %.3f, which "
                "re-noises the first stage's result completely -- it only "
                "costs time. Use last_x_steps (or manual sigmas) for the "
                "second stage.", float(second[0]))
        _LOG.info(
            "obvpm.h3: two stages: %dx%d (scale %.3f, shape %.1f%% off "
            "the video's) for %d steps (%s), latent upscale to %dx%d, "
            "then %d steps (%s)",
            w1, h1, (w1 * h1 / float(width * height)) ** 0.5,
            100 * shape_error(width, height, w1, h1), len(first) - 1,
            _sigma_text(first), width, height, len(second) - 1,
            _sigma_text(second))
        return (second, first, w1, h1, True)

    @classmethod
    def _names(cls):
        it = cls.INPUT_TYPES()
        return set(it["required"]) | set(it["optional"])


class H3MCtxPinsFromPixels:
    CATEGORY = "obvpm/h3"
    FUNCTION = "convert"
    RETURN_TYPES = (wt.PINSPECS,)
    RETURN_NAMES = ("pin_specs",)
    DESCRIPTION = (
        "Re-routes every latent pin in a spec stack through the clip's "
        "frames: H3 MCtx Apply Pins then decodes the window from the clip "
        "file and encodes it at the size of the latent it pins into, "
        "squashed onto it whole as the latent upscale stretches it back. "
        "For the first stage of a two-stage run, which is smaller than the "
        "clip it continues -- a latent cannot be resized. Pixel-grade, so "
        "use it only there; the second stage pins the clip's own latents."
    )
    OUTPUT_TOOLTIPS = (
        "The same pins, each read from its clip's frames instead of its "
        "sidecar. Wire to the first stage's Apply Pins, with its VAEs "
        "connected.",
    )

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "optional": {
                "pin_specs": (wt.PINSPECS, {
                    "tooltip": "The pin stack (the Timeline's pin_specs). "
                               "Empty or unconnected passes through "
                               "empty."}),
            },
        }

    def convert(self, pin_specs=None):
        # fit "stretch": the first stage's size is never quite the video's
        # shape (the 32 grid), and the latent upscale maps it onto the
        # video corner to corner. A pin cropped to cover the first stage
        # would come back larger than the parent it continues -- the
        # background stretching at the seam. Squashed whole, the upscale
        # undoes it exactly.
        out = []
        for i, spec in enumerate(pin_specs or []):
            spec = dict(spec, fit="stretch")
            if spec.get("source_kind") == "clip":
                if not spec.get("source_path"):
                    raise ValueError(
                        "H3 MCtx Pins From Pixels: pin %d (%s) has no clip "
                        "file -- its clip arrived on a wire from this run, "
                        "so there are no frames to re-encode. Save the clip "
                        "first and pin it from the file."
                        % (i, spec.get("place", "?")))
                spec = dict({k: v for k, v in spec.items() if k != "source"},
                            source_kind="clip_pixels")
            out.append(spec)
        return (out,)


class H3StageLatent:
    CATEGORY = "obvpm/h3"
    FUNCTION = "join"
    RETURN_TYPES = ("LATENT",)
    RETURN_NAMES = ("latent",)
    DESCRIPTION = (
        "The second stage's latent: the latent-upscaled video of the first "
        "stage with the first stage's audio (sound has no size, so it "
        "goes on as it is), and no denoise mask -- the first stage's pins "
        "were at the small size, and the second stage's Apply Pins lays "
        "its own."
    )
    OUTPUT_TOOLTIPS = (
        "An H3 AV latent at the upscaled size. Wire to the second stage's "
        "Apply Pins latent (through the dual_stage switch).",
    )

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "first_stage": ("LATENT", {
                    "tooltip": "The first stage's result (the sampler's "
                               "denoised output): its audio is kept."}),
                "video_latent": ("LATENT", {
                    "tooltip": "The first stage's video, latent-upscaled."}),
            },
        }

    def join(self, first_stage, video_latent):
        small, audio = unpack_av(first_stage, "first_stage")
        video = video_latent["samples"]
        if getattr(video, "is_nested", False):
            video = video.unbind()[0]
        if video.ndim == 4:
            video = video.unsqueeze(0)
        if video.ndim != 5 or int(video.shape[2]) != int(small.shape[2]):
            raise ValueError(
                "H3 Second Stage Latent: video_latent is %s but the first "
                "stage has %d latent steps; wire the upscaled VIDEO of "
                "that same first stage."
                % (tuple(video.shape), int(small.shape[2])))
        return (pack_av(video.to(audio.device), audio, "latent"),)
