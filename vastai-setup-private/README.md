# vastai-setup-private

Things that must not be published: put the folders here, next to these scripts. Git ignores every sub-folder and zip in this directory.

| Folder | Goes to |
|---|---|
| `comfyui-obvpm-pro-extensions/` | `ComfyUI/custom_nodes/comfyui-obvpm-pro-extensions` (supporters-only licence: never push it) |
| `refmods/` | `ComfyUI/models/refmods` (your RefMod files) |

The same two lines are in `stacks/h3-obvpm-timeline/stack.sh`:
`private custom_nodes comfyui-obvpm-pro-extensions` and `private models refmods`.

## Scripts

| Script | Where to run it | What it does |
|---|---|---|
| `copy-to-comfyui.bat [ComfyUI folder]` | Windows PC with ComfyUI | Copies the two folders into ComfyUI. Without an argument it uses `..\ComfyUI`, then `F:\ComfyUI\ComfyUI`. |
| `upload-to-vast.bat PORT HOST` | Windows PC | Uploads the two folders to `/workspace/vastai-setup-private/` on a Vast instance (SSH button gives PORT and HOST). |
| `copy-to-comfyui.sh [ComfyUI folder]` | The Vast instance | Copies them from `/workspace/vastai-setup-private/` into `/workspace/ComfyUI`. Provisioning does this by itself; use the script when you uploaded after provisioning. |

## On a new Vast instance

1. `upload-to-vast.bat PORT HOST`
2. On the instance, run provisioning again (or `bash /workspace/vastai-setup-private/copy-to-comfyui.sh` for just this step), then
   `supervisorctl restart comfyui`.
