# vastai-setup

Vast.ai provisioning for ComfyUI. One script, many **stacks** (a stack = one model family:
its custom nodes, models, and workflows).

## Layout

```
provision.sh            the only file Vast fetches — download engine
stacks/<name>/
  stack.sh              what this stack needs: NODES+=, MODELS+=, CIVITAI+=, PIP_PACKAGES+=
  *.json                its workflows
```

Nodes used by every stack (rgthree, KJNodes, GGUF) are in `provision.sh`; stacks list only their own.

Repo holds only `.sh` and workflow `.json`. Models stay on Hugging Face / Civitai.

## Stacks

| Stack | What | Approx. download |
|---|---|---|
| `mmh3-dasiwa` | MiniMax H3 video + DaSiWa workflows | ~75 GB |
| `qwen21-multiref` | Qwen Image 2.1 multi-reference editing (bf16) + QwenVL enhancer | ~44 GB |
| `mmh3-obvpm-timeline` | MiniMax H3 timeline: generate / extend / bridge / upscale (needs ComfyUI 0.35.0+) | ~46 GB (+2.6 GB if mmh3-dasiwa also selected) |

Shared files download once, so `all` is less than the sum: llama-cpp and the Qwen3.5 GGUF LLM
(mmh3-dasiwa, qwen21-multiref); MiniMax H3 model, VAEs, text encoder, upscaler (mmh3-dasiwa, mmh3-obvpm-timeline).

## Use

In the Vast.ai template set `PROVISIONING_SCRIPT` to:

```
https://raw.githubusercontent.com/paroonk/vastai-setup/main/provision.sh
```

Template env vars:

| Var | Default | Purpose |
|---|---|---|
| `STACKS` | `all` | `mmh3-dasiwa`, `mmh3-dasiwa,qwen21-multiref`, or `all` (case-insensitive). Selects nodes, models and workflows together. |
| `CIVITAI_TOKEN` | — | Civitai API key. Required for Civitai downloads. |
| `HF_TOKEN` | — | Only for gated Hugging Face repos. |
| `TEXT_ENCODER` | `auto` | `nvfp4` (Blackwell) / `int8` / `auto` |
| `AUTO_UPDATE` | — | `false` skips `git pull` on existing custom nodes |
| `SETUP_REF` | `main` | Branch/tag to take stacks from — test changes on a branch first |

⚠️ `STACKS` defaults to `all`: once there are several stacks, an instance without `STACKS`
downloads every stack's models. Set it explicitly in each template.

## Add a workflow

Commit the `.json` into `stacks/<name>/`. Next instance installs it under ComfyUI workflows
`<name>/`. Same-named files there are overwritten.

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
| `stacks/mmh3-dasiwa/DasiwaMinimaxH3WorkflowsT2VA_cMMH3V25.json` | DaSiWa C-MMH3 v2.5 (Civitai 3195699) | `MiniMaxH3/` prefixes removed; checkpoint -> Civitai filename; latent upscaler -> conv_v1_bf16 |
| `stacks/qwen21-multiref/QwenImageEdit21-Wildcards-Qwen3.5.json` | huchukato QwenImageEdit21 v1.1 (Civitai 3353811) | diffusion model + text encoder -> official bf16 (author used Uncensored/Heretic int8) |
| `stacks/mmh3-obvpm-timeline/h3_obvpm_timeline_r2v_v0.1.1-005.json` | [chanon/comfyui-obvpm-timeline](https://github.com/chanon/comfyui-obvpm-timeline) (GPL-3.0) | `h3\` LoRA prefixes removed (nodes + presets); latent upscaler -> conv_v1_bf16 |

MiniMax H3 workflows reference the **nvfp4** text encoder (Blackwell). On other GPUs the stacks download
int8: pick `qwen3vl_32b_minimax_h3_int8_convrot` in the text encoder node once and save.

## Rules

- Public repo: **never commit tokens**. Check workflow JSONs for API keys in node settings.
- Every push to `main` goes live on the next instance you start.
