//*********************************************************
//
// Copyright (c) Microsoft. All rights reserved.
// This code is licensed under the MIT License (MIT).
// THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF
// ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY
// IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR
// PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.
//
//*********************************************************
//
// Screen-space reflection via depth-buffer ray march.
// Used by RTM_SSR mode (key 3) as a raster-side comparison against
// recursive RT reflection (key 7, RTM_REFLECTIONS).
//
// Observable SSR artifacts vs recursive RT:
//   1. Reflections disappear when reflected geometry leaves screen bounds
//   2. Self-intersection artifacts near grazing angles (step-size aliasing)
//   3. Edge fade masks the hard screen-boundary cutoff
//

#define HLSL
#include "ModelViewerRaytracing.h"

Texture2D<float>  depth   : register(t12);
Texture2D<float4> normals : register(t13);  // xyz = world normal, w = metallic

static const uint  kSSRSteps     = 64;
static const float kSSRStepSize  = 0.04f;  // world-space step size (scene ~2 m wide)
static const float kSSRThickness = 0.08f;  // NDC.z tolerance for depth hit
static const uint  kSSRFadeStart = 56;     // fade over steps 56-64 near step limit

[shader("raygeneration")]
void RayGen()
{
    uint2  pixelPos = DispatchRaysIndex().xy;
    float2 res      = g_dynamic.resolution;
    if (pixelPos.x >= (uint)res.x || pixelPos.y >= (uint)res.y)
        return;

    // Only metallic surfaces generate SSR (normalData.w = metallic, Commit 4)
    float4 normalData = normals[pixelPos];
    float  metallic   = normalData.w;
    if (metallic < 0.5f)
        return;

    float sceneDepth = depth[pixelPos];
    if (sceneDepth >= 1.0f)
        return;  // sky / background

    // Reconstruct world position from NDC depth
    float2 uv      = (float2(pixelPos) + 0.5f) / res;
    float2 ndcXY   = uv * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f);
    float4 worldH  = mul(g_dynamic.cameraToWorld, float4(ndcXY, sceneDepth, 1.0f));
    float3 worldPos = worldH.xyz / worldH.w;

    float3 normal  = normalize(normalData.xyz);
    float3 viewDir = normalize(worldPos - g_dynamic.worldCameraPosition);
    float3 reflDir = reflect(viewDir, normal);

    // Fresnel–Schlick weight (silver F0 approximation for metallic surfaces)
    float3 F0      = float3(0.85f, 0.85f, 0.85f);
    float  cosTheta = saturate(-dot(viewDir, normal));
    float3 F       = F0 + (1.0f - F0) * pow(1.0f - cosTheta, 5.0f);

    // World-space ray march, project each step to screen UV via worldToClip
    float3 rayPos  = worldPos + normal * 0.02f;  // surface bias to avoid self-hit
    float3 rayStep = reflDir * kSSRStepSize;

    float3 hitColor = float3(0, 0, 0);
    float  hitFade  = 0.0f;

    [loop]
    for (uint i = 0; i < kSSRSteps; ++i)
    {
        rayPos += rayStep;

        float4 clip = mul(g_dynamic.worldToClip, float4(rayPos, 1.0f));
        if (clip.w <= 0.0f)
            break;

        float3 ndc = clip.xyz / clip.w;

        // Artifact 1: reflected ray exits screen → reflection vanishes
        if (any(abs(ndc.xy) > 1.0f))
            break;

        float2 sampleUV = ndc.xy * float2(0.5f, -0.5f) + 0.5f;
        uint2  samplePx = uint2(sampleUV * res);

        float sampleDepth = depth[samplePx];

        // Depth intersection: ray NDC.z just crossed behind the surface
        if (ndc.z > sampleDepth && ndc.z < sampleDepth + kSSRThickness)
        {
            // Fade at screen edges (Artifact 1 softening) and near step limit
            float2 edgeDist = 1.0f - abs(ndc.xy);
            float  edgeFade = saturate(min(edgeDist.x, edgeDist.y) * 8.0f);
            float  stepFade = (i >= kSSRFadeStart)
                ? 1.0f - float(i - kSSRFadeStart) / float(kSSRSteps - kSSRFadeStart)
                : 1.0f;

            hitColor = g_screenOutput[samplePx].rgb;
            hitFade  = edgeFade * stepFade;
            break;
        }
    }

    if (hitFade > 0.01f)
    {
        float3 base = g_screenOutput[pixelPos].rgb;
        g_screenOutput[pixelPos] = float4(base + F * hitFade * hitColor, 1.0f);
    }
}
