# LoRA usage notes

Settings, trigger words and prompts for the LoRAs in `families/*/family.sh`. The family files keep only a one-line
hint per LoRA; the details live here. Saved file names are in the family files.

## qwen21 (Qwen Image 2.1)

### Speed

| LoRA | Notes |
|---|---|
| Viggle Turbo v0.3 (6-step) | Strength 1.0. For accelerated generation / editing. |

### Editing control

| LoRA | Notes |
|---|---|
| Consistency (ausboss) | Strength 1.0, no trigger word. Preserves the unchanged parts of the source image while editing; lower strength = more freedom / more image drift. `-2000` (step 2000, commented out in the family file): tighter alignment, slightly paler paintings. |
| Outpaint v2 (ausboss) | Start at strength 1.0. Pad with solid gray `#808080`. Instruction: "Outpaint the image: replace the solid gray areas with a seamless continuation of the scene, keeping the existing picture unchanged." Optional: "Scene: <describe what should appear in the expanded area>". |
| Outfit Swap Consistency | Strength 1.0, no trigger. Image1 = person, Image2 = outfit reference. Preserves framing, face, pose and background during outfit changes. |
| Restore | Strength 1.0 for small / compressed in-focus photos, 0.5 for blurry ones. No trigger. Work at about 2 MP, both sides divisible by 32. CFG 1, euler, simple, denoise 1.0. Steps: 8 with Viggle Turbo at 1.0, or 25 without Turbo. Do not stack with the general Consistency LoRA. |

### Realism

| LoRA | Notes |
|---|---|
| Nice Asians Qwen 2.1 | Strength 0.6-0.8 (default 0.7). No trigger. |
| Realism Edit v2 | Trigger: "convert this into a real phone photo". Start around 0.8-1.0. Best as a separate realism pass after the main edit. |

### BFS (face / body swap)

Author settings for both: strength 1.0, sampler `deis_2m`, scheduler simple, 8 steps, CFG 1.0, denoise 1.0 (negative prompt unused at CFG 1).
Also uses `p_qwen_image_2.1_8step_v0.1.safetensors` at strength 1.0. Needs RES4LYF nodes (for `deis_2m`) and an updated ComfyUI.
Image1 = target / base image, Image2 = replacement reference. Resolution matters: the author reports 2K reduces Qwen 2.1 blur / detail loss.

- **Head Swap v1.1** prompt: `Start with <Image1> as the base image, keeping its lighting, environment, and background. Remove the head from <Image1> completely and replace it with the head from <Image2>, strictly preserving the hair, eye color, nose structure from <Image2>. Copy the direction of the eye, head rotation, micro expressions from <Image1>, high quality, sharp details, 4K`
- **Body Swap v1.0** prompt: `Start with <Image1> as the base image, keeping its lighting, environment, and background. Replace the body from <Image1> with the body from <Image2>, strictly preserving the clothing, body shape and proportions from <Image2>. Strictly replicate the exact pose, arm positions, leg positions, hand gestures, head rotation, eye direction and micro expressions from <Image1>`

### Appearance sliders

| LoRA | Notes |
|---|---|
| Skin Tone Slider v1 | Positive weight darkens, negative lightens. No trigger. T2I: -0.8..-0.4 fair / porcelain, 0 baseline, +0.3..+0.6 warm tan / golden bronze (sweet spot), +0.7..+1.0 deep brown. Edits: -1.0..-0.8 lighten, +1.2..+1.8 tan / rich brown (sweet spot), +2.0 strongest dark shift. |
| Pornmaster Breasts Slider v1 | Adjusts upper-body proportions, keeps identity. Positive = more volume, negative = less. T2I: +0.3..+0.6 recommended, +0.7..+1.0 stronger, avoid above +1.0; -1.0..-0.4 for a smaller / slender contour (listed eta 1.8). I2I: +1.0..+2.0 recommended, +2.0..+3.0 stronger, avoid above +3.0 (can distort anatomy). |

### NSFW

| LoRA | Notes |
|---|---|
| NSFW LoRA v2.0 | Steps 25+, CFG 3-6, strength 0.8-1.0, sampler `er_sde` (Euler is much worse), scheduler `beta`. Trained on (concepts, not trigger words): Blowjobs, Cowgirl, Cum, Vaginas, Anal, Penis, Doggystyle, Missionary, Dildo, Pussy Licking. |
| Vagina v1.0 | No notes from the author. |
| Nude Edit v3.0 | CFG 3 recommended. Trigger: `Nude Edit` / `全裸编辑`, `Legs Spread` / `开腿`, `Cowgirl` / `女上位`, `Oral` / `口交`. |
| FemaledVaginus-NSFW v1.3 | Strength 0.7-1.0, `er_sde`, `beta`, 20 steps, CFG 3.0 (raise CFG for more detail). |

## h3 (MiniMax H3)

| LoRA | Notes |
|---|---|
| Turbo, obvpm timeline presets | The Turbo LoRAs in the family file are the ones the obvpm timeline presets load ("vanilla", "lightx2v", "taomate 3 step refine"). Saved under loras/h3/ with the original names, matching the author workflows' h3\ paths (no edit, no rewrite). |
| Turbo v4 step600 (larryvrh, Apache-2.0) | Strength 1.0, 6-8 steps, scheduler simple. Use with the MiniMax-H3 Turbo LoRA + Turbo Sampler nodes (`Larryvrh/ComfyUI-MiniMax-H3-Turbo`). `low_vram`: off first, enable only if out of memory. The author documents T2V / I2V; verify Ref2VA compatibility in your OBVPM preset. |
| People Realism (fal) | Prompt prefix `r34l1sm`. Strength 1.0; 0.6-0.8 for a lighter effect. T2V / I2V / R2V. |
| Character Swap v1, 1000-step (akatz-ai) | Needs the Ref2VA base. Model-only LoRA loader, strength 1.0. No trigger word; name the target explicitly in the prompt. Source video = `<Video 1>`, replacement image = `<Picture 1>`. Start with continuous 4-5 second shots; motion / lip sync may drift. Not a Turbo LoRA; Turbo is optional. |
| MysticXXX MMH3 v1 | Style LoRA, no notes. |
