//
// Copyright (c) Microsoft. All rights reserved.
// This code is licensed under the MIT License (MIT).
// THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF
// ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY
// IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR
// PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.
//
// Developed by Minigraph
//
// Author(s):	James Stanard

#include "Common.hlsli"
#define SINGLE_SAMPLE
#include "Lighting.hlsli"
#include "PBR.hlsli"
#include "ProceduralMaterial.hlsli"

cbuffer MatCBV : register(b1)
{
    uint MaterialID;
}

Texture2D<float3> texDiffuse		: register(t0);
Texture2D<float3> texORM			: register(t1);	// R=Occlusion, G=Roughness, B=Metallic
Texture2D<float4> texEmissive		: register(t2);
Texture2D<float3> texNormal			: register(t3);
//Texture2D<float4> texLightmap		: register(t4);
//Texture2D<float4> texReflection	: register(t5);
Texture2D<float> texSSAO			: register(t12);
Texture2D<float> texShadow			: register(t13);

struct VSOutput
{
	sample float4 position : SV_Position;
	sample float3 worldPos : WorldPos;
	sample float2 uv : TexCoord0;
	sample float3 viewDir : TexCoord1;
    sample float4 shadowCoord : TexCoord2;
	sample float3 normal : Normal;
	sample float3 tangent : Tangent;
	sample float3 bitangent : Bitangent;
};

struct MRT
{
	float3 Color : SV_Target0;
	float3 Normal : SV_Target1;
};

[RootSignature(Renderer_RootSig)]
MRT main(VSOutput vsOutput)
{
	MRT mrt;

	uint2 pixelPos = uint2(vsOutput.position.xy);
# define SAMPLE_TEX(texName) texName.Sample(defaultSampler, vsOutput.uv)

    float3 diffuseAlbedo;
    float  ao, roughness, metallic;

    if (MaterialID >= 100)
    {
        ProcMat pm    = GetProceduralMaterial(MaterialID);
        diffuseAlbedo = pm.baseColor;
        metallic      = pm.metallic;
        roughness     = pm.roughness;
        ao            = pm.ao;
    }
    else
    {
        diffuseAlbedo       = SAMPLE_TEX(texDiffuse);
        float3 ormSample    = SAMPLE_TEX(texORM);
        ao                  = ormSample.r;
        roughness           = ormSample.g;
        metallic            = ormSample.b;
    }

    float3 specularAlbedo = lerp(float3(0.04, 0.04, 0.04), diffuseAlbedo, metallic); // F0
    float3 diffuseContrib = diffuseAlbedo * (1.0 - metallic);

    float3 colorSum = 0;
    {
        float ssao = texSSAO[pixelPos];
        colorSum += AmbientPBR(diffuseContrib, specularAlbedo, ssao * ao, AmbientColor);
    }

    float3 normal;
    {
        normal = normalize(SAMPLE_TEX(texNormal) * 2.0 - 1.0);
        float3x3 tbn = float3x3(normalize(vsOutput.tangent), normalize(vsOutput.bitangent), normalize(vsOutput.normal));
        normal = normalize(mul(normal, tbn));
    }

    // vsOutput.viewDir = worldPos - ViewerPos (camera→surface), so negate for PBR V convention.
    float3 V = normalize(-vsOutput.viewDir);

    // Area light: 4 representative point samples with PCSS shadow (same geometry as Blinn-Phong path).
    float  visibility = GetAreaLightPCSS(vsOutput.shadowCoord, texShadow);
    const float2 sampleOffsets[4] = {
        float2(-0.18f, -0.12f), float2( 0.18f, -0.12f),
        float2(-0.18f,  0.12f), float2( 0.18f,  0.12f)
    };
    [unroll]
    for (uint i = 0; i < 4; ++i)
    {
        float3 samplePos  = PointLightPos.xyz + float3(sampleOffsets[i].x, 0.0f, sampleOffsets[i].y);
        float3 L          = samplePos - vsOutput.worldPos;
        float  invDist    = rsqrt(dot(L, L));
        L *= invDist;

        // Distance falloff: R^2/d^2 − d/R  (R^2 = 9, same as original ApplyPointLight)
        float distFalloff = 9.0f * invDist * invDist;
        distFalloff = max(0.0f, distFalloff - rsqrt(distFalloff));

        colorSum += distFalloff * EvaluatePBR(
            diffuseContrib, specularAlbedo, roughness,
            normal, V, L,
            PointLightColor.xyz * 0.25f,
            visibility);
    }
    colorSum += SAMPLE_TEX(texEmissive).rgb;

    // Debug views
    if (DebugView == 1)      colorSum = float3(ao, ao, ao);
    else if (DebugView == 2) colorSum = float3(roughness, roughness, roughness);
    else if (DebugView == 3) colorSum = float3(metallic, metallic, metallic);
    else if (DebugView == 4) colorSum = normal * 0.5 + 0.5;

	mrt.Normal = normal;
	mrt.Color = colorSum;
	return mrt;
}
