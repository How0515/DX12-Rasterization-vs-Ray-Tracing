// GGXPrefilterCS.hlsl
// Convolves a captured environment cubemap with GGX BRDF to produce a prefiltered env map.
// Mip 0 = direct copy (roughness 0); Mip 1..kEnvCubeMips-1 = GGX IS with increasing roughness.
// Dispatch: (ceil(mipSize/8), ceil(mipSize/8), 6) -- DTid.z = face index.

#ifndef PI
#define PI 3.14159265358979323846f
#endif

cbuffer PrefilterCB : register(b0)
{
    uint g_MipLevel;
    uint g_NumMips;
    uint g_NumSamples;
    uint g_OutputSize;
}

TextureCube<float4>      g_SrcCubemap : register(t0);
RWTexture2DArray<float4> g_Output     : register(u0);
SamplerState             g_Sampler    : register(s0);

float Halton(uint seed, uint base)
{
    float result = 0.0f;
    float f = 1.0f;
    uint  i = seed;
    [loop]
    while (i > 0u)
    {
        f      /= float(base);
        result += f * float(i % base);
        i      /= base;
    }
    return result;
}

float2 Halton2D(uint seed)
{
    return float2(Halton(seed, 2u), Halton(seed, 3u));
}

float3 ImportanceSampleGGX(float2 Xi, float roughness, float3 N)
{
    float alpha  = roughness * roughness;
    float alpha2 = alpha * alpha;
    float phi      = 2.0f * PI * Xi.x;
    float cosTheta = sqrt(saturate((1.0f - Xi.y) / max(1.0f + (alpha2 - 1.0f) * Xi.y, 1e-7f)));
    float sinTheta = sqrt(max(1.0f - cosTheta * cosTheta, 0.0f));
    float3 H_local = float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
    float3 up = abs(N.z) < 0.9999f ? float3(0.0f, 0.0f, 1.0f) : float3(1.0f, 0.0f, 0.0f);
    float3 T  = normalize(cross(up, N));
    float3 B  = cross(N, T);
    return normalize(T * H_local.x + B * H_local.y + N * H_local.z);
}

// Standard D3D12 cubemap face UV-to-direction mapping.
// uv in [0,1]; face 0..5 = +X,-X,+Y,-Y,+Z,-Z.
float3 FaceUVtoDir(uint face, float2 uv)
{
    float u = uv.x * 2.0f - 1.0f;
    float v = uv.y * 2.0f - 1.0f;
    switch (face)
    {
        case 0:  return normalize(float3(+1.0f,    -v,    -u));  // +X
        case 1:  return normalize(float3(-1.0f,    -v,    +u));  // -X
        case 2:  return normalize(float3(   +u, +1.0f,    +v));  // +Y
        case 3:  return normalize(float3(   +u, -1.0f,    -v));  // -Y
        case 4:  return normalize(float3(   +u,    -v, +1.0f));  // +Z
        default: return normalize(float3(   -u,    -v, -1.0f));  // -Z
    }
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint x    = DTid.x;
    uint y    = DTid.y;
    uint face = DTid.z;
    if (x >= g_OutputSize || y >= g_OutputSize)
        return;

    float2 uv = (float2(x, y) + 0.5f) / float(g_OutputSize);
    float3 N  = FaceUVtoDir(face, uv);

    float4 result;

    if (g_MipLevel == 0u)
    {
        // Mip 0: direct copy from source cubemap
        result = g_SrcCubemap.SampleLevel(g_Sampler, N, 0.0f);
    }
    else
    {
        // Mip 1+: GGX IS prefilter with split-sum V=N assumption
        float roughness = float(g_MipLevel) / float(g_NumMips - 1u);
        float3 accum  = float3(0.0f, 0.0f, 0.0f);
        float  totalW = 0.0f;
        for (uint i = 0u; i < g_NumSamples; ++i)
        {
            float2 Xi   = Halton2D(i);
            float3 H    = ImportanceSampleGGX(Xi, roughness, N);
            float3 L    = reflect(-N, H);
            float  NdotL = saturate(dot(N, L));
            if (NdotL > 0.0f)
            {
                accum  += g_SrcCubemap.SampleLevel(g_Sampler, L, 0.0f).rgb * NdotL;
                totalW += NdotL;
            }
        }
        result = float4(accum / max(totalW, 1e-5f), 1.0f);
    }

    g_Output[uint3(x, y, face)] = result;
}
