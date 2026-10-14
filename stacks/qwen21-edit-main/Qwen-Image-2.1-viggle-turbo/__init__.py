# Node registration for ComfyUI, added by paroonk/vastai-setup (not part of the upstream files).
# viggle_turbo.py is unmodified from https://huggingface.co/Viggle/Qwen-Image-2.1-viggle-turbo (comfyui/viggle_turbo.py),
# used under the Qwen RESEARCH LICENSE AGREEMENT (see LICENSE and NOTICE; non-commercial use only).
from .viggle_turbo import ViggleTurboSigmas, ViggleTurboLora

NODE_CLASS_MAPPINGS = {
    "ViggleTurboSigmas": ViggleTurboSigmas,
    "ViggleTurboLora": ViggleTurboLora,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "ViggleTurboSigmas": "Qwen-Image-2.1 Viggle Turbo Sigmas",
    "ViggleTurboLora": "Qwen-Image-2.1 Viggle Turbo LoRA (unmerged)",
}

__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS"]