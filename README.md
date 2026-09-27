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
| `qwen21` | Qwen Image 2.1 multi-reference editing (bf16) + QwenVL enhancer | ~44 GB |

Shared files (llama-cpp, Qwen3.5 GGUF LLM) download once, so `all` is less than the sum.

## Use

In the Vast.ai template set `PROVISIONING_SCRIPT` to:

```
https://raw.githubusercontent.com/paroonk/vastai-setup/main/provision.sh
```

Template env vars:

| Var | Default | Purpose |
|---|---|---|
| `STACKS` | `all` | `mmh3-dasiwa`, `mmh3-dasiwa,qwen21`, or `all` (case-insensitive). Selects nodes, models and workflows together. |
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

## Rules

- Public repo: **never commit tokens**. Check workflow JSONs for API keys in node settings.
- Every push to `main` goes live on the next instance you start.
