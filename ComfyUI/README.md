# ComfyUI integration

Installed in `C:\Users\Leon\Documents\ComfyUI_windows_portable` against ComfyUI 0.46.0 (`a277b5b`). Runtime Python modules are the app backend; no model conversion, migration, demo or installation scripts are bundled.

To reproduce manually, apply `text-streaming.patch` from the ComfyUI repository root, copy `local_studio` into `custom_nodes`, and install that extension's `requirements.txt` (Bonjour discovery and original HEIC decoding) using ComfyUI's embedded Python. Add `--listen 0.0.0.0 --port 8188` to `run_nvidia_gpu.bat`. This has already been done in the configured installation.

The patch adds a context-local token callback to Qwen's existing autoregressive decoder, checks cancellation between tokens, and includes the quantization publisher's Qwen 2.1 NVFP4 conditioning correction. The V3 output node streams cumulative decoded text as `local_studio_text` WebSocket events, scoped by request and client. Text and images execute on ComfyUI's existing queue with native model loading and memory management.

The extension advertises `_localstudio._tcp` through multicast DNS, exposes `/local-studio/catalog` and builds native graphs at `/local-studio/workflow`. The iPhone uploads original attachments, submits graphs through `/prompt`, receives progress and text on `/ws`, then retrieves saved output through `/history` and `/view`. Cancellation targets the specific job, leaving other clients' jobs alone. All inference traffic remains on the local network.

Windows Firewall needs inbound TCP 8188 and UDP 5353 on the private local network. Both dedicated private-network firewall rules are enabled.

The core patch and copied ComfyUI-derived integration follow ComfyUI's GPL-3.0 license, included here. The NVFP4 conditioning changes originate from [BennyDaBall's runtime patch](https://huggingface.co/BennyDaBall/Qwen-Image-2.1-NVFP4/tree/main/runtime).

## Model presets

| Model | Enabled use | Steps | CFG | Sampler / schedule |
| --- | --- | ---: | ---: | --- |
| FLUX 3 Klein | Generate, edit | 16 | 1 | Euler / simple |
| Fibo 2.0 Dev | Generate, edit | 50 | 5 | Euler / simple |
| MOSS Image SFT | Generate | 25 | 2.5 | er_sde / simple |
| Qwen Image 2.1 Turbo | Generate, edit | 8 | 1 | Euler / fixed official sigmas |
| Fibo 2.0 Edit Turbo | Edit | 4 | 1 | Euler / simple |
| Qwen Image 2.1 | Generate, edit | 40 | 1 | Euler / simple |

Qwen3-VL 4B, shared with Fibo and FLUX conditioning, also supplies autoregressive chat and prompt enhancement. The text node uses 0.7 temperature, top-k 20, top-p 0.8 and repetition penalty 1.05. Image presets are fixed; output canvas and text response length are configurable in Settings. Edits use the reference aspect ratio at the trained resolution. Attachment files are preserved; resizing inside model conditioning follows the native workflow.

Sources: [FLUX quantization](https://huggingface.co/BennyDaBall/flux-3-image-klein-NVFP4), [Fibo Dev](https://huggingface.co/BennyDaBall/Fibo-2.0-dev-NVFP4), [Fibo Edit](https://huggingface.co/BennyDaBall/Fibo-2.0-edit-turbo-NVFP4), [MOSS](https://huggingface.co/BennyDaBall/MOSS-Image-SFT-NVFP4), [Qwen Turbo](https://huggingface.co/BennyDaBall/Qwen-Image-2.1-Turbo-NVFP4), [Qwen 2.1](https://huggingface.co/BennyDaBall/Qwen-Image-2.1-NVFP4), [native ComfyUI templates](https://github.com/Comfy-Org/workflow_templates/tree/main/templates), and [MOSS native integration](https://github.com/OpenMOSS/MOSS-Image/blob/main/comfyui/README.md).

FLUX uses the quantization publisher's 16-step distilled preset, including its explicit ModelSamplingFlux shift of 2.77259. The current ComfyUI text-to-image template also offers a 15-step er_sde variant. Qwen Turbo follows the linked NVFP4 release's BasicGuider (CFG 1) for both generation and editing; the current generic ComfyUI edit template uses CFG 8. MOSS editing requires a separate editing LoRA, so it is not advertised for this SFT-only installation.
