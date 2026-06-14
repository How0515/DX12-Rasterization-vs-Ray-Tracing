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

    float3 diffuseAlbedo = SAMPLE_TEX(texDiffuse);

    float3 ormSample    = SAMPLE_TEX(texORM);
    float  ao           = ormSample.r;
    float  roughness    = ormSample.g;
    float  metallic     = ormSample.b;
    float  specularMask = 1.0 - roughness;
    float  gloss        = lerp(2.0, 128.0, (1.0 - roughness) * (1.0 - roughness));
    float3 specularAlbedo = lerp(float3(0.04, 0.04, 0.04), diffuseAlbedo, metallic);
    float3 diffuseContrib = diffuseAlbedo * (1.0 - metallic);

    float3 colorSum = 0;
    {
        float ssao = texSSAO[pixelPos];
        colorSum += ApplyAmbientLight( diffuseAlbedo, ssao * ao, AmbientColor );
    }

    float3 normal;
    {
        normal = SAMPLE_TEX(texNormal) * 2.0 - 1.0;
        AntiAliasSpecular(normal, gloss);
        float3x3 tbn = float3x3(normalize(vsOutput.tangent), normalize(vsOutput.bitangent), normalize(vsOutput.normal));
        normal = normalize(mul(normal, tbn));
    }

    float3 viewDir = normalize(vsOutput.viewDir);
    // Directional light is disabled; the ceiling area-light approximation is used instead.

    colorSum += ApplyRectAreaLightApprox( diffuseContrib, specularAlbedo, specularMask, gloss, normal, viewDir,
        vsOutput.worldPos, PointLightPos.xyz, PointLightColor.xyz, vsOutput.shadowCoord, texShadow );
    colorSum += SAMPLE_TEX(texEmissive).rgb;

	// ShadeLights(colorSum, pixelPos,
	// 	diffuseAlbedo,
	// 	specularAlbedo,
	// 	specularMask,
	// 	gloss,
	// 	normal,
	// 	viewDir,
	// 	vsOutput.worldPos
	// 	);

    if (DebugView == 1)      colorSum = float3(ao, ao, ao);
    else if (DebugView == 2) colorSum = float3(roughness, roughness, roughness);
    else if (DebugView == 3) colorSum = float3(metallic, metallic, metallic);
    else if (DebugView == 4) colorSum = normal * 0.5 + 0.5;

	mrt.Normal = normal;
	mrt.Color = colorSum;
	return mrt;
}
