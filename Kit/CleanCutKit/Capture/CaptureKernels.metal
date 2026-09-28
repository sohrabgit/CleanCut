#include <CoreImage/CoreImage.h>

// Per-pixel statistics for guided capture. Each kernel writes four values that
// `CIAreaAverage` then reduces to frame-wide means, so one small readback
// answers "is it sharp, lit, glare-free?". Values are weighted by the subject
// matte `m` so the product decides, not the backdrop. Inputs are camera-encoded
// (the analysis context isn't color-managed), which is where clipping happens.

extern "C" { namespace coreimage {

static float luma(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

/// `(m·lap², m·Y, m·Y², m)`: Laplacian energy for sharpness, and the luma
/// moments to normalize it by the subject's own contrast.
float4 subjectDetail(sampler image, sampler matte, destination dest) {
    float2 p = dest.coord();
    float center = luma(image.sample(image.transform(p)).rgb);
    float neighbours = luma(image.sample(image.transform(p + float2(1, 0))).rgb)
                     + luma(image.sample(image.transform(p - float2(1, 0))).rgb)
                     + luma(image.sample(image.transform(p + float2(0, 1))).rgb)
                     + luma(image.sample(image.transform(p - float2(0, 1))).rgb);
    float laplacian = neighbours - 4.0 * center;
    float m = clamp(matte.sample(matte.transform(p)).r, 0.0, 1.0);
    return float4(m * laplacian * laplacian, m * center, m * center * center, m);
}

/// `(m·highlight, m·shadow, m·specular, Y)`: clipped highlights (any channel
/// blown), crushed shadows, near-white specular hotspots, and unweighted luma
/// for the frame's overall brightness.
float4 subjectTone(sample_t image, sample_t matte) {
    float m = clamp(matte.r, 0.0, 1.0);
    float3 c = clamp(image.rgb, 0.0, 1.0);
    float brightest = max(c.r, max(c.g, c.b));
    float darkest = min(c.r, min(c.g, c.b));
    float highlight = step(0.98, brightest);
    float shadow = 1.0 - step(0.03, brightest);
    float specular = step(0.95, darkest);
    return float4(m * highlight, m * shadow, m * specular, luma(c));
}

}}
