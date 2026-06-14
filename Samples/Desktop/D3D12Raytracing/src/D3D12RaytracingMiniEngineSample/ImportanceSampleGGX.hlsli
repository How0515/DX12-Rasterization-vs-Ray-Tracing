// ImportanceSampleGGX.hlsli
// GGX microfacet importance sampling + Halton low-discrepancy sequence.
//
// Usage (in a hit shader):
//   uint   seed    = MakeHaltonSeed(DispatchRaysIndex().xy, g_dynamic.frameIndex);
//   float2 Xi      = Halton2D(seed);
//   float3 H       = ImportanceSampleGGX(Xi, roughness, normal);
//   float3 reflDir = reflect(incidentDir, H);
//   if (dot(reflDir, normal) > 0.0f) { /* trace reflection ray */ }
//
// Roughness convention: linear roughness [0,1]; alpha = roughness^2 internally,
// matching D_GGX in PBR.hlsli.

#ifndef IMPORTANCE_SAMPLE_GGX_HLSLI
#define IMPORTANCE_SAMPLE_GGX_HLSLI

#ifndef PI
#define PI 3.14159265358979323846f
#endif

// ---------------------------------------------------------------------------
// Halton low-discrepancy sequence in base `base`.
// Returns a float in [0, 1) for the given index (seed).
// ---------------------------------------------------------------------------
float Halton(uint seed, uint base)
{
    float result = 0.0f;
    float f      = 1.0f;
    uint  i      = seed;
    [loop]
    while (i > 0u)
    {
        f      /= float(base);
        result += f * float(i % base);
        i      /= base;
    }
    return result;
}

// 2D Halton sample using bases 2 (x) and 3 (y) — standard low-discrepancy pair.
float2 Halton2D(uint seed)
{
    return float2(Halton(seed, 2u), Halton(seed, 3u));
}

// Per-pixel seed: mixes pixel position with a monotonically increasing frameIndex.
// Different pixels get different seeds; successive frames get successive seeds
// so the Halton sequence advances temporally (TAA accumulates the samples).
uint MakeHaltonSeed(uint2 pixelPos, uint frameIndex)
{
    uint h = pixelPos.x * 1973u ^ pixelPos.y * 9277u ^ frameIndex * 26699u;
    h ^= h >> 16u;
    h *= 0x45d9f3bu;
    h ^= h >> 16u;
    return h;
}

// ---------------------------------------------------------------------------
// GGX (Trowbridge-Reitz) importance sampling.
//
//   Xi        : 2D uniform sample in [0,1)^2  (e.g. from Halton2D)
//   roughness : linear roughness [0,1]
//   N         : macro-surface normal in world space
//
// Returns a microfacet normal H sampled proportional to D_GGX(NdotH, alpha).
// The reflection direction is:  reflDir = reflect(incidentDir, H)
// Discard if dot(reflDir, N) <= 0.
//
// Derivation: inversion method on the GGX NDF marginal CDF gives
//   cosTheta = sqrt( (1 - Xi.y) / (1 + (alpha^2 - 1) * Xi.y) )
// ---------------------------------------------------------------------------
float3 ImportanceSampleGGX(float2 Xi, float roughness, float3 N)
{
    float alpha  = roughness * roughness;
    float alpha2 = alpha * alpha;

    // Sample spherical coordinates of H in tangent space
    float phi      = 2.0f * PI * Xi.x;
    float cosTheta = sqrt(saturate((1.0f - Xi.y) / max(1.0f + (alpha2 - 1.0f) * Xi.y, 1e-7f)));
    float sinTheta = sqrt(max(1.0f - cosTheta * cosTheta, 0.0f));

    // H in local tangent space (+Z = N)
    float3 H_local = float3(sinTheta * cos(phi),
                            sinTheta * sin(phi),
                            cosTheta);

    // Build an orthonormal TBN frame around N
    float3 up = abs(N.z) < 0.9999f ? float3(0.0f, 0.0f, 1.0f) : float3(1.0f, 0.0f, 0.0f);
    float3 T  = normalize(cross(up, N));
    float3 B  = cross(N, T);

    // Transform H from tangent space to world space
    return normalize(T * H_local.x + B * H_local.y + N * H_local.z);
}

// Convenience: perfect mirror direction when roughness is below this threshold.
// Avoids unnecessary Halton sampling for near-mirror surfaces.
static const float kGlossyRoughnessThreshold = 0.02f;

#endif // IMPORTANCE_SAMPLE_GGX_HLSLI
