# vastai-setup

Vast.ai provisioning for ComfyUI. One script, many **stacks** (a stack = one model family:
its custom nodes, models, and workflows).

## Layout

```
provision.sh            the only file Vast fetches — download engine
stacks/<name>/
  stack.sh              what this stack needs: NODES+=, MODELS+=, CIVITAI+=, PIP_PACKAGES+=
  *.json                its workflows (edited: paths fixed to what the stack downloads)
  originals/*.json      (optional) the author's files as shipped, installed to workflows/<name>/originals/
families/<family>/
  loras.sh              LoRAs for every stack named <family>-*  (qwen21, mmh3)
```

Nodes used by every stack (rgthree, KJNodes, GGUF) are in `provision.sh`; stacks list only their own.

Repo holds only `.sh` and workflow `.json`. Models stay on Hugging Face / Civitai.

## Stacks

| Stack | What | Approx. download (qwen21: on top of the shared core, see below) |
|---|---|---|
| `mmh3-dasiwa` | MiniMax H3 video + DaSiWa workflows | ~75 GB |
| `qwen21-multi-image` | Qwen Image 2.1 multi-image editing, up to 10 references, reference-aware prompt enhancer | ~10 GB (prompt enhancer) |
| `qwen21-integrated` | Qwen Image 2.1 integrated image editing (SageAttention / EasyCache speed-ups, prompt enhancer bypassed) | ~10 GB (prompt enhancer) |
| `qwen21-outpaint` | Qwen Image 2.1 outpaint on any side, auto prompt (Qwen3-VL), AusBoss nodes, outpaint LoRA v2/v1 | ~0 GB |
| `qwen21-lonecats-fast` | Lonecats Qwen 2.1 fast workflow: turbo LoRA option, Clown/Detail-Daemon sampling, VOSR2 4x upscaler, post-processing (LUT, phone filters), Qwen3-VL caption | ~3 GB (+~7 GB VOSR2 on first run) |
| `qwen21-edit-8step` | Qwen 2.1 edit, 8-step turbo LoRA + prompt enhancer | ~0 GB |
| `qwen21-dual-cfg` | Qwen-Image-2.1 dual-CFG edit (two sampling stages, hand/foot repair) | ~0 GB |
| `qwen21-t2i-edit` | StefanFalkok's T2I + Edit workflows (SageAttention), prompt enhancers, SeedVR2 upscale | ~26 GB (SeedVR2 models) |
| `mmh3-obvpm-timeline` | MiniMax H3 timeline: generate / extend / bridge / upscale (needs ComfyUI 0.35.0+) | ~50 GB (+7.3 GB if mmh3-dasiwa also selected) |

**qwen21 shared core** (downloaded once for any `qwen21-*` stack): VAE, diffusion model, heretic NVFP4 text encoder and all qwen21 LoRAs. About 13 GB on Blackwell (NVFP4 diffusion model 3.9 GB) or about 24 GB on other GPUs (bf16 diffusion model 14.2 GB).

**LoRA families.** Select any `qwen21-*` stack and you get **all** qwen21 LoRAs (~2.3 GB from Hugging Face
+ the Civitai ones); any `mmh3-*` stack gets all MiniMax H3 LoRAs. They live in `families/<family>/loras.sh`;
the family is the stack name before the first `-`. To add a LoRA to a family, append it there.

Shared files download once, so `all` is less than the sum: MiniMax H3 model, VAEs, text encoder,
upscaler (mmh3-dasiwa, mmh3-obvpm-timeline); Qwen Image 2.1 model, heretic text encoder, VAE (qwen21-multi-image, qwen21-integrated, qwen21-outpaint, qwen21-lonecats-fast, qwen21-edit-8step, qwen21-dual-cfg, qwen21-t2i-edit); llama-cpp (mmh3-dasiwa, qwen21-lonecats-fast).

## Use

In the Vast.ai template set `PROVISIONING_SCRIPT` to:

```
https://raw.githubusercontent.com/paroonk/vastai-setup/main/provision.sh
```

Template env vars:

| Var | Default | Purpose |
|---|---|---|
| `STACKS` | `all` | `mmh3-dasiwa`, `mmh3-dasiwa,qwen21-outpaint`, a family name (`qwen21` = every `qwen21-*` stack, `mmh3` likewise), or `all` (case-insensitive). Selects nodes, models and workflows together. |
| `CIVITAI_TOKEN` | — | Civitai API key. Required for Civitai downloads. |
| `HF_TOKEN` | — | Only for gated Hugging Face repos. |
| `TEXT_ENCODER` | `auto` | MiniMax H3 stacks only: `auto` = nvfp4 on Blackwell, int8 elsewhere; or force `nvfp4` / `int8` |
| `QWEN21_DIFFUSION` | `auto` | qwen21 stacks: `auto` = NVFP4 on Blackwell, bf16 elsewhere; or force `nvfp4` / `bf16` |
| `QWEN21_ENCODER` | `nvfp4` | qwen21 stacks: heretic `nvfp4` (6.3 GB) or `bf16` (17.5 GB) |
| `QUIET_LOG` | `true` | Pauses Vast's `comfyui`/`api-wrapper` services during provisioning (they print "startup paused…" every 5 s) and restarts them at the end. `false` leaves them. If ComfyUI is ever down after a run: `supervisorctl start comfyui api-wrapper`. |
| `AUTO_UPDATE` | `true` | `git pull` custom nodes already on disk (e.g. a restarted instance). `false` keeps them. Fresh clones are always latest. |
| `SETUP_REF` | `main` | Branch/tag to take stacks from — test changes on a branch first |

⚠️ `STACKS` defaults to `all`: once there are several stacks, an instance without `STACKS`
downloads every stack's models. Set it explicitly in each template.

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

1. Create `stacks/<name>/stack.sh` — copy `stacks/mmh3-dasiwa/stack.sh`, replace the lists.
   Only append (`+=`); never reassign a list, or you wipe other stacks' entries.
2. Add its workflow JSONs to the same folder.

No change to `provision.sh`. Models/nodes shared between stacks download once.

## Third-party workflows

Saved here so instances don't depend on Civitai/GitHub availability. Model paths are edited to match
the files each stack downloads (no subfolders, stack's own model variants). They are snapshots:
when the author releases a new version, re-download and re-apply the path fixes.

| File | Source | Changes |
|---|---|---|
| `stacks/mmh3-dasiwa/mmh3-dasiwa_t2va_v2.5.json` | DaSiWa C-MMH3 v2.5 (Civitai 3195699) | `MiniMaxH3/` prefixes removed; checkpoint -> Civitai filename; latent upscaler -> conv_v1_bf16; default upscale model `2x-AnimeSharpV4_RCAN` (not downloaded, stage OFF) -> `4x-UltraSharp` |
| `stacks/qwen21-multi-image/qwen21-multi-image_edit.json` | "Qwen Image 2.1 Multi-image Editing" (Civitai 2958067, v1.0) | diffusion model -> bf16, text encoder -> heretic NVFP4 (author int8); prompt-enhancer encoder (Qwen3.5-9B PE, int8 only) kept |
| `stacks/qwen21-integrated/qwen21-integrated_edit.json` | "Qwen image 2.1 Integrated Image Editing to Accelerate Workflows" (Civitai 2965021, v1.0) | diffusion model -> bf16, text encoder -> heretic NVFP4 (author int8) |
| `stacks/qwen21-outpaint/qwen21-outpaint_auto-prompt.json` | "Qwen Image 2.1 Outpaint: auto prompt, any side, optional LoRA" (Civitai 2964810, v1.1) | diffusion model -> bf16, text encoder -> heretic NVFP4 (author int8). Needs ComfyUI-AusBoss nodes (installed by the stack) |
| `stacks/qwen21-lonecats-fast/qwen21-lonecats-fast_upscale-postprocess.json` | "Lonecats Qwen 2.1 Fast Workflow w/ upscalers and post processing" (Civitai 2960068, v1.0 Beta) | `Qwen\\` model subfolder prefixes removed. Not downloaded: bypassed GGUF diffusion model. VOSR2 model auto-downloads on first run (~7 GB) |
| `stacks/qwen21-edit-8step/qwen21-edit-8step_prompt-enhancer.json` | "qwen 2.1 EDIT WORKFLOW 8 steps with prompt enchancer" (Civitai 2969533, v1.0) | diffusion model -> bf16 (author int8); LoRA name = downloaded file. The author's `qwen3vl_8b_nvfp4_heretic` encoder is kept (see below) |
| `stacks/qwen21-dual-cfg/qwen21-dual-cfg_edit.json` | "Qwen-Image-2.1 Dual CFG Image Edit" (Civitai 2965509, v1.0) | models -> bf16 |
| `stacks/qwen21-t2i-edit/*.json` (text-to-image, image-edit, each also with prompt-enhancer; seedvr2-upscale) | "Qwen Image 2.1 Workflows (T2I + Edit) with SageAttention" by StefanFalkok (Civitai 2951890, v1.1) | `qwenimage21\` path removed, UNET -> bf16; enhancer workflows: Gemma 4 12B -> `qwen3vl_8b_bf16`, CLIP type -> `qwen_image`; files renamed |
| `stacks/mmh3-obvpm-timeline/mmh3-obvpm-timeline_r2v_v0.1.1.json` | [chanon/comfyui-obvpm-timeline](https://github.com/chanon/comfyui-obvpm-timeline) (GPL-3.0) | `h3\` LoRA prefixes removed (nodes + presets); latent upscaler conv_v1_fp16 -> conv_v1_bf16 |

Stacks can add `LINKS+=("link|target")` (paths under `models/`) to expose one downloaded file at a
second path a node expects, instead of downloading it twice.

Civitai entries may give a 3rd field, `"target|url|filename"`, to save under a readable name.

### qwen21: diffusion model and text encoder

All `qwen21-*` workflows load `qwen_image_2.1_nvfp4` (UNET loader) and `qwen3vl_8b_nvfp4_heretic` (CLIP loader). Both come from
`families/qwen21/loras.sh`, downloaded once:

| | Blackwell (`auto`) | Other GPUs (`auto`) | Env override |
|---|---|---|---|
| Diffusion model | [pottokao NVFP4 DiT](https://huggingface.co/pottokao/Qwen-Image-2.1-DiT-NVFP4-ComfyUI), 3.9 GB (community quant of the official model, non-commercial licence, T1 tier) | official bf16, 14.2 GB, the NVFP4 filename links to it | `QWEN21_DIFFUSION=auto\|nvfp4\|bf16` |
| Text encoder | [pottokao heretic NVFP4](https://huggingface.co/pottokao/Qwen-Image-2.1-Text-Encoder-Heretic-NVFP4), 6.3 GB (uncensored Qwen3-VL-8B) | same file (untested on non-Blackwell) | `QWEN21_ENCODER=nvfp4\|bf16` (`bf16` = heretic bf16, 17.5 GB, filename linked) |

The NVFP4 diffusion model is a plain quantization of the official model; only the text encoder is heretic (uncensored). The
standard (non-heretic) encoder is not downloaded. `TEXT_ENCODER` does **not** affect qwen21 stacks. The Qwen3.5-9B prompt
enhancers (`multi-image`, `integrated`) are a different model and stay standard. Untested: LoRAs on the NVFP4 diffusion model.

### Other qwen21 LoRAs (all in `families/qwen21/loras.sh`)

| File | Source | Use |
|---|---|---|
| `qwen-image-2.1-outpaint-v2` / `-outpaint` | ausboss (HF) | Rotate / crop / outpaint edits. v2 recommended, v1 for big zoom-outs. Workflow: `qwen21-outpaint` stack |
| `qwen-image-2.1-consistency` / `-2000` | ausboss (HF), Civitai 2969143 | Edits stay on the original's frame. No trigger word; strength 1.0 right after the model loader; 25 steps, CFG 1. 2000 = tighter but paler paintings |
| `qwen21_skin-tone-slider_v1` | Civitai 766017 | Slider, no trigger word. T2I: -0.8..-0.4 fair, +0.3..+0.6 tan, +0.7..+1.0 dark. Edit: -1.0..-0.8 lighter, +1.2..+1.8 tan to brown |
| `qwen21_nsfw-lora_v2.0` | Civitai 2958918 | Author's settings: 25+ steps, CFG 3-5, strength 0.8, sampler `er_sde`, scheduler `beta`, detailed prompts |

### Qwen21 Nude Edit LoRA (v2.0)

`qwen21_nude-edit_v2.0.safetensors` (Civitai 2956565), for the **Edit** workflows. No trigger word: it is trained on
short **Chinese** edit instructions (English barely trained). Keywords for the four modes:

| Keyword | Mode |
|---|---|
| 全裸 | Nude (all clothes off, or upper body only; say what to keep: socks, shoes, jewelry, hair, pose) |
| 开腿 | Legs spread |
| 女上位 | Cowgirl |
| 口交 | Oral |

v2 adds pubic hair: it is off by default, describe it in the prompt (阴毛). v2 also tries harder to keep accessories and
hairstyle. Civitai showed the LoRA as paid/early access when added; the download may need access on your account.

MiniMax H3 workflows reference the **nvfp4** text encoder (native on Blackwell). On other GPUs the stacks download
int8: pick `qwen3vl_32b_minimax_h3_int8_convrot` in the text encoder node once and save.

## Rules

- Public repo: **never commit tokens**. Check workflow JSONs for API keys in node settings.
- Every push to `main` goes live on the next instance you start.
