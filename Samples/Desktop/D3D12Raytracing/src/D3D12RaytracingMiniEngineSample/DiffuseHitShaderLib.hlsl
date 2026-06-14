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
// Author(s):    James Stanard, Christopher Wallis
//

#define HLSL
#include "ModelViewerRaytracing.h"
#include "RayTracingHlslCompat.h"
#include "PBR.hlsli"
#include "ProceduralMaterial.hlsli"

cbuffer Material : register(b3)
{
    uint MaterialID;
}

StructuredBuffer<RayTraceMeshInfo> g_meshInfo : register(t1);
ByteAddressBuffer g_indices : register(t2);
ByteAddressBuffer g_attributes : register(t3);
Texture2D<float> texShadow : register(t4);
Texture2D<float> texSSAO : register(t5);
SamplerState      g_s0 : register(s0);
SamplerComparisonState shadowSampler : register(s1);

Texture2D<float4> g_localTexture : register(t6);
Texture2D<float4> g_localNormal  : register(t7);
Texture2D<float4> g_localORM     : register(t8);  // R=Occlusion, G=Roughness, B=Metallic

Texture2D<float4>   normals  : register(t13);

static const float kShadowRayEpsilon = 1e-5f;
static const uint kAreaLightGridDim = 8;
static const uint kAreaLightSampleCount = kAreaLightGridDim * kAreaLightGridDim;

uint HashAreaLightPixel(uint2 pixelPosition)
{
    uint hash = pixelPosition.x * 0x8da6b343u ^ pixelPosition.y * 0xd8163841u;
    hash ^= hash >> 16;
    hash *= 0x7feb352du;
    hash ^= hash >> 15;
    hash *= 0x846ca68bu;
    return hash ^ (hash >> 16);
}

float2 GetAreaLightGridRotation(uint2 pixelPosition)
{
    float angle = (HashAreaLightPixel(pixelPosition) & 0x00ffffffu) *
        (6.28318530718f / 16777216.0f);
    float sine;
    float cosine;
    sincos(angle, sine, cosine);
    return float2(cosine, sine);
}

float2 GetAreaLightSampleOffset(uint sampleIndex, float2 rotation)
{
    float2 gridPosition = float2(sampleIndex % kAreaLightGridDim, sampleIndex / kAreaLightGridDim);
    float2 centeredGridPosition = (gridPosition + 0.5f) / kAreaLightGridDim - 0.5f;
    float2 rotatedPosition = float2(
        rotation.x * centeredGridPosition.x - rotation.y * centeredGridPosition.y,
        rotation.y * centeredGridPosition.x + rotation.x * centeredGridPosition.y);

    // Keep the rotated grid inside the rectangular emitter.
    float2 wrappedPosition = frac(rotatedPosition + 0.5f) - 0.5f;
    return wrappedPosition * float2(0.36f, 0.24f);
}

uint3 Load3x16BitIndices(
    uint offsetBytes)
{
    const uint dwordAlignedOffset = offsetBytes & ~3;

    const uint2 four16BitIndices = g_indices.Load2(dwordAlignedOffset);

    uint3 indices;

    if (dwordAlignedOffset == offsetBytes)
    {
        indices.x = four16BitIndices.x & 0xffff;
        indices.y = (four16BitIndices.x >> 16) & 0xffff;
        indices.z = four16BitIndices.y & 0xffff;
    }
    else
    {
        indices.x = (four16BitIndices.x >> 16) & 0xffff;
        indices.y = four16BitIndices.y & 0xffff;
        indices.z = (four16BitIndices.y >> 16) & 0xffff;
    }

    return indices;
}

float GetShadow(float3 ShadowCoord)
{
    const float Dilation = 2.0;
    float d1 = Dilation * ShadowTexelSize.x * 0.125;
    float d2 = Dilation * ShadowTexelSize.x * 0.875;
    float d3 = Dilation * ShadowTexelSize.x * 0.625;
    float d4 = Dilation * ShadowTexelSize.x * 0.375;
    float result = (
        2.0 * texShadow.SampleCmpLevelZero(shadowSampler, ShadowCoord.xy, ShadowCoord.z) +
        texShadow.SampleCmpLevelZero(shadowSampler, ShadowCoord.xy + float2(-d2, d1), ShadowCoord.z) +
        texShadow.SampleCmpLevelZero(shadowSampler, ShadowCoord.xy + float2(-d1, -d2), ShadowCoord.z) +
        texShadow.SampleCmpLevelZero(shadowSampler, ShadowCoord.xy + float2(d2, -d1), ShadowCoord.z) +
        texShadow.SampleCmpLevelZero(shadowSampler, ShadowCoord.xy + float2(d1, d2), ShadowCoord.z) +
        texShadow.SampleCmpLevelZero(shadowSampler, ShadowCoord.xy + float2(-d4, d3), ShadowCoord.z) +
        texShadow.SampleCmpLevelZero(shadowSampler, ShadowCoord.xy + float2(-d3, -d4), ShadowCoord.z) +
        texShadow.SampleCmpLevelZero(shadowSampler, ShadowCoord.xy + float2(d4, -d3), ShadowCoord.z) +
        texShadow.SampleCmpLevelZero(shadowSampler, ShadowCoord.xy + float2(d3, d4), ShadowCoord.z)
        ) / 10.0;
    return result;
    //return result * result;
}

float2 GetUVAttribute(uint byteOffset)
{
    return asfloat(g_attributes.Load2(byteOffset));
}

void AntiAliasSpecular(inout float3 texNormal, inout float gloss)
{
    float normalLenSq = dot(texNormal, texNormal);
    float invNormalLen = rsqrt(normalLenSq);
    texNormal *= invNormalLen;
    gloss = lerp(1, gloss, rcp(invNormalLen));
}

// Apply fresnel to modulate the specular albedo
void FSchlick(inout float3 specular, inout float3 diffuse, float3 lightDir, float3 halfVec)
{
    float fresnel = pow(1.0 - saturate(dot(lightDir, halfVec)), 5.0);
    specular = lerp(specular, 1, fresnel);
    diffuse = lerp(diffuse, 0, fresnel);
}

float3 ApplyLightCommon(
    float3    diffuseColor,    // Diffuse albedo
    float3    specularColor,    // Specular albedo
    float    specularMask,    // Where is it shiny or dingy?
    float    gloss,            // Specular power
    float3    normal,            // World-space normal
    float3    viewDir,        // World-space vector from eye to point
    float3    lightDir,        // World-space vector from point to light
    float3    lightColor        // Radiance of directional light
)
{
    float3 halfVec = normalize(lightDir - viewDir);
    float nDotH = saturate(dot(halfVec, normal));

    FSchlick(specularColor, diffuseColor, lightDir, halfVec);

    float specularFactor = specularMask * pow(nDotH, gloss) * (gloss + 2) / 8;

    float nDotL = saturate(dot(normal, lightDir));

    return nDotL * lightColor * (diffuseColor + specularFactor * specularColor);
}

float TraceAreaLightSampleVisibility(float3 worldPos, float3 normal, float3 samplePos, uint callerDepth)
{
    if (!UseShadowRays)
        return 1.0f;
    // RTPSO MaxTraceRecursionDepth=3; a shadow ray at callerDepth>=2 would reach depth 4 and crash.
    if (callerDepth >= 2)
        return 1.0f;

    float3 toLight = samplePos - worldPos;
    float distanceToLight = length(toLight);
    if (distanceToLight <= 2.0f * kShadowRayEpsilon)
        return 1.0f;

    RayDesc shadowRay;
    shadowRay.Origin = worldPos + normal * kShadowRayEpsilon;
    shadowRay.TMin = kShadowRayEpsilon;
    shadowRay.Direction = toLight / distanceToLight;
    shadowRay.TMax = distanceToLight - kShadowRayEpsilon;

    RayPayload shadowPayload;
    shadowPayload.SkipShading    = true;
    shadowPayload.RayHitT        = FLT_MAX;
    shadowPayload.Color          = float3(0, 0, 0);
    shadowPayload.RecursionDepth = 0;
    TraceRay(
        g_accel,
        RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH,
        1,
        0,
        1,
        0,
        shadowRay,
        shadowPayload);

    return shadowPayload.RayHitT < FLT_MAX ? 0.0f : 1.0f;
}

float3 ApplyRectAreaLightApprox(
    float3 diffuseColor,
    float3 specularColor,
    float specularMask,
    float gloss,
    float3 normal,
    float3 viewDir,
    float3 worldPos)
{
    float3 result = 0.0f;
    float2 gridRotation = GetAreaLightGridRotation(DispatchRaysIndex().xy);
    [loop]
    for (uint i = 0; i < kAreaLightSampleCount; ++i)
    {
        float2 sampleOffset = GetAreaLightSampleOffset(i, gridRotation);
        float3 samplePos = PointLightPos.xyz + float3(sampleOffset.x, 0.0f, sampleOffset.y);
        float visibility = TraceAreaLightSampleVisibility(worldPos, normal, samplePos, 0);
        float3 toLight = samplePos - worldPos;
        float distSq = dot(toLight, toLight);
        float invDist = rsqrt(distSq);
        float distFalloff = 9.0f * (invDist * invDist);
        distFalloff = max(0, distFalloff - rsqrt(distFalloff));
        result += visibility * distFalloff * ApplyLightCommon(
            diffuseColor, specularColor, specularMask, gloss,
            normal, viewDir, toLight * invDist, PointLightColor.xyz / kAreaLightSampleCount);
    }
    return result;
}

float3 RayPlaneIntersection(float3 planeOrigin, float3 planeNormal, float3 rayOrigin, float3 rayDirection)
{
    float t = dot(-planeNormal, rayOrigin - planeOrigin) / dot(planeNormal, rayDirection);
    return rayOrigin + rayDirection * t;
}

/*
    REF: https://gamedev.stackexchange.com/questions/23743/whats-the-most-efficient-way-to-find-barycentric-coordinates
    From "Real-Time Collision Detection" by Christer Ericson
*/
float3 BarycentricCoordinates(float3 pt, float3 v0, float3 v1, float3 v2)
{
    float3 e0 = v1 - v0;
    float3 e1 = v2 - v0;
    float3 e2 = pt - v0;
    float d00 = dot(e0, e0);
    float d01 = dot(e0, e1);
    float d11 = dot(e1, e1);
    float d20 = dot(e2, e0);
    float d21 = dot(e2, e1);
    float denom = 1.0 / (d00 * d11 - d01 * d01);
    float v = (d11 * d20 - d01 * d21) * denom;
    float w = (d00 * d21 - d01 * d20) * denom;
    float u = 1.0 - v - w;
    return float3(u, v, w);
}

// World-space outward normals for procedural surfaces.
// Box (matID 104): each face = 2 triangles, ordered top/front/back/left/right/bottom.
float3 GetProceduralNormal(uint matID, uint primIdx)
{
    if (matID == 100) return float3( 0,  1,  0);  // floor
    if (matID == 101) return float3( 1,  0,  0);  // red wall
    if (matID == 102) return float3(-1,  0,  0);  // green wall
    if (matID == 103) return float3( 0,  0, -1);  // back wall
    if (matID == 105) return float3( 0, -1,  0);  // ceiling
    if (matID == 106) return float3( 0, -1,  0);  // area light panel
    if (matID == 104)  // Box A: Y-rotated 25° (sin=0.4226, cos=0.9063)
    {
        if (primIdx <  2) return float3( 0,       1,      0);       // top
        if (primIdx <  4) return float3( 0.4226f, 0, -0.9063f);     // front (Zmin)
        if (primIdx <  6) return float3(-0.4226f, 0,  0.9063f);     // back  (Zmax)
        if (primIdx <  8) return float3(-0.9063f, 0, -0.4226f);     // left  (Xmin)
        if (primIdx < 10) return float3( 0.9063f, 0,  0.4226f);     // right (Xmax)
                          return float3( 0,      -1,      0);       // bottom
    }
    if (matID == 108)  // Box B: axis-aligned (mirrors Box A across room center)
    {
        if (primIdx <  2) return float3( 0,  1,  0);  // top
        if (primIdx <  4) return float3( 0,  0, -1);  // front
        if (primIdx <  6) return float3( 0,  0,  1);  // back
        if (primIdx <  8) return float3(-1,  0,  0);  // left  (faces Box A)
        if (primIdx < 10) return float3( 1,  0,  0);  // right
                          return float3( 0, -1,  0);  // bottom
    }
    return float3(0, 1, 0);
}

[shader("closesthit")]
void Hit(inout RayPayload payload, in BuiltInTriangleIntersectionAttributes attr)
{
    payload.RayHitT = RayTCurrent();
    if (payload.SkipShading)
    {
        return;
    }

    uint materialID = MaterialID;
    uint triangleID = PrimitiveIndex();

    // Procedural surfaces (floor/walls/box/mirror): g_meshInfo is sized for the helmet only.
    // Bypass mesh attribute loading and use hardcoded geometry data instead.
    if (materialID >= 100)
    {
        float3 worldPos = WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
        float3 normal   = GetProceduralNormal(materialID, PrimitiveIndex());
        float3 V        = normalize(-WorldRayDirection());

        if (materialID == 106)
        {
            ProcMat lm = GetProceduralMaterial(106);
            payload.Color = lm.baseColor;
            return;
        }

        ProcMat pm         = GetProceduralMaterial(materialID);
        float3 diffuseContrib = pm.baseColor * (1.0 - pm.metallic);
        float3 specularAlbedo = lerp(float3(0.04, 0.04, 0.04), pm.baseColor, pm.metallic);
        float  roughness      = pm.roughness;

        float3 outputColor = AmbientPBR(
            diffuseContrib, specularAlbedo,
            texSSAO[DispatchRaysIndex().xy] * pm.ao,
            AmbientColor);

        float2 gridRotation = GetAreaLightGridRotation(DispatchRaysIndex().xy);
        [loop]
        for (uint li = 0; li < kAreaLightSampleCount; ++li)
        {
            float2 sampleOffset = GetAreaLightSampleOffset(li, gridRotation);
            float3 samplePos    = PointLightPos.xyz + float3(sampleOffset.x, 0.0f, sampleOffset.y);
            float  visibility   = TraceAreaLightSampleVisibility(worldPos, normal, samplePos, payload.RecursionDepth);
            float3 L            = samplePos - worldPos;
            float  invDist      = rsqrt(dot(L, L));
            L *= invDist;

            float distFalloff = 9.0f * invDist * invDist;
            distFalloff = max(0.0f, distFalloff - rsqrt(distFalloff));

            outputColor += distFalloff * EvaluatePBR(
                diffuseContrib, specularAlbedo, roughness,
                normal, V, L,
                PointLightColor.xyz / kAreaLightSampleCount,
                visibility);
        }

        // Recursive mirror reflection (Stage 9): perfect specular bounce via reflect().
        // Stage 10 upgrade: replace reflect() with GGX-sampled direction for glossy.
        if (DebugView == 0 && MaxRecursionDepth > 0 && payload.RecursionDepth < MaxRecursionDepth && pm.metallic > 0.5f)
        {
            float3 reflDir = reflect(WorldRayDirection(), normal);

            RayPayload reflPayload;
            reflPayload.SkipShading    = false;
            reflPayload.RayHitT        = FLT_MAX;
            reflPayload.Color          = float3(0, 0, 0);
            reflPayload.RecursionDepth = payload.RecursionDepth + 1;

            RayDesc reflRay;
            reflRay.Origin    = worldPos + normal * 1e-4f;
            reflRay.TMin      = 0.0f;
            reflRay.Direction = reflDir;
            reflRay.TMax      = FLT_MAX;

            TraceRay(g_accel, RAY_FLAG_CULL_BACK_FACING_TRIANGLES, ~0, 0, 1, 0, reflRay, reflPayload);

            float3 F = F_Schlick(saturate(dot(normal, V)), specularAlbedo);
            outputColor += F * reflPayload.Color;
        }

        if (DebugView == 1)      outputColor = float3(pm.ao, pm.ao, pm.ao);
        else if (DebugView == 2) outputColor = float3(roughness, roughness, roughness);
        else if (DebugView == 3) outputColor = float3(pm.metallic, pm.metallic, pm.metallic);
        else if (DebugView == 4) outputColor = normal * 0.5 + 0.5;

        payload.Color = outputColor;
        return;
    }

    RayTraceMeshInfo info = g_meshInfo[materialID];

    const uint3 ii = Load3x16BitIndices(info.m_indexOffsetBytes + PrimitiveIndex() * 3 * 2);
    const float2 uv0 = GetUVAttribute(info.m_uvAttributeOffsetBytes + ii.x * info.m_attributeStrideBytes);
    const float2 uv1 = GetUVAttribute(info.m_uvAttributeOffsetBytes + ii.y * info.m_attributeStrideBytes);
    const float2 uv2 = GetUVAttribute(info.m_uvAttributeOffsetBytes + ii.z * info.m_attributeStrideBytes);

    float3 bary = float3(1.0 - attr.barycentrics.x - attr.barycentrics.y, attr.barycentrics.x, attr.barycentrics.y);
    float2 uv = bary.x * uv0 + bary.y * uv1 + bary.z * uv2;

    const float3 normal0 = asfloat(g_attributes.Load3(info.m_normalAttributeOffsetBytes + ii.x * info.m_attributeStrideBytes));
    const float3 normal1 = asfloat(g_attributes.Load3(info.m_normalAttributeOffsetBytes + ii.y * info.m_attributeStrideBytes));
    const float3 normal2 = asfloat(g_attributes.Load3(info.m_normalAttributeOffsetBytes + ii.z * info.m_attributeStrideBytes));
    float3 vsNormal = normalize(normal0 * bary.x + normal1 * bary.y + normal2 * bary.z);
    
    const float3 tangent0 = asfloat(g_attributes.Load3(info.m_tangentAttributeOffsetBytes + ii.x * info.m_attributeStrideBytes));
    const float3 tangent1 = asfloat(g_attributes.Load3(info.m_tangentAttributeOffsetBytes + ii.y * info.m_attributeStrideBytes));
    const float3 tangent2 = asfloat(g_attributes.Load3(info.m_tangentAttributeOffsetBytes + ii.z * info.m_attributeStrideBytes));
    float3 vsTangent = normalize(tangent0 * bary.x + tangent1 * bary.y + tangent2 * bary.z);

    // Reintroduced the bitangent because we aren't storing the handedness of the tangent frame anywhere.  Assuming the space
    // is right-handed causes normal maps to invert for some surfaces.  The Sponza mesh has all three axes of the tangent frame.
    //float3 vsBitangent = normalize(cross(vsNormal, vsTangent)) * (isRightHanded ? 1.0 : -1.0);
    const float3 bitangent0 = asfloat(g_attributes.Load3(info.m_bitangentAttributeOffsetBytes + ii.x * info.m_attributeStrideBytes));
    const float3 bitangent1 = asfloat(g_attributes.Load3(info.m_bitangentAttributeOffsetBytes + ii.y * info.m_attributeStrideBytes));
    const float3 bitangent2 = asfloat(g_attributes.Load3(info.m_bitangentAttributeOffsetBytes + ii.z * info.m_attributeStrideBytes));
    float3 vsBitangent = normalize(bitangent0 * bary.x + bitangent1 * bary.y + bitangent2 * bary.z);

    // TODO: Should just store uv partial derivatives in here rather than loading position and caculating it per pixel
    const float3 p0 = asfloat(g_attributes.Load3(info.m_positionAttributeOffsetBytes + ii.x * info.m_attributeStrideBytes));
    const float3 p1 = asfloat(g_attributes.Load3(info.m_positionAttributeOffsetBytes + ii.y * info.m_attributeStrideBytes));
    const float3 p2 = asfloat(g_attributes.Load3(info.m_positionAttributeOffsetBytes + ii.z * info.m_attributeStrideBytes));

    float3 worldPosition = WorldRayOrigin() + WorldRayDirection() * RayTCurrent();

    // Transform object-space positions to world space using the BLAS instance transform.
    // Required when the instance has a non-identity transform (e.g. Y-axis rotation).
    // Without this, worldPosition (world space) and p0/p1/p2 (object space) are in
    // different spaces, causing incorrect UV gradients → wrong mip selection.
    float3x4 objToWorld = ObjectToWorld3x4();
    float3 wp0 = mul(objToWorld, float4(p0, 1.0));
    float3 wp1 = mul(objToWorld, float4(p1, 1.0));
    float3 wp2 = mul(objToWorld, float4(p2, 1.0));

    // Also transform normals/tangents to world space for correct lighting.
    vsNormal    = normalize(mul(objToWorld, float4(vsNormal,    0.0)));
    vsTangent   = normalize(mul(objToWorld, float4(vsTangent,   0.0)));
    vsBitangent = normalize(mul(objToWorld, float4(vsBitangent, 0.0)));

    //---------------------------------------------------------------------------------------------
    // Compute partial derivatives of UV coordinates:
    //
    //  1) Construct a plane from the hit triangle
    //  2) Intersect two helper rays with the plane:  one to the right and one down
    //  3) Compute barycentric coordinates of the two hit points
    //  4) Reconstruct the UV coordinates at the hit points
    //  5) Take the difference in UV coordinates as the partial derivatives X and Y

    // Normal for plane — use world-space positions so the plane is consistent with worldPosition
    float3 triangleNormal = normalize(cross(wp2 - wp0, wp1 - wp0));

    // Helper rays
    uint2 threadID = DispatchRaysIndex().xy;
    float3 ddxOrigin, ddxDir, ddyOrigin, ddyDir;
    GenerateCameraRay(uint2(threadID.x + 1, threadID.y), ddxOrigin, ddxDir);
    GenerateCameraRay(uint2(threadID.x, threadID.y + 1), ddyOrigin, ddyDir);

    // Intersect helper rays
    float3 xOffsetPoint = RayPlaneIntersection(worldPosition, triangleNormal, ddxOrigin, ddxDir);
    float3 yOffsetPoint = RayPlaneIntersection(worldPosition, triangleNormal, ddyOrigin, ddyDir);

    // Compute barycentrics — use world-space triangle positions
    float3 baryX = BarycentricCoordinates(xOffsetPoint, wp0, wp1, wp2);
    float3 baryY = BarycentricCoordinates(yOffsetPoint, wp0, wp1, wp2);

    // Compute UVs and take the difference
    float3x2 uvMat = float3x2(uv0, uv1, uv2);
    float2 ddxUV = mul(baryX, uvMat) - uv;
    float2 ddyUV = mul(baryY, uvMat) - uv;

    //---------------------------------------------------------------------------------------------

    const float3 diffuseColor = g_localTexture.SampleGrad(g_s0, uv, ddxUV, ddyUV).rgb;

    float3 ormSample     = g_localORM.SampleGrad(g_s0, uv, ddxUV, ddyUV).rgb;
    float  ao            = ormSample.r;
    float  roughness     = ormSample.g;
    float  metallic      = ormSample.b;
    float3 specularAlbedo = lerp(float3(0.04, 0.04, 0.04), diffuseColor, metallic); // F0
    float3 diffuseContrib = diffuseColor * (1.0 - metallic);

    float3 normal;
    {
        normal = normalize(g_localNormal.SampleGrad(g_s0, uv, ddxUV, ddyUV).rgb * 2.0 - 1.0);
        float3x3 tbn = float3x3(vsTangent, vsBitangent, vsNormal);
        normal = normalize(mul(normal, tbn));
    }

    // normalize(-WorldRayDirection()) = surface→camera = V (correct PBR convention; no sign flip needed)
    const float3 V = normalize(-WorldRayDirection());

    float3 outputColor = AmbientPBR(diffuseContrib, specularAlbedo, texSSAO[DispatchRaysIndex().xy] * ao, AmbientColor);

    // Area light: stochastic samples with per-sample RT shadow rays
    {
        float2 gridRotation = GetAreaLightGridRotation(DispatchRaysIndex().xy);
        [loop]
        for (uint li = 0; li < kAreaLightSampleCount; ++li)
        {
            float2 sampleOffset = GetAreaLightSampleOffset(li, gridRotation);
            float3 samplePos    = PointLightPos.xyz + float3(sampleOffset.x, 0.0f, sampleOffset.y);
            float  visibility   = TraceAreaLightSampleVisibility(worldPosition, normal, samplePos, payload.RecursionDepth);
            float3 L            = samplePos - worldPosition;
            float  invDist      = rsqrt(dot(L, L));
            L *= invDist;

            float distFalloff = 9.0f * invDist * invDist;
            distFalloff = max(0.0f, distFalloff - rsqrt(distFalloff));

            outputColor += distFalloff * EvaluatePBR(
                diffuseContrib, specularAlbedo, roughness,
                normal, V, L,
                PointLightColor.xyz / kAreaLightSampleCount,
                visibility);
        }
    }

    if (DebugView == 0 && MaxRecursionDepth > 0 && payload.RecursionDepth < MaxRecursionDepth && metallic > 0.5f)
    {
        float3 reflDir = reflect(WorldRayDirection(), normal);

        RayPayload reflPayload;
        reflPayload.SkipShading    = false;
        reflPayload.RayHitT        = FLT_MAX;
        reflPayload.Color          = float3(0, 0, 0);
        reflPayload.RecursionDepth = payload.RecursionDepth + 1;

        RayDesc reflRay;
        reflRay.Origin    = worldPosition + normal * 1e-4f;
        reflRay.TMin      = 0.0f;
        reflRay.Direction = reflDir;
        reflRay.TMax      = FLT_MAX;

        TraceRay(g_accel, RAY_FLAG_CULL_BACK_FACING_TRIANGLES, ~0, 0, 1, 0, reflRay, reflPayload);

        float3 F = F_Schlick(saturate(dot(normal, V)), specularAlbedo);
        outputColor += F * reflPayload.Color;
    }

    // Debug view override
    if (DebugView == 1)      outputColor = float3(ao, ao, ao);
    else if (DebugView == 2) outputColor = float3(roughness, roughness, roughness);
    else if (DebugView == 3) outputColor = float3(metallic, metallic, metallic);
    else if (DebugView == 4) outputColor = normal * 0.5 + 0.5;

    payload.Color = outputColor;
}
