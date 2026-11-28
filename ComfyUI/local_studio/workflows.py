import secrets
import math

from PIL import Image

import folder_paths


MODELS = [
    dict(id="qwen-chat", name="Qwen Heretic", family="chat", generation=False, editing=False,
         encoder="qwen3-vl-4b-heretic_nvfp4.safetensors", clip_type="stable_diffusion", steps=0, cfg=0, sampler="", scheduler=""),
    dict(id="fibo-dev", name="Fibo 2.0 Dev", family="fibo", generation=True, editing=True,
         weights="fibo2_dev_nvfp4.safetensors", encoder="qwen3vl_4b_bf16.safetensors",
         vae="flux2-vae.safetensors", clip_type="fibo2", steps=50, cfg=5, sampler="euler", scheduler="simple"),
    dict(id="moss-sft", name="MOSS Image SFT", family="moss", generation=True, editing=False,
         weights="moss_image_sft_nvfp4.safetensors", encoder="qwen3.5_9b_w4a8_gptq.safetensors",
         vae="flux2-vae_small.safetensors", clip_type="moss_image", steps=25, cfg=2.5, sampler="er_sde", scheduler="simple"),
    dict(id="fibo-edit", name="Fibo 2.0 Edit Turbo", family="fibo", generation=False, editing=True,
         weights="fibo2_edit_turbo_nvfp4.safetensors", encoder="qwen3vl_4b_bf16.safetensors",
         vae="flux2-vae.safetensors", clip_type="fibo2", steps=4, cfg=1, sampler="euler", scheduler="simple"),
    dict(id="qwen-image", name="Qwen Image 2.1", family="qwen", generation=True, editing=True,
         weights="qwen_image_2.1_nvfp4.safetensors", encoder="qwen3vl_8b_nvfp4.safetensors",
         vae="qwen_image_2.1_vae_bf16.safetensors", clip_type="qwen_image", steps=40, cfg=1, sampler="euler", scheduler="simple"),
]


FOLDERS = {"weights": "diffusion_models", "encoder": "text_encoders", "vae": "vae"}
SYSTEM_CHAT = "You are a helpful assistant. Answer directly in the user's language."
SYSTEM_ENHANCE = {
    None: ("Rewrite the request as one detailed image prompt. Preserve every requested subject and exact visible text. "
           "Describe composition, lighting, materials and style. Output only the rewritten prompt as plain text, without labels, headings or Markdown."),
    "fibo-edit": "Rewrite the image edit request as one short imperative sentence. Output only the instruction.",
    "fibo-dev": ('Expand into a JSON image caption with short_description, objects, background_setting, lighting, '
                 'aesthetics, style_medium and text_render. Preserve exact requested visible text. Output JSON only.'),
}
NEGATIVE = {"moss": "worst quality, bad anatomy, watermark, jpeg artifact"}


def installed(model):
    return all(folder_paths.get_full_path(folder, model[key]) is not None for key, folder in FOLDERS.items() if key in model)


def catalog():
    return [model | {"installed": installed(model)} for model in MODELS]


def build_workflow(body):
    model = next((m for m in MODELS if m["id"] == body["model"]), None)
    if model is None or not installed(model):
        raise ValueError("The selected model is not installed.")
    images, enhance, prompt = body["images"], body["enhance"], body["prompt"]
    width, height, max_tokens = int(body["width"]), int(body["height"]), int(body["max_tokens"])
    text_mode = enhance or model["family"] == "chat"
    if not text_mode and images and not model["editing"]:
        raise ValueError("This model supports generation only. Choose an editing model for attachments.")
    if not text_mode and not images and not model["generation"]:
        raise ValueError("This model needs an image to edit.")
    seed = secrets.randbelow(2**53)
    graph = {}

    def node(key, kind, **inputs):
        graph[key] = {"class_type": kind, "inputs": inputs}
        return [key, 0]

    input_directory = folder_paths.get_input_directory()
    refs = {}
    for i, filename in enumerate(images):
        if not folder_paths.exists_annotated_filepath(filename) or \
                not folder_paths.is_within_directory(input_directory, folder_paths.get_annotated_filepath(filename)):
            raise ValueError("Reference image is not an uploaded input.")
        refs[f"images.image_{i + 1}"] = node(f"image{i}", "LoadImage", image=filename)

    if text_mode:
        chat = MODELS[0]
        clip = node("clip", "CLIPLoader", clip_name=chat["encoder"], type=chat["clip_type"], device="default")
        if enhance:
            turns = [{"role": "system", "text": SYSTEM_ENHANCE.get(model["id"], SYSTEM_ENHANCE[None])},
                     {"role": "user", "text": prompt}]
        else:
            turns = [{"role": "system", "text": SYSTEM_CHAT}] + body["messages"]
            if turns[-1].get("role") != "user":
                turns.append({"role": "user", "text": prompt})
        if any(turn["role"] not in ("system", "user", "assistant") for turn in turns):
            raise ValueError("Invalid chat role.")
        # Attached images precede the newest turn's text.
        vision = "<|vision_start|><|image_pad|><|vision_end|>" * len(refs)
        formatted = "".join(f"<|im_start|>{turn['role']}\n{vision if i == len(turns) - 1 else ''}{turn['text']}<|im_end|>\n"
                            for i, turn in enumerate(turns)) + "<|im_start|>assistant\n"
        node("output", "LocalStudioTextStream", clip=clip, prompt=formatted, client_id=body["client_id"],
             request_id=body["request_id"], max_tokens=max_tokens, seed=seed, **refs)
        return {"prompt": graph, "metadata": {"model": "Qwen3-VL 4B Heretic", "model_id": chat["id"], "seed": seed,
                                              "prompt": prompt, "encoder": chat["encoder"],
                                              "width": width, "height": height, "max_tokens": max_tokens}}

    family = model["family"]
    unet = node("model", "UNETLoader", unet_name=model["weights"], weight_dtype="default")
    clip = node("clip", "CLIPLoader", clip_name=model["encoder"], type=model["clip_type"], device="default")
    vae = node("vae", "VAELoader", vae_name=model["vae"])
    negative_prompt = NEGATIVE.get(family, "")
    if family == "fibo":
        # Edits keep the requested pixel area at the reference's (EXIF-oriented) aspect ratio.
        ref_width, ref_height = width, height
        if refs:
            with Image.open(folder_paths.get_annotated_filepath(images[0])) as reference:
                rw, rh = reference.size
                if reference.getexif().get(274) in (5, 6, 7, 8):
                    rw, rh = rh, rw
            ref_width = max(16, round(math.sqrt(width * height * rw / rh) / 16) * 16)
            ref_height = max(16, round(math.sqrt(width * height * rh / rw) / 16) * 16)
        positive = node("encode", "TextEncodeFibo2", clip=clip, vae=vae, prompt=prompt, negative_prompt="",
                        width=ref_width, height=ref_height, batch_size=1, **refs)
        negative, latent = ["encode", 1], ["encode", 2]
    elif family == "qwen":
        positive = node("encode", "TextEncodeQwenImage21", clip=clip, vae=vae, prompt=prompt, negative_prompt="",
                        resolution=max(32, round(math.sqrt(width * height) / 32) * 32), **refs)
        negative = ["encode", 1]
        latent = ["encode", 2] if refs else node("latent", "EmptyLatentImage", width=width, height=height, batch_size=1)
    else:
        positive = node("positive", "CLIPTextEncode", clip=clip, text=prompt)
        negative = node("negative", "CLIPTextEncode", clip=clip, text=negative_prompt)
        latent = node("latent", "EmptyFlux2LatentImage", width=width, height=height, batch_size=1)
        if refs:
            node("reference", "ReferenceMultiLatent", positive=positive, negative=negative, vae=vae, resolution="resize",
                 **{"resolution.megapixels": width * height / (1024 * 1024)},
                 **{f"images.image{i}": value for i, value in enumerate(refs.values())})
            positive, negative, latent = ["reference", 0], ["reference", 1], ["reference", 2]

    metadata = {key: model[key] for key in ("steps", "cfg", "sampler", "scheduler")}
    samples = node("sample", "KSampler", model=unet, positive=positive, negative=negative, latent_image=latent,
                   seed=seed, steps=model["steps"], cfg=model["cfg"], sampler_name=model["sampler"],
                   scheduler=model["scheduler"], denoise=1.0)
    node("output", "SaveImage", images=node("decode", "VAEDecode", samples=samples, vae=vae),
         filename_prefix="LocalStudio/" + model["id"])
    metadata.update(model=model["name"], model_id=model["id"], seed=seed, prompt=prompt, negative_prompt=negative_prompt,
                    diffusion_model=model["weights"], encoder=model["encoder"], vae=model["vae"],
                    width=width, height=height, max_tokens=max_tokens)
    return {"prompt": graph, "metadata": metadata}
