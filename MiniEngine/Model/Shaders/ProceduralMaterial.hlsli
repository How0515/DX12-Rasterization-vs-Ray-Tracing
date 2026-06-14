//
// ProceduralMaterial.hlsli
// Single source of truth for Cornell Box procedural surface PBR parameters.
// Shared by ModelViewerPS.hlsl (raster) and DiffuseHitShaderLib.hlsl (RT).
//
// MaterialID convention:
//   0  - 26 : FlightHelmet submeshes — ORM texture path
//   100     : Floor          diffuse grey,  metallic=0, roughness=0.80
//   101     : Red Wall       diffuse red,   metallic=0, roughness=0.95
//   102     : Green Wall     diffuse green, metallic=0, roughness=0.95
//   103     : Back Wall      diffuse grey,  metallic=0, roughness=0.92
//   104     : Mirror Box     silver,        metallic=1, roughness=0.02  (reflection comparison)
//   105     : Ceiling        diffuse grey,  metallic=0, roughness=0.95
//   106     : Area Light     emissive panel

#ifndef PROCEDURAL_MATERIAL_HLSLI
#define PROCEDURAL_MATERIAL_HLSLI

struct ProcMat
{
    float3 baseColor;
    float  metallic;
    float  roughness;
    float  ao;
};

ProcMat GetProceduralMaterial(uint matID)
{
    ProcMat m;
    m.ao = 1.0;
    [branch] switch (matID)
    {
    case 100: m.baseColor = float3(0.725, 0.710, 0.680); m.metallic = 0.0; m.roughness = 0.80; break; // floor
    case 101: m.baseColor = float3(0.630, 0.060, 0.050); m.metallic = 0.0; m.roughness = 0.95; break; // red wall
    case 102: m.baseColor = float3(0.140, 0.450, 0.090); m.metallic = 0.0; m.roughness = 0.95; break; // green wall
    case 103: m.baseColor = float3(0.720, 0.710, 0.680); m.metallic = 0.0; m.roughness = 0.92; break; // back wall
    case 104: m.baseColor = float3(0.950, 0.950, 0.950); m.metallic = 1.0; m.roughness = 0.02; break; // mirror box
    case 105: m.baseColor = float3(0.720, 0.710, 0.680); m.metallic = 0.0; m.roughness = 0.95; break; // ceiling
    case 106: m.baseColor = float3(1.000, 0.950, 0.800); m.metallic = 0.0; m.roughness = 1.00; break; // area light
    default:  m.baseColor = float3(0.500, 0.500, 0.500); m.metallic = 0.0; m.roughness = 0.90; break;
    }
    return m;
}

#endif // PROCEDURAL_MATERIAL_HLSLI
