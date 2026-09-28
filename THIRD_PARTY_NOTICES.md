# Third-party notices

## U²-Net / U²-Netp
- **Used for:** the bundled Core ML segmentation model (`Models/U2Netp.mlpackage`), converted by `Tools/ModelConversion/convert.py`.
- **Source:** https://github.com/xuebinqin/U-2-Net (model definition at commit `ac7e1c8`); official `u2netp.pth` weights.
- **Weights SHA-256:** `e7567cde013fb64813973ce6e1ecc25a80c05c3ca7adbc5a54f3c3d90991b854`
- **License:** Apache License 2.0
- **Citation:** Xuebin Qin, Zichen Zhang, Chenyang Huang, Masood Dehghan, Osmar R. Zaiane, Martin Jagersand. *U²-Net: Going Deeper with Nested U-Structure for Salient Object Detection.* Pattern Recognition 106, 2020.

## IS-Net (DIS), general-use weights
- **Used for:** benchmarking only. The models are generated locally by `Tools/ModelConversion` and are not committed or bundled.
- **Source:** https://github.com/xuebinqin/DIS (model definition at commit `b6764e2`); `isnet-general-use.pth`, downloaded from the Apache-2.0 Hugging Face mirror `NimaBoscarino/IS-Net_DIS-general-use`. The weights load with `strict=True` into the official architecture.
- **Weights SHA-256:** `9e1aafea58f0b55d0c35077e0ceade6ba1ba2bce372fd4f8f77215391f3fac13`
- **License:** Apache License 2.0
- **Citation:** Xuebin Qin, Hang Dai, Xiaobin Hu, Deng-Ping Fan, Ling Shao, Luc Van Gool. *Highly Accurate Dichotomous Image Segmentation.* ECCV 2022.

## Considered and not used
- **BRIA RMBG 1.4 / 2.0.** CC BY-NC 4.0 (non-commercial) is not compatible with an MIT-licensed project.
- **MODNet.** It's trained for portraits, not products.

The full Apache License 2.0 text is at https://www.apache.org/licenses/LICENSE-2.0.
