#!/usr/bin/env python3
"""Converts open-source salient-object segmentation models to Core ML for the
CleanCut benchmark (Vision vs Core ML across compute units).

Models (both Apache-2.0, by Xuebin Qin et al.):
  - U²-Netp  (4.7 MB, 320×320)   https://github.com/xuebinqin/U-2-Net
  - ISNet    (general-use, 1024×1024) https://github.com/xuebinqin/DIS

Each model is wrapped so the Core ML graph is self-contained:
  image (RGB, 0…255) → exact preprocessing → network → min-max normalized mask,
emitted as a Float16 grayscale *image* output, so Swift receives a
CVPixelBuffer it can wrap in a CIImage with no copying or array math.

Weights are downloaded, loaded with strict=True (which proves they match the
official architecture) and their SHA-256 recorded in Models/manifest.json.

Usage:  make -C Tools/ModelConversion      (or: .venv/bin/python convert.py)
"""

import hashlib
import importlib.util
import json
import sys
import types
import urllib.request
from pathlib import Path

import coremltools as ct
import coremltools.optimize.coreml as cto
import numpy as np
import torch
import torch.nn as nn

ROOT = Path(__file__).resolve().parent
WEIGHTS = ROOT / "weights"
SOURCES = ROOT / "build" / "sources"
OUTPUT = ROOT.parent.parent / "Models"

U2NET_COMMIT = "ac7e1c817ecab7c7dff5ce6b1abba61cd213ff29"
DIS_COMMIT = "b6764e20381f6f42a70f83fa3324181529ed1403"

MODELS = {
    "U2Netp": {
        "source": f"https://raw.githubusercontent.com/xuebinqin/U-2-Net/{U2NET_COMMIT}/model/u2net.py",
        "class": "U2NETP",
        "weights": {"gdrive": "1rbSTGKAE-MTxBYHd-51l2hMOQPT_7EPy", "file": "u2netp.pth"},
        "size": 320,
        # torchvision-style ImageNet normalization, as in u2net_test.py
        "mean": (0.485, 0.456, 0.406),
        "std": (0.229, 0.224, 0.225),
        "license": "Apache-2.0",
        "description": "U²-Netp salient object detection (Qin et al. 2020), 320×320.",
        "palettize": False,
    },
    "ISNet": {
        "source": f"https://raw.githubusercontent.com/xuebinqin/DIS/{DIS_COMMIT}/IS-Net/models/isnet.py",
        "class": "ISNetDIS",
        "weights": {"hf": ("NimaBoscarino/IS-Net_DIS-general-use", "isnet-general-use.pth"), "file": "isnet-general-use.pth"},
        "size": 1024,
        # DIS Inference.py: x / 255, normalize(mean=0.5, std=1.0)
        "mean": (0.5, 0.5, 0.5),
        "std": (1.0, 1.0, 1.0),
        "license": "Apache-2.0",
        "description": "IS-Net general-use dichotomous image segmentation (Qin et al. 2022), 1024×1024.",
        "palettize": True,
    },
}


def fetch(url: str, destination: Path) -> Path:
    if not destination.exists():
        destination.parent.mkdir(parents=True, exist_ok=True)
        print(f"  downloading {url}")
        urllib.request.urlretrieve(url, destination)
    return destination


def fetch_weights(spec: dict) -> Path:
    path = WEIGHTS / spec["file"]
    if path.exists():
        return path
    WEIGHTS.mkdir(parents=True, exist_ok=True)
    if "gdrive" in spec:
        import gdown
        gdown.download(id=spec["gdrive"], output=str(path), quiet=False)
    else:
        from huggingface_hub import hf_hub_download
        repo, filename = spec["hf"]
        downloaded = hf_hub_download(repo_id=repo, filename=filename, local_dir=WEIGHTS)
        Path(downloaded).rename(path) if Path(downloaded) != path else None
    return path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_module(name: str, path: Path) -> types.ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Wrapped(nn.Module):
    """Normalization → network → first (finest) side output → min-max to 0…1."""

    def __init__(self, net: nn.Module, mean, std):
        super().__init__()
        self.net = net
        self.register_buffer("mean", torch.tensor(mean).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(std).view(1, 3, 1, 1))

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        x = (image - self.mean) / self.std
        out = self.net(x)
        # U²-Net returns a tuple of side outputs; ISNet returns ([side outputs], [features]).
        mask = out[0][0] if isinstance(out[0], (list, tuple)) else out[0]
        lo = mask.amin(dim=(2, 3), keepdim=True)
        hi = mask.amax(dim=(2, 3), keepdim=True)
        return (mask - lo) / (hi - lo + 1e-8)


def convert(name: str, spec: dict) -> list[dict]:
    print(f"\n== {name}")
    module = load_module(name.lower(), fetch(spec["source"], SOURCES / f"{name.lower()}.py"))
    weights = fetch_weights(spec["weights"])

    net = getattr(module, spec["class"])(3, 1) if spec["class"] == "U2NETP" else getattr(module, spec["class"])()
    state = torch.load(weights, map_location="cpu", weights_only=True)
    net.load_state_dict(state, strict=True)  # proves the weights match the official architecture
    net.eval()
    model = Wrapped(net, spec["mean"], spec["std"]).eval()

    size = spec["size"]
    example = torch.rand(1, 3, size, size)
    with torch.no_grad():
        traced = torch.jit.trace(model, example)
        reference = model(example).numpy()

    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=example.shape, scale=1 / 255.0, color_layout=ct.colorlayout.RGB)],
        outputs=[ct.ImageType(name="mask", color_layout=ct.colorlayout.GRAYSCALE_FLOAT16)],
        minimum_deployment_target=ct.target.iOS18,
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )
    describe(mlmodel, spec)
    check_parity(mlmodel, example, reference)

    variants = [(name, mlmodel)]
    if spec["palettize"]:
        config = cto.OptimizationConfig(global_config=cto.OpPalettizerConfig(nbits=6, mode="kmeans"))
        palettized = cto.palettize_weights(mlmodel, config)
        describe(palettized, spec, suffix=" 6-bit palettized weights.")
        check_parity(palettized, example, reference)
        variants.append((f"{name}-6bit", palettized))

    OUTPUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for variant_name, variant in variants:
        path = OUTPUT / f"{variant_name}.mlpackage"
        variant.save(str(path))
        size_mb = sum(f.stat().st_size for f in path.rglob("*") if f.is_file()) / 1_048_576
        print(f"  saved {path.relative_to(OUTPUT.parent)} ({size_mb:.1f} MB)")
        entries.append({
            "name": variant_name,
            "package": path.name,
            "inputSize": size,
            "sizeMB": round(size_mb, 1),
            "license": spec["license"],
            "source": spec["source"],
            "weightsSHA256": sha256(weights),
        })
    return entries


def describe(mlmodel, spec: dict, suffix: str = "") -> None:
    mlmodel.author = "Xuebin Qin et al.; converted by CleanCut"
    mlmodel.license = spec["license"]
    mlmodel.short_description = spec["description"] + suffix
    mlmodel.version = "1.0"


def check_parity(mlmodel, example: torch.Tensor, reference: np.ndarray) -> None:
    """Runs the converted model on the traced example and compares with PyTorch."""
    from PIL import Image

    pixels = (example[0].permute(1, 2, 0).numpy() * 255).round().astype(np.uint8)
    prediction = mlmodel.predict({"image": Image.fromarray(pixels)})["mask"]
    predicted = np.asarray(prediction, dtype=np.float32)
    error = np.abs(predicted - reference[0, 0]).mean()
    print(f"  Core ML vs PyTorch mean abs error: {error:.4f}")
    if error > 0.05:
        sys.exit(f"parity check failed for {mlmodel.short_description}")


def main() -> None:
    names = sys.argv[1:] or list(MODELS)
    manifest_path = OUTPUT / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    for name in names:
        for entry in convert(name, MODELS[name]):
            manifest[entry["name"]] = entry
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"\nwrote {manifest_path.relative_to(OUTPUT.parent)}")


if __name__ == "__main__":
    main()
