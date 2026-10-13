# comfyui-obvpm-timeline

A MiniMax H3 ComfyUI workflow and nodes that allow generating, extending, prepending, bridging and editing videos in an easy to use UI.

The timeline node is like a mini video editor.

And it also supports creating seamless looping videos.

<img src="assets/timeline-node.png" title="" alt="The Timeline node: three clips on the timeline, with the first one set to be prepended" width="804">

## Support this work

If these nodes and workflows save you time, consider supporting their development on Patreon. **Supporters get early access to new features and workflows.**

<a href="https://www.patreon.com/cw/obvpm"><img src="assets/patreon.svg" alt="Support obvpm on Patreon" width="300"></a>

## Updates

### Workflow Updates

#### v0.1.4-007 (Latest HEAD)

- New workflow [`h3_obvpm_timeline_r2v_v0.1.4-007.json`](workflows/h3_obvpm_timeline_r2v_v0.1.4-007.json). It runs on this pack's 0.1.4.
- **Needs [comfyui-obvpm](https://github.com/chanon/comfyui-obvpm) 0.2.14 or newer and comfyui-obvpm-timeline 0.1.4 or newer.** The Compatibility Check node says so when the workflow loads.
- The generation and upscale engines are switched on and off as whole groups: a **Mute Group If** switch in each engine group (Run when Generating, Run when Upscaling) mutes the engine that is not used for the run, decided from the timeline's `upscaling` before the run starts. Before, a gate inside each engine stopped it during the run.
- **H3 Model** (an Override Bundle Values node): turn on its `model` override to run a different model than the one in the engine settings preset, without editing the preset.
- Generation and upscale load their VAEs separately: generation defaults to the faster `minimax_h3_video_vae_int8_convrot.safetensors`, while the upscale keeps `minimax_h3_video_vae_fp16.safetensors` for the final quality.
- A **Megapixels Resolution Reference** note beside the timeline lists the width x height each megapixels setting gives at 16:9 and 4:3.
- The live preview while sampling comes from the new **H3 Live Preview** node (with `taeh3.safetensors` in `models/vae_approx`) instead of KJNodes' Model Preview Override: the whole clip, pinned frames included, plays under the Result Preview's bar while it samples.

#### v0.1.1-006 (2026-09-28)

- New workflow [`h3_obvpm_timeline_r2v_v0.1.1-006.json`](workflows/h3_obvpm_timeline_r2v_v0.1.1-006.json). It runs on this pack's 0.1.1, with the same requirements as 005.
- **New latent upscaler model:** the upscale pass now uses `minimax_h3_latent_upscaler_3d_conv_v1_fp16.safetensors` (the previous file is no longer published). Download it from [Hugging Face](https://huggingface.co/LBH-123-AI/Minimax_h3_latent_Upscaler/blob/main/minimax_h3_latent_upscaler_3d_conv_v1/minimax_h3_latent_upscaler_3d_conv_v1_fp16.safetensors) into `ComfyUI/models/latent_upscale_models/`.
- Fixed: an engine preset's `shift_video` did not change the noise schedule (the scheduler always used the model's built-in shift of 12, and the preset value only affected the audio). The shift is now applied once, in H3 Model Optimization, so it shapes the schedule and the sparse attention window too. The included presets all use 12, so their results are unchanged.

Full history in [workflows/README.md](workflows/README.md)

### comfyui-obvpm-timeline Custom Node Pack Updates

#### 0.3.1 (2026-10-05)

- Fixed: a 0.3 workflow opened before updating from 0.2 (or before restarting) failed every Run with "Value 1 smaller than min of 2: level_lock_frames": the Timeline read its settings as a 0.2 workflow's, one slot over. It now keeps them. A copy saved while it showed the error keeps the shifted settings: open the workflow again from its file.

#### 0.3.0 (2026-10-05)

- **Changed (0.3.0): H3 Sampling Schedule's outputs are reordered** (first stage's together, `dual_stage` last); saved workflows keep their wires.
- **Changed (0.3.0): the Timeline has no output pins**: everything it hands a Run is one bundle set as the constant `h3_timeline_outputs` -- take its fields out with an Unbundle that gets it. Its settings moved into a ⚙ dialog; the node shows `set_constant`, `base_folder`, `crf` and `duration_seconds`. 0.2 workflows open and run as before (an Unbundle beside the Timeline takes over the old wires). Needs comfyui-obvpm 0.2.14.
- **Changed (0.3.0): the Result Preview and Upscale Result Preview have no `path` input**; they read the save by the Set node their `result_constant` names.
- New: the Timeline plays under our own player bar instead of the browser's controls; its seek bar shows the whole clip with the part the cut uses marked.
- New, for other packs: takes of their own kind in a seed hunt's folder show in the Result Preview, with their own buttons.
- Fixed: in a seed hunt, the next take's place no longer shows the previous take's live frames before its own first step.
- Fixed: in fullscreen, the Result Preview and the seam browser keep their top row, so the single view can go back to the grid; dialogs opened there show.
- Fixed: an 8.3 ms skip in the sound at some extend joins (clips whose length is not a multiple of 3 frames, like 124 or 362): takes' files, previews and exports now play the sound on its frames.
- Fixed: a few ms of near-silence just before crossfaded extend joins in previews and exports.
- Fixed: a rare 25 ms skip in the sound at a junction in the upscale (a take extended from an off-grid cut of an off-grid take).
- Fixed: a false "unexpected audio grid" warning when continuing clips of some lengths (e.g. 362 frames); the clips and takes were fine.
- Changed: the Result Preview's live picture is always on; its right-click switch is gone (an old workflow could turn it off unnoticed).
- Fixed: the hunt button shows a loaded workflow's hunt state.
- Fixed: no more blue selection over videos; status lines and the Timeline's next run line can be selected to copy.
- New: a very short take can be continued: its window reaches back into the frames it held from the clip it continues (a 33-frame extend was "too short to extend"), and a prepend's on into the frames a prepend-made take led into -- in both stages of a two-stage run.
- New: a prepend close to a clip's end takes its window from the take after it on the timeline when that take extends the clip (it holds the same frames, then its own); otherwise it says how many frames are left.

#### 0.2.1 (2026-10-04)

- New: seed hunting. One Run makes several takes from different seeds and the Result Preview shows them side by side as they arrive, live picture included; keep the best, discard the rest. A **hunt** toggle and count in the Timeline's header, and the new H3 Seed Hunt node.
- New: **browse takes** in the seam menu: every take that fits a seam side by side, the seed hunts' waiting takes included, each playing joined to its neighbour; **use** puts one in the cut.
- New: **H3 Live Preview**: the sampler's picture on the take's own timeline, pinned ends included, in step with the finished takes in a hunt's grid.
- New: our own player bar below the picture in the Result Preview and the seam browser; a hunt's takes play, pause and seek together, and the live preview keeps its place between sampling steps.
- Two-stage extends no longer stretch the picture at the join (960x544 at scale 0.5 came out 6% taller): the first stage keeps the video's shape (512x288 there) and its pins are squashed onto it, not cropped.
- New: the Result Preview (and the seam browser) laid out anew: grid or single view, each take *with seams*, *with neighbours* or *result only*, hover a take to add, keep or delete it, a red SAMPLING step x/y on the take being made (stage 1 / stage 2 first in a two-stage run) from the moment a run starts, and a list of earlier generations to look at again. A single generation waits among the candidates too, until it is kept or added.
- New: `result_constant` on the Result Previews -- they read their path from a KJ Set node by name, no wire needed (comfyui-obvpm 0.2.12 or newer, so the engine settings feeding them do not fade).
- New node **H3 Upscale Result Preview**: plays the finished upscale under the same player bar, with delete and dismiss.
- A seed hunt's waiting takes are named `take_01_seed_1234.mp4`, ...; kept, they become the next clip as before.
- Result Preview, fixed: the live frames from KJNodes' Model Preview Override are shown only on the preview of the branch that is sampling. A preview fed from an upscale save showed the generation's frames.
- Joined previews reuse the part of the parent they share, so after a generation's first take each one builds in about 0.2 s instead of about 3 s.
- Switching takes in single view is instant and keeps its place; paused takes sit on exactly the same frame.

Full change history in [CHANGELOG.md](CHANGELOG.md)

## Watch the Tutorial

The best way to learn how to use the Timeline and workflow is by watching the YouTube tutorial video:

[![Watch the tutorial on YouTube](https://img.youtube.com/vi/kqP09NfJXaQ/hqdefault.jpg)](https://youtu.be/kqP09NfJXaQ)

**Watch on YouTube: [https://youtu.be/kqP09NfJXaQ](https://youtu.be/kqP09NfJXaQ)**

## Features

The main node is the **Timeline** node: the clips you generate are placed on it, and it is where you arrange, cut and preview them, and pick which clip the next generation continues from.

Generate a clip, see if you like it, add it to the timeline, then extend from it. Any part you don't like can be redone later.

Every generated clip is saved together with a motion context file (`.mctx`) that holds its latents. Extensions continue from those original latents using latent masks, not from re-encoded pixels, so there are no lighting changes or flickers at the joins. And because the files sit next to the clips, a clip can still be extended at full quality days or months later.

**Generating**

- **Extend** a clip seamlessly.
- **Prepend**: generate what happens *before* a clip
- **Bridge**: generate what happens between the end of one clip and the beginning of another. This lets you redo any section of the video, and bridging onto a fresh generation brings the quality back if it has drifted.
- **Loop**: bridge the last clip back to the first clip to make a seamless looping video.
- **Extend from a cut**: if a clip ends badly, cut off the bad part and extend from the good part. Snap cuts keeps cuts on the latent frame grid.
- Clips that have no motion context (external clips, clips from other workflows) can be extended too, with seam improvements applied automatically.
- **Result preview**: plays each new clip joined to its neighbours and rates how seamless the join is. From there you add it to the timeline, delete it or dismiss it.
- **Live preview**: the H3 Live Preview node shows the sampler's picture in the result preview while it samples, the whole clip on the take's timeline under the preview's own player bar. Lets you quickly see if a generation is going wrong.

**Timeline**

- **Mini Video Editor**: Drag in clips from anywhere, reorder them by dragging, trim the ends, cut left / cut right at the playhead, undo cuts, and open gaps.
- **Quick preview**: plays through the clips right away. **Full preview** assembles them into a single video file, losslessly where possible. **Export** saves the finished video.
- **Load Settings, Prompts from Clips**: restores the prompt, seed, settings and references that a clip was generated with, so you don't have to keep track of them yourself.
- **Swap takes**: Swap between previous takes generated for the same extension, so you can go back to them and swap between them on the timeline.
- The sequence is also available as text, for copying a timeline into another workflow.

**Upscaling**

- A latent upscale and refine of the **whole sequence in one pass**, so details stay consistent across the joins and the result is still seamless.
- Sampling is done in windows, so long or high resolution videos still fit in VRAM.
- Generate at low resolution for fast iteration, then upscale once at the end. This is optional, you can also generate the first pass at final quality.
- Each clip's conditioning is saved with it, so the upscale uses the same references the clip was generated with.

**Workflow**

- Organized for fast and easy use. All inputs are in one area. No pan all over the workflow to change things.
- **Settings Presets**: Allows you to save frequently used settings such as steps, turbo, and sampling settings and control them in one place
- Up to four image references, plus video and audio references. (More can be added)

## Dependencies

**ComfyUI 0.35.0 (2026-09-09) or newer is needed:** the workflow's Model Optimization uses core's `Model Sparse Attention` node, which arrived there.

The workflows use these custom node packs, so install all of them:

| Custom node pack                                                                                       | Used for                                                                                  |
| ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------- |
| [comfyui-obvpm-timeline](https://github.com/chanon/comfyui-obvpm-timeline) (this pack)                 | The Timeline node, pins, joint render, upscale pass, result preview                       |
| [comfyui-obvpm](https://github.com/chanon/comfyui-obvpm) (0.2.14 or newer)                              | Bundles, Settings Presets, switches and gates, Load Images & Compose, Compatibility Check |
| [ComfyUI-KJNodes](https://github.com/kijai/ComfyUI-KJNodes)                                            | Set / Get nodes, Sage attention patch                                                     |
| [Comfyui_Minimax_h3_latent_Upscaler](https://github.com/LBH-123-AI/Comfyui_Minimax_h3_latent_Upscaler) | The latent upscaler used by the upscale pass                                              |
| [ComfyUI-MiniMax-H3-Turbo](https://github.com/Larryvrh/ComfyUI-MiniMax-H3-Turbo)                       | Turbo LoRA loader for larryvrh turbo                                                      |
| [ComfyUI-Spectrum-MiniMax-H3](https://github.com/xmarre/ComfyUI-Spectrum-MiniMax-H3)                   | Spectrum acceleration                                                                     |
| [rgthree-comfy](https://github.com/rgthree/rgthree-comfy)                                              | Power Lora Loader                                                                         |

### IMPORTANT Compatibility Warnings

**Latent upscaler: use the original pack, not the "Plus" fork.** The workflow was built with [LBH-123-AI/Comfyui_Minimax_h3_latent_Upscaler](https://github.com/LBH-123-AI/Comfyui_Minimax_h3_latent_Upscaler). The fork [xmarre/Comfyui_Minimax_h3_latent_Upscaler-Plus](https://github.com/xmarre/Comfyui_Minimax_h3_latent_Upscaler-Plus) registers a node with the **same id and name** but a different set of widgets. Only one of the two can be installed at a time, and with the fork installed the workflow loads wrong:

- **Symptom:** on the *H3 Latent Upscaler 3D* node, `device` shows `true` and `precision` shows `cuda`, and the run fails until both are set by hand.
- **Cause:** the fork removed the `enable_temporal_chunking` and `force_unload` widgets, so every saved value after `align` lands one field too far along.
- **Why not just fix the two fields:** the fork also removed **temporal chunking**, and the upscale pass relies on it. Without it the upscaler normalises over the whole sequence at once, which on longer timelines produces the drifting, hallucinated detail this workflow was tuned to avoid.

If you see the symptom, uninstall the Plus fork, install the original pack, restart ComfyUI and reload the workflow.

**"MiniMax H3 Video Extend (Backported)" causes colour shifts at the joins.** The pack [kat3ri/ComfyUI-MiniMax-H3-Extend](https://github.com/kat3ri/ComfyUI-MiniMax-H3-Extend) (nodes *MiniMax H3 Video Extend (Backported)* and *MiniMax H3 Encode AV (Patched)*) does not just add nodes: at import time it **replaces** two core ComfyUI functions, `MiniMaxH3.extra_conds` and `PackedLayout.__init__`, with copies taken from an older ComfyUI. Those copies affect every H3 sampling run in the session, even in workflows that never use its nodes.

- **Symptom:** an extension's colours and brightness drift away from the clip it continues, or the join has a visible colour/brightness step, even though the timeline's own extensions are normally seamless.
- **Cause:** this pack extends through latent masks. Current ComfyUI passes those masks into the model as per-token denoise masks, so the preserved context frames are run at the clean-conditioning timestep. The replaced `extra_conds` predates that mechanism and silently drops the masks, so the model treats the preserved frames as if they were fully noised and re-renders the continuation against context it cannot see properly. The replaced `PackedLayout` also rejects interior keyframe anchors, which the pin nodes need.
- **Detection:** the mctx pin nodes stop with an error naming the foreign patch. Plain extends do not: they run and simply look wrong.

If you have this pack installed, remove it, restart ComfyUI and re-run the extension. The related [pmhaidn/ComfyUI-Minimax-H3-Extender](https://github.com/pmhaidn/ComfyUI-Minimax-H3-Extender) *wraps* the core function instead of replacing it and leaves the current layout code alone, so it has not shown this problem; it does patch the Turbo LoRA loader, so if you see odd Turbo behaviour with it installed, try without it.

## Installation

Clone (or copy) this folder into `ComfyUI/custom_nodes`:

```
cd ComfyUI/custom_nodes
git clone https://github.com/chanon/comfyui-obvpm-timeline
```

Restart ComfyUI. No extra Python dependencies are required. 

## Workflow

The workflow is available in the [workflows](https://github.com/chanon/comfyui-obvpm-timeline/tree/main/workflows) folder. Use the latest, `h3_obvpm_timeline_r2v_v0.1.4-007.json` (it needs comfyui-obvpm 0.2.14 and this pack's 0.1.4, see [the workflow changelog](workflows/README.md)); the older `-006` and `-004` are kept for setups that cannot update yet.

## Other Notes

Every node in this pack is listed with **(obvpm)** after its name, so
searching the node menu for `obvpm` finds all of them. The names used
throughout this documentation leave that suffix off.

**AI Generated docs:**

**[docs/h3.md](docs/h3.md)** 
**[docs/h3-nodes.md](docs/h3-nodes.md)**

## License

[GPL-3.0](LICENSE). See
[THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md) for acknowledgments.
