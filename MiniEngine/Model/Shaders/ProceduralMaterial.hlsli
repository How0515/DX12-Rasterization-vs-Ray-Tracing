//
// ProceduralMaterial.hlsli
// Single source of truth for Cornell Box procedural surface PBR parameters.
// Shared by ModelViewerPS.hlsl (raster) and DiffuseHitShaderLib.hlsl (RT).
//
// MaterialID convention:
//   0  - 26 : FlightHelmet submeshes — ORM texture path
//   100     : Floor          polished metal, metallic=0.85, roughness=0.15
//   101     : Red Wall       diffuse red,   metallic=0, roughness=0.95
//   102     : Green Wall     diffuse green, metallic=0, roughness=0.95
//   103     : Back Wall      diffuse grey,  metallic=0, roughness=0.92
//   104     : Box A          silver metallic (Stage 9/10) OR diffuse white (Stage 11 GI, giScene=1)
//   105     : Ceiling        diffuse grey,  metallic=0, roughness=0.95
//   106     : Area Light     emissive panel
//   107     : GI Box A       diffuse white, metallic=0, roughness=0.90  (explicit GI-scene material)
//   108     : Mirror Box B   silver,        metallic=1, roughness=0.02

#ifndef PROCEDURAL_MATERIAL_HLSLI
#define PROCEDURAL_MATERIAL_HLSLI

struct ProcMat
{
    float3 baseColor;
    float  metallic;
    float  roughness;
    float  ao;
};

// boxARoughness: runtime-controlled roughness for Box A (matID 104).
// giScene: when 1, all non-emissive procedural surfaces become rough diffuse
// so raster and RT GI modes compare the same material configuration.
ProcMat GetProceduralMaterial(uint matID, float boxARoughness, uint giScene)
{
    ProcMat m;
    m.ao = 1.0;
    [branch] switch (matID)
    {
    case 100: m.baseColor = float3(0.800, 0.800, 0.820); m.metallic = 0.85; m.roughness = 0.15;           break; // floor
    case 101: m.baseColor = float3(0.630, 0.060, 0.050); m.metallic = 0.0;  m.roughness = 0.95;           break; // red wall
    case 102: m.baseColor = float3(0.140, 0.450, 0.090); m.metallic = 0.0;  m.roughness = 0.95;           break; // green wall
    case 103: m.baseColor = float3(0.720, 0.710, 0.680); m.metallic = 0.0;  m.roughness = 0.92;           break; // back wall
    case 104:                                                                                                        // Box A
        if (giScene)
        { m.baseColor = float3(0.900, 0.900, 0.900); m.metallic = 0.0;  m.roughness = 0.90; }            // GI: diffuse white
        else
        { m.baseColor = float3(0.950, 0.950, 0.950); m.metallic = 1.0;  m.roughness = boxARoughness; }   // Stage 9/10: silver metallic
        break;
    case 105: m.baseColor = float3(0.720, 0.710, 0.680); m.metallic = 0.0;  m.roughness = 0.95;           break; // ceiling
    case 106: m.baseColor = float3(1.000, 0.950, 0.800); m.metallic = 0.0;  m.roughness = 1.00;           break; // area light
    case 107: m.baseColor = float3(0.900, 0.900, 0.900); m.metallic = 0.0;  m.roughness = 0.90;           break; // GI Box A (explicit)
    case 108: m.baseColor = float3(0.950, 0.950, 0.950); m.metallic = 1.0;  m.roughness = 0.02;           break; // Box B (mirror reference)
    default:  m.baseColor = float3(0.500, 0.500, 0.500); m.metallic = 0.0;  m.roughness = 0.90;           break;
    }

    if (giScene && matID != 106)
    {
        m.metallic  = 0.0;
        m.roughness = max(m.roughness, 0.90);
    }

    return m;
}

#endif // PROCEDURAL_MATERIAL_HLSLI
