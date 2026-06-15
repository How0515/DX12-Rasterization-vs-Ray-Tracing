# DX12 Rasterization vs Ray Tracing

A DirectX 12 research renderer that compares rasterization approximation techniques against ray tracing on an effect-by-effect basis. Built as a graduate thesis project on Microsoft's D3D12 Raytracing MiniEngine sample.

---

## Overview

Modern real-time renderers combine rasterization and ray tracing rather than choosing one. The key question is not *which is better*, but **when raster approximations fail structurally and what a ray query does differently**.

This project implements both approaches for each lighting effect — shadow, reflection, glossy reflection, and global illumination — inside **a single engine with a shared scene, shared BRDF, and shared material data**. Each raster technique's failure conditions are reproduced with dedicated camera presets so the pipeline-level cause can be compared directly against its ray tracing counterpart.

> This is a **diagnostic comparison framework**, not a performance benchmark. The Cornell-style scene is intentionally simple to isolate variables, not to represent production workloads.

---

## Implemented Phases

| Phase | Effect | Raster | Ray Tracing |
|---|---|---|---|
| Phase 0 | Engine Analysis | DXR MiniEngine sample audit | — |
| Phase 1 | Scene Construction | Cornell Box + FlightHelmet | — |
| Phase 2 | Hard Shadow | Shadow Map (2048×2048, Reverse-Z) | Shadow Ray (`RAY_FLAG_ACCEPT_FIRST_HIT`) |
| Phase 3 | Soft Shadow | PCSS (64 blocker + filter samples) | Area-Light Shadow Rays (64 rays/hit) |
| Phase 4 | PBR Material | Cook-Torrance + ORM texture pipeline | Shared `EvaluatePBR` in RT hit shader |
| Phase 5 | Mirror Reflection | Screen-Space Reflection (SSR) | Recursive Reflection Ray (Depth 2/3/5) |
| Phase 6 | Glossy Reflection | GGX Prefiltered Environment Map (PEM) | GGX Importance-Sampled Reflection Ray |
| Phase 7 | Global Illumination | Environment Irradiance (diffuse IBL) | Cosine-weighted Diffuse Secondary Ray (1/2-bounce) |

---

## Scene

A closed Cornell-style diagnostic scene with:

- **Colored walls** (red left, green right, white top/back/floor) for observing color bleeding
- **Area light panel** on the ceiling
- **Box A** — left mirror box; roughness controllable via UI slider in Glossy mode
- **Box B** — right mirror box; fixed as perfect mirror baseline (roughness=0.02)
- **FlightHelmet** glTF model with ORM textures (metallic/roughness/AO)

Camera presets are arranged to expose specific artifact conditions: shadow contact, SSR screen-edge, off-screen missing, depth discontinuity, mirror-in-mirror reflection chain, glossy parallax error, and GI color bleeding.

---

## Controls

### Rendering Mode Keys

| Key | Mode | Description |
|---|---|---|
| `1` | Raster | Raster baseline, no shadows |
| `2` | Raster Shadow | Raster + Shadow Map / PCSS |
| `3` | Raster SSR | Raster + Shadow Map + Screen-Space Reflection |
| `4` | RT | RT primary rays + Shadow Map |
| `5` | RT Shadow | RT primary rays + Area-Light Shadow Rays |
| `6` | RT Refl (Depth 1) | RT Mirror Reflection, recursion depth 1 |
| `7` | RT Refl (Depth 2) | RT Mirror Reflection, recursion depth 2 |
| `8` | RT Refl (Depth 4) | RT Mirror Reflection, recursion depth 4 |
| `9` | Raster Glossy | GGX Prefiltered Environment Map |
| `0` | RT Glossy | GGX Importance-Sampled Reflection Ray (1 spp + TAA) |
| `G` | RT GI (1-bounce) | Cosine-weighted diffuse secondary ray, 1 bounce + TAA |
| `H` | Raster GI | Environment irradiance from diffuse cubemap |
| `J` | RT GI (2-bounce) | Cosine-weighted diffuse secondary ray, 2 bounces + TAA |

### Camera and Navigation

| Key | Action |
|---|---|
| `↑` / `↓` | Cycle through 14 camera presets |
| `←` / `→` | Adjust current parameter (roughness, light coefficient, etc.) |
| `T` | Jump to Shadow comparison preset |
| `Y` | Jump to Glossy comparison preset |
| `U` | Jump to GI color-bleeding preset |
| `F` | Freeze / unfreeze camera |

---

## Key Technical Observations

### Shadow (Phase 2–3)
- Shadow map **depth bias** is a trade-off between Peter Panning (over-offset) and Shadow Acne (under-offset). Shadow ray's world-space `TMin` epsilon avoids this discrete choice but still requires tuning for contact accuracy.
- Shadow caster culling in the shadow pass silently removes wall shadows; a two-sided shadow rasterizer is required.
- RT hard shadows provide contact-accurate visibility without texture resolution limits. RT soft shadow (64 rays) produces smooth penumbra proportional to light size.

### Mirror Reflection (Phase 5)
- SSR screen-edge cutoff, off-screen missing, and depth-discontinuity artifacts cannot be fixed by tuning step count — the required data simply does not exist in the color/depth buffer.
- Reflection ray Depth 2 → only direct reflection visible. Depth 5 → full `Camera → Floor → Box A → Box B → Helmet` chain completes. Results converge near Depth 5 because the Helmet is not a pure mirror.

### Glossy Reflection (Phase 6)
- PEM maps `mip = roughness × 6.0` from a single center capture → stable but shows **parallax error** (Box A absent from Box B's reflection surface).
- GGX IS ray: `roughness < 0.02` branches to `reflect()` for continuity with Phase 5. Higher roughness widens the GGX lobe and increases 1 spp/frame variance; noise accumulates multiplicatively with recursion depth.

### Global Illumination (Phase 7)
- Raster GI (H) samples the highest PEM mip along the surface normal — fully position-independent, so all surfaces with the same normal receive identical irradiance regardless of location.
- RT GI G (1-bounce) and J (2-bounce) express position-dependent color bleeding, but at 1 spp/frame variance masks the G vs J difference without extended TAA accumulation.
- GI modes force non-emissive materials to `metallic=0, roughness≥0.9` to eliminate mirror reflections that would contaminate the diffuse comparison.

---

## Architecture

```
Samples/Desktop/D3D12Raytracing/src/D3D12RaytracingMiniEngineSample/
└── ModelViewer.cpp             — main loop, mode switching, camera presets

MiniEngine/Model/Shaders/
├── PBR.hlsli                   — shared Cook-Torrance BRDF (GGX NDF, Smith G, Fresnel-Schlick)
├── ProceduralMaterial.hlsli    — material ID → metallic/roughness for Cornell surfaces
├── Lighting.hlsli              — direct lighting, shadow map, PEM, diffuse IBL flags
├── ImportanceSampleGGX.hlsli   — GGX half-vector sampling + Halton sequence
├── ModelViewerPS.hlsl          — raster pixel shader (shadow map, SSR, PEM, GI)
├── DiffuseHitShaderLib.hlsl    — RT closest-hit shader (shadow ray, reflection, glossy, GI)
├── RayGenerationShaderLib.hlsl — ray generation shader
└── PrefilterEnvMapCS.hlsl      — GGX prefilter compute shader (128×128, 7 mip levels)

docs/
└── thesis_draft_ko.md          — Korean thesis draft (full pipeline analysis)
```

**Data shared between Raster and RT paths:**
- Scene geometry / BLAS / TLAS
- Material tables (ORM textures + procedural parameters per surface ID)
- Area light definition
- `EvaluatePBR()` — identical Cook-Torrance evaluation in both pixel shader and hit shader

---

## Requirements

| Item | Requirement |
|---|---|
| OS | Windows 10 / 11 |
| GPU | DXR-capable (NVIDIA RTX / AMD RDNA2 or later) |
| SDK | Windows SDK 10.0.19041+ |
| IDE | Visual Studio 2022 |

Open `MiniEngine/ModelViewer/ModelViewer.sln` and build the `D3D12RaytracingMiniEngineSample` project in **Release x64**.

---

## Based On

[Microsoft DirectX-Graphics-Samples](https://github.com/microsoft/DirectX-Graphics-Samples) — D3D12 Raytracing MiniEngine Sample (MIT License)
