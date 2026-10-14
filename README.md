# vastai-setup

Vast.ai provisioning for ComfyUI. One script, many **stacks** (a stack = one model family:
its custom nodes, models, and workflows).

## Layout

```
provision.sh            the only file Vast fetches: clones this repo, loads lib/, runs the steps
lib/                    the engine, one concern per file
  config.sh             paths, env defaults, empty install lists
  base.sh               what every stack gets: apt, pip, custom nodes
  dsl.sh                helpers for writing stacks: hf, civitai, node, model, gpu_* checks
  progress.sh           log, step counter, status file, final summary
  checks.sh             disk and token checks
  setup.sh              apt, pip, ComfyUI update, custom nodes
  download.sh           size plan, Hugging Face / wget / Civitai downloads
  stacks.sh             stack selection, loading, links, workflow install
  quiet.sh              QUIET_LOG (pause Vast services while provisioning)
stacks/<name>/
  stack.sh              what this stack needs (node, hf, civitai, ... lines)
  *.json                its workflows (edited: paths fixed to what the stack downloads)
  <folder>/             (optional) a bundled custom node, copied to ComfyUI/custom_nodes/<folder> in the last step (replaces a cloned copy of the same name; its requirements.txt is installed)
  originals/*.json      (optional) the author's files as shipped, installed to workflows/<name>/originals/
families/<family>/
  family.sh             shared by every stack named <family>-*: LoRAs, and for qwen21 the VAE, diffusion model, encoder, name rewrites
```

Nodes used by every stack (rgthree, KJNodes, GGUF, RES4LYF, AusBoss, ...) are in `lib/base.sh`; stacks list only their own.

Repo holds only `.sh` and workflow `.json`. Models stay on Hugging Face / Civitai.

### Writing a stack.sh

```bash
node ausboss/ComfyUI-AusBoss                                    # custom node: github owner/repo

# Downloads read: models subfolder, then source, then an optional saved name.
hf vae Comfy-Org/MiniMax-H3 vae/minimax_h3_audio_vae_fp32.safetensors               # hf <subfolder> <repo[@commit]> <path-in-repo> [name]
hf vae Kijai/MiniMax-H3-experimental minimax_h3_video_vae_int8_convrot.safetensors   # file at the repo root
hf loras ausboss/Qwen-Image-2.1-Outpaint-LoRA qwen-image-2.1-outpaint-v2.safetensors qwen21_outpaint-v2.safetensors   # + saved name
hf loras Kijai/MiniMax-H3_comfy@098f8c4 loras/x.safetensors                          # repo@commit pins a revision
github vae_approx madebyollin/taehv@62f7591 safetensors/taeh3.safetensors           # file in a GitHub repo, same shape as hf
model upscale_models https://example.com/x.pth my-name.pth                           # any other direct URL
civitai loras https://civitai.red/api/download/models/3357315?fileId=3244894 my-name.safetensors   # URL pasted from Civitai (.red or .com)

pip_llama_cpp                                                   # vision-capable llama-cpp wheel
```

Each helper only appends to a list, so stacks can't wipe each other's entries. Plain `PIP_PACKAGES+=(...)`, `LINKS+=(...)` and `WF_SUBST+=(...)` still work.

## Stacks

| Stack | What | Approx. download (qwen21: on top of the shared core, see below) |
|---|---|---|
| `qwen21-edit-main` | Qwen Image 2.1 edit (work in progress): edit + prompt-enhancer, outpaint and rotate workflows, shipped as the author made them | ~0 GB (not yet complete, see below) |
| `h3-obvpm-timeline` | MiniMax H3 timeline: generate / extend / bridge / upscale (needs ComfyUI 0.35.0+) | ~50 GB (diffusion model, VAEs, text encoder, Turbo and other H3 LoRAs, upscaler) |

**qwen21 shared core** (downloaded once for any `qwen21-*` stack): VAE, diffusion model, heretic NVFP4 text encoder and all qwen21 LoRAs. About 13 GB (NVFP4 diffusion model 4.2 GB, NVFP4 encoder 6.3 GB).

**LoRA families.** Select any `qwen21-*` stack and you get **all** qwen21 LoRAs (~2.3 GB from Hugging Face
+ the Civitai ones); any `h3-*` stack gets all MiniMax H3 LoRAs. They live in `families/<family>/family.sh`;
the family is the stack name before the first `-`. To add a LoRA to a family, append it there.

Shared files download once, so `all` is less than the sum: the H3 models and LoRAs (any `h3-*` stack) and the
Qwen Image 2.1 model, heretic text encoder, VAE and LoRAs (any `qwen21-*` stack) come from the family files.

## Use

In the Vast.ai template set `PROVISIONING_SCRIPT` to:

```
https://raw.githubusercontent.com/paroonk/vastai-setup/main/provision.sh
```

Template env vars:

| Var | Default | Purpose |
|---|---|---|
| `STACKS` | `all` | `h3-obvpm-timeline`, `h3-obvpm-timeline,qwen21-edit-main`, a family name (`qwen21` = every `qwen21-*` stack, `h3` likewise), or `all` (case-insensitive). Selects nodes, models and workflows together. |
| `CIVITAI_TOKEN` | — | Civitai API key. Required for Civitai downloads. |
| `HF_TOKEN` | — | Only for gated Hugging Face repos. |
| `QUIET_LOG` | `true` | Pauses Vast's `comfyui`/`api-wrapper` services during provisioning (they print "startup paused…" every 5 s) and restarts them at the end. `false` leaves them. If ComfyUI is ever down after a run: `supervisorctl start comfyui api-wrapper`. |
| `AUTO_UPDATE` | `true` | `git pull` custom nodes already on disk (e.g. a restarted instance). `false` keeps them. Fresh clones are always latest. |
| `SETUP_REF` | `main` | Branch/tag to take stacks from — test changes on a branch first |

⚠️ `STACKS` defaults to `all`: once there are several stacks, an instance without `STACKS`
downloads every stack's models. Set it explicitly in each template.

## Private folders (not in the repo)

Some things must not be published: `comfyui-obvpm-pro-extensions` (supporters-only licence) and your own `refmods`. List them in a
stack with `private <comfy-subpath> <folder>`, e.g. `private custom_nodes comfyui-obvpm-pro-extensions` and `private models refmods`.
They are never downloaded. Upload the folders to `/workspace/vastai-setup-private/` on the instance (set `PRIVATE_DIR` to use another
folder); the last provisioning step copies each one to `ComfyUI/<comfy-subpath>/<folder>`, replacing a node that is already there (a model folder such as `refmods` is merged, so files you made on the instance stay), and installs a
node's `requirements.txt`. A folder that is missing is skipped with a log line.

A fresh instance has nothing uploaded at first boot, so upload and re-run provisioning once; finished downloads are skipped. If you keep the
instance or a Vast volume, you only do this once.

## Watching progress

The provisioning log shows `[n/9]` steps with timings, `[node k/N]`, and
`[models k/N] file (size) — done/total GB` for every download (sizes are looked up first).
Vast's log viewer mixes in its own "startup paused" lines; for a clean one-line view run:

```bash
watch -n5 cat /workspace/provision-status.txt
```

It ends with `FINISHED ... all items OK` or `FINISHED ... with N failure(s)`.

## Add a workflow

Commit the `.json` into `stacks/<name>/`. Next instance installs it under ComfyUI workflows
`<name>/`. Same-named files there are overwritten. Put the untouched author's copy in
`stacks/<name>/originals/` to keep it for comparison.

## Add a stack

1. Create `stacks/<name>/stack.sh` — copy `stacks/qwen21-edit-main/stack.sh` and change the lines.
2. Add its workflow JSONs to the same folder.

No change to `provision.sh` or `lib/`. Models/nodes shared between stacks download once.

## Third-party workflows

Saved here so instances don't depend on Civitai/GitHub availability. Model paths are edited to match
the files each stack downloads (no subfolders, stack's own model variants). They are snapshots:
when the author releases a new version, re-download and re-apply the path fixes.

| File | Source | Changes |
|---|---|---|
| `stacks/h3-obvpm-timeline/h3_obvpm_timeline_r2v_v0.3.0-010-pro-refmod.json` | [chanon/comfyui-obvpm-timeline](https://github.com/chanon/comfyui-obvpm-timeline) (GPL-3.0) | Author files, with the LoRA names edited to the `h3_<name>` files the h3 family saves (the original `h3\<name>` sub-folder prefix is removed). Their nodes are the bundled folders `comfyui-obvpm`, `comfyui-obvpm-timeline`, `comfyui-obvpm-pro-extensions` in the same stack, copied to `custom_nodes/` in the last step; the -refmod ones also need ComfyUI-MiniMaxH3Mod (installed). Not downloaded: the `minimax_h3_hybrid_fl2va_ref2va_b30-49` model that the v0.3 engine-settings preset names (community file, pick your own hybrid or leave the loaded ref2va model), and RefMod files for `models/refmods` |
| `stacks/qwen21-edit-main/*.json` (`qwen21_edit`, `qwenImage21Outpaint_v12`, `qwenImage21Rotate_v11`) | Qwen Image 2.1 edit / outpaint / rotate workflows | Their saved `qwen-image-2.1-UC-int8_convrot` and `qwen3vl_8b_int8_convrot_heretic` names are rewritten to the NVFP4 files at install. LoRA loaders already use the `qwen21_` saved names from the family file. AusBoss nodes come from the base list. The edit workflow's `sam3.1_multiplex_fp16` checkpoint (1.7 GB, bypassed by default) is downloaded by the stack. |

Stacks can add `LINKS+=("link|target")` (paths under `models/`) to expose one downloaded file at a
second path a node expects, or `WF_SUBST+=("from|to")` to rewrite a text (e.g. a model filename) in the installed workflows.

Civitai entries may give a 3rd field, `"target|url|filename"`, to save under a readable name.

### qwen21: diffusion model and text encoder

The `qwen21-*` workflows in the repo use two neutral names, `qwen_image_2.1` (UNET loader) and `qwen3vl_8b_heretic` (CLIP loader).
No symlinks: when `provision.sh` installs the workflows it rewrites those names (`WF_SUBST`, set in `families/qwen21/family.sh`) to the
file that was actually downloaded, so each installed workflow names its real file:

| Neutral name | Becomes |
|---|---|
| Diffusion model `qwen_image_2.1` | [abenzerps uncensored NVFP4](https://huggingface.co/abenzerps/Qwen-Image-2.1-Uncensored-Quantized) `qwen-image-2.1-UC-NVFP4`, 4.2 GB (UC = uncensored quant; licence tag: other) |
| Text encoder `qwen3vl_8b_heretic` | [pottokao heretic NVFP4](https://huggingface.co/pottokao/Qwen-Image-2.1-Text-Encoder-Heretic-NVFP4) `qwen3vl_8b_nvfp4_heretic`, 6.3 GB (uncensored Qwen3-VL-8B) |

NVFP4 only: there is no bf16 option. NVFP4 has native kernels on Blackwell GPUs; on other GPUs it is untested. The standard (non-heretic)
encoder is not downloaded. Untested: LoRAs on the NVFP4 diffusion model.

### qwen21 LoRAs (all in `families/qwen21/family.sh`)

Each LoRA has a one-line hint above it; full settings, trigger words and prompts are in `docs/lora-notes.md`. Saved names start with `qwen21_`.
Groups: speed/consistency (8-step and Viggle turbo, consistency, outpaint), realism/editing (nice-asians, outfit swap, realism edit, restore, VNCCS pose studio),
BFS head/body swap, sliders (skin tone, breasts) and NSFW (nsfw-lora, vagina, nude edit v3, femaledvaginus). Civitai ones need `CIVITAI_TOKEN`; use `civitai.red` URLs for NSFW files.

Some LoRAs are saved under a `qwen21_` name (e.g. `qwen21_consistency`, `qwen21_outpaint-v2`); the `qwen21-edit-main` workflows already load them by those names.
Civitai showed some LoRAs as paid/early access when added; the download may need access on your account.

The MiniMax H3 text encoder is NVFP4 only (native kernels on Blackwell GPUs; untested on others), so the workflows' `qwen3vl_32b_minimax_h3_nvfp4_awq` loads as saved.

## Rules

- Public repo: **never commit tokens**. Check workflow JSONs for API keys in node settings.
- Every push to `main` goes live on the next instance you start.
