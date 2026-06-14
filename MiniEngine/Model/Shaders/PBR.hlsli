// PBR.hlsli — Cook-Torrance BRDF building blocks (shared by Raster and RT paths)
//
// Usage:
//   diffuseColor = baseColor * (1 - metallic)
//   F0           = lerp(float3(0.04, 0.04, 0.04), baseColor, metallic)
//   roughness    = linear roughness [0,1]  (alpha = roughness^2 is computed internally)

#ifndef PBR_HLSLI
#define PBR_HLSLI

#ifndef PI
#define PI 3.14159265358979323846
#endif

// ---------------------------------------------------------------------------
// GGX Trowbridge-Reitz Normal Distribution Function
// ---------------------------------------------------------------------------
float D_GGX(float NdotH, float alpha)
{
    float a2 = alpha * alpha;
    float d  = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (PI * d * d);
}

// ---------------------------------------------------------------------------
// Smith's geometry shadowing-masking with Schlick-GGX approximation
// ---------------------------------------------------------------------------
float G_Smith(float NdotV, float NdotL, float roughness)
{
    float r = roughness + 1.0;
    float k = (r * r) * 0.125;  // k = (roughness+1)^2 / 8  (direct-light remapping)
    float gV = NdotV / (NdotV * (1.0 - k) + k);
    float gL = NdotL / (NdotL * (1.0 - k) + k);
    return gV * gL;
}

// ---------------------------------------------------------------------------
// Fresnel-Schlick
// ---------------------------------------------------------------------------
float3 F_Schlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

// ---------------------------------------------------------------------------
// Cook-Torrance BRDF for a single punctual light.
//
//  diffuseColor = baseColor * (1 - metallic)   — Lambertian albedo
//  F0           = lerp(0.04, baseColor, metallic) — specular reflectance at normal incidence
//  roughness    = linear roughness [0,1]
//  N, V, L      = normalized world-space: surface normal, view dir, light dir
//  lightColor   = incident radiance of the light source
//  shadow       = [0,1] shadow factor
//
//  Returns outgoing radiance Lo.
// ---------------------------------------------------------------------------
float3 EvaluatePBR(
    float3 diffuseColor,
    float3 F0,
    float  roughness,
    float3 N,
    float3 V,
    float3 L,
    float3 lightColor,
    float  shadow)
{
    // Clamp roughness: GGX D denominator → 0 as roughness → 0, causing specular explosion.
    float  roughnessClamped = clamp(roughness, 0.04, 1.0);

    float3 H    = normalize(V + L);
    float NdotL = saturate(dot(N, L));
    float NdotV = max(dot(N, V), 1e-5);
    float NdotH = saturate(dot(N, H));
    float VdotH = saturate(dot(V, H));

    float  alpha   = roughnessClamped * roughnessClamped;
    float  D       = D_GGX(NdotH, alpha);
    float  G       = G_Smith(NdotV, NdotL, roughnessClamped);
    float3 F       = F_Schlick(VdotH, F0);

    // Specular: Cook-Torrance
    float3 specular = (D * G * F) / max(4.0 * NdotV * NdotL, 1e-3);

    // Diffuse: Lambertian (no /PI — light intensities are tuned for unnormalized Blinn-Phong,
    // so dividing by PI would make the scene ~3x darker without retuning all light values).
    float3 diffuse = (1.0 - F) * diffuseColor;

    return (diffuse + specular) * NdotL * lightColor * shadow;
}

// ---------------------------------------------------------------------------
// Ambient (IBL placeholder — single-color ambient with AO).
//
//  diffuse ambient : (1 - F0) * diffuseColor  — dielectric contribution
//  specular ambient: F0                        — metal/specular contribution
//
// Without specular ambient, metallic surfaces are completely black in
// unlit areas because diffuseColor = baseColor*(1-metallic) = 0.
// ---------------------------------------------------------------------------
float3 AmbientPBR(float3 diffuseColor, float3 F0, float ao, float3 ambientColor)
{
    // Guard: ao=0 (from missing/black ORM fallback texture) kills all ambient.
    float  aoSafe          = max(ao, 0.01);
    float3 ambientDiffuse  = (1.0 - F0) * diffuseColor;
    float3 ambientSpecular = F0;
    return (ambientDiffuse + ambientSpecular) * aoSafe * ambientColor;
}

#endif // PBR_HLSLI
