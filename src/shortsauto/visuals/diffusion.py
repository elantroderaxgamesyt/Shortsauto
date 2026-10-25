"""Imágenes por escena con Stable Diffusion local (solo con GPU NVIDIA).

- sdxl-lightning: SDXL base + UNet SDXL-Lightning 4 pasos (OpenRAIL++), 6 GB+ de VRAM.
- sd15-lcm: SD 1.5 + LoRA LCM (OpenRAIL-M), 4 GB de VRAM.
Los pesos se descargan a models/hf la primera vez (huggingface_hub reanuda solo).
"""
import gc
import logging
from pathlib import Path

from ..config import MODELS

log = logging.getLogger(__name__)

HF_CACHE = MODELS / "hf"

STYLES = {
    "realista": "cinematic photo, ultra detailed, dramatic lighting, 35mm, sharp focus",
    "anime": "anime key visual, vibrant colors, detailed background, studio quality",
    "minimalista": "minimalist digital art, clean shapes, soft gradients, bold composition",
    "3d": "3d render, octane render, soft global illumination, highly detailed, vibrant",
}
NEGATIVE = "text, watermark, logo, signature, blurry, lowres, deformed, ugly, extra fingers"

SPECS = {
    "sdxl-lightning": dict(size=(768, 1344), gb=11.5),
    "sd15-lcm": dict(size=(512, 912), gb=4.3),
}


def available() -> bool:
    try:
        import torch
        return torch.cuda.is_available()
    except ImportError:
        return False


def download(model: str) -> None:
    from huggingface_hub import hf_hub_download, snapshot_download
    if model == "sdxl-lightning":
        snapshot_download("stabilityai/stable-diffusion-xl-base-1.0", cache_dir=HF_CACHE,
                          allow_patterns=["model_index.json", "scheduler/*", "text_encoder/*.json",
                                          "text_encoder/model.fp16.safetensors", "text_encoder_2/*.json",
                                          "text_encoder_2/model.fp16.safetensors", "tokenizer/*",
                                          "tokenizer_2/*", "unet/config.json"])
        snapshot_download("madebyollin/sdxl-vae-fp16-fix", cache_dir=HF_CACHE,
                          allow_patterns=["config.json", "diffusion_pytorch_model.safetensors"])
        hf_hub_download("ByteDance/SDXL-Lightning", "sdxl_lightning_4step_unet.safetensors",
                        cache_dir=HF_CACHE)
    else:
        snapshot_download("stable-diffusion-v1-5/stable-diffusion-v1-5", cache_dir=HF_CACHE,
                          allow_patterns=["model_index.json", "scheduler/*", "text_encoder/config.json",
                                          "text_encoder/model.fp16.safetensors", "tokenizer/*",
                                          "unet/config.json", "unet/diffusion_pytorch_model.fp16.safetensors",
                                          "vae/config.json", "vae/diffusion_pytorch_model.fp16.safetensors",
                                          "feature_extractor/*"])
        snapshot_download("latent-consistency/lcm-lora-sdv1-5", cache_dir=HF_CACHE)


class ImageGenerator:
    def __init__(self, model: str, vram_gb: float):
        import torch
        from diffusers import (AutoencoderKL, EulerDiscreteScheduler, LCMScheduler,
                               StableDiffusionPipeline, StableDiffusionXLPipeline,
                               UNet2DConditionModel)
        from huggingface_hub import hf_hub_download
        from safetensors.torch import load_file

        self.model = model
        self.size = SPECS[model]["size"]
        dtype = torch.float16
        if model == "sdxl-lightning":
            base = "stabilityai/stable-diffusion-xl-base-1.0"
            config = UNet2DConditionModel.load_config(base, subfolder="unet", cache_dir=HF_CACHE)
            unet = UNet2DConditionModel.from_config(config).to(dtype)
            unet.load_state_dict(load_file(hf_hub_download(
                "ByteDance/SDXL-Lightning", "sdxl_lightning_4step_unet.safetensors", cache_dir=HF_CACHE)))
            vae = AutoencoderKL.from_pretrained("madebyollin/sdxl-vae-fp16-fix", torch_dtype=dtype,
                                                cache_dir=HF_CACHE)
            self.pipe = StableDiffusionXLPipeline.from_pretrained(
                base, unet=unet, vae=vae, torch_dtype=dtype, variant="fp16", cache_dir=HF_CACHE)
            self.pipe.scheduler = EulerDiscreteScheduler.from_config(
                self.pipe.scheduler.config, timestep_spacing="trailing")
            self.steps, self.guidance = 4, 0.0
        else:
            self.pipe = StableDiffusionPipeline.from_pretrained(
                "stable-diffusion-v1-5/stable-diffusion-v1-5", torch_dtype=dtype, variant="fp16",
                cache_dir=HF_CACHE, safety_checker=None, requires_safety_checker=False)
            self.pipe.scheduler = LCMScheduler.from_config(self.pipe.scheduler.config)
            self.pipe.load_lora_weights("latent-consistency/lcm-lora-sdv1-5", cache_dir=HF_CACHE)
            self.pipe.fuse_lora()
            self.steps, self.guidance = 6, 1.5
        # Con poca VRAM descargamos partes del modelo a RAM entre pasos.
        if vram_gb < 10:
            self.pipe.enable_model_cpu_offload()
        else:
            self.pipe.to("cuda")
        self.pipe.enable_vae_tiling()
        self.torch = torch

    def generate(self, prompt: str, style: str, out: Path, seed: int) -> Path:
        w, h = self.size
        full = f"{prompt}, {STYLES.get(style, STYLES['realista'])}, vertical composition"
        g = self.torch.Generator("cuda").manual_seed(seed)
        kwargs = dict(prompt=full, width=w, height=h, num_inference_steps=self.steps,
                      guidance_scale=self.guidance, generator=g)
        if self.guidance > 1:
            kwargs["negative_prompt"] = NEGATIVE
        self.pipe(**kwargs).images[0].save(out)
        return out

    def close(self) -> None:
        del self.pipe
        gc.collect()
        self.torch.cuda.empty_cache()


def is_oom(e: Exception) -> bool:
    return "out of memory" in str(e).lower() or type(e).__name__ == "OutOfMemoryError"
