#include <CoreImage/CoreImage.h>

// Edge color decontamination ("spill removal").
//
// Pixels on a soft matte edge are a mix of product and backdrop. Composited
// onto a new background as-is, they keep the old backdrop's color: a green halo
// from a garden, a warm fringe from a wooden table. We undo the mix instead.
//
//   observed      I = α·F + (1 − α)·B         (the compositing equation)
//   solved for F  F = (I − (1 − α)·B) / α
//
// B, the local backdrop color, is estimated on the Swift side as a blur of the
// background-only pixels, kept premultiplied: rgb = Σ w·I, a = Σ w, with
// w = (1 − α)⁴ so clean backdrop outweighs half-mixed edge pixels.
// Dividing rgb by a gives a weighted average of nearby backdrop colors that
// ignores the product itself.

extern "C" {
namespace coreimage {

float4 decontaminateEdges(sample_t image, sample_t background, sample_t matte, float strength) {
    float alpha = clamp(matte.r, 0.0, 1.0);

    // No backdrop nearby (deep inside the product): nothing to remove.
    float3 backdrop = background.a > 1e-3 ? background.rgb / background.a : image.rgb;

    // Solve the compositing equation. Below α ≈ 0.1 the division amplifies
    // noise, so the solve is capped there.
    float3 foreground = clamp((image.rgb - (1.0 - alpha) * backdrop) / max(alpha, 0.1), 0.0, 1.0);

    // α = 1 already yields the original pixel. Fade the correction out at very
    // low α, where the estimate is least reliable and barely visible anyway.
    float confidence = smoothstep(0.02, 0.15, alpha);
    return float4(mix(image.rgb, foreground, strength * confidence), image.a);
}

}
}
