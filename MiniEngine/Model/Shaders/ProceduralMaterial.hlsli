//
// ProceduralMaterial.hlsli
// Single source of truth for Cornell Box procedural surface PBR parameters.
// Shared by ModelViewerPS.hlsl (raster) and DiffuseHitShaderLib.hlsl (RT).
//
// MaterialID convention:
//   0  - 26 : FlightHelmet submeshes — ORM texture path
//   100     : Floor          diffuse grey,  metallic=0, roughness=0.85
//   101     : Red Wall       diffuse red,   metallic=0, roughness=0.92
//   102     : Green Wall     diffuse green, metallic=0, roughness=0.92
//   103     : Back Wall      diffuse grey,  metallic=0, roughness=0.90
//   104     : Box            diffuse grey,  metallic=0, roughness=0.75  (matte paint)
//   105     : Ceiling        diffuse grey,  metallic=0, roughness=0.90
//   106     : Area Light     emissive panel
//   107     : Mirror Plate   gold tint,     metallic=1, roughness=0.05  (reflection test)

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
    case 100: m.baseColor = float3(0.725, 0.710, 0.680); m.metallic = 0.0; m.roughness = 0.85; break; // floor
    case 101: m.baseColor = float3(0.630, 0.060, 0.050); m.metallic = 0.0; m.roughness = 0.92; break; // red wall
    case 102: m.baseColor = float3(0.140, 0.450, 0.090); m.metallic = 0.0; m.roughness = 0.92; break; // green wall
    case 103: m.baseColor = float3(0.720, 0.710, 0.680); m.metallic = 0.0; m.roughness = 0.90; break; // back wall
    case 104: m.baseColor = float3(0.720, 0.710, 0.680); m.metallic = 0.0; m.roughness = 0.75; break; // box (matte paint)
    case 105: m.baseColor = float3(0.720, 0.710, 0.680); m.metallic = 0.0; m.roughness = 0.90; break; // ceiling
    case 106: m.baseColor = float3(1.000, 0.950, 0.800); m.metallic = 0.0; m.roughness = 1.00; break; // area light
    case 107: m.baseColor = float3(0.950, 0.900, 0.800); m.metallic = 1.0; m.roughness = 0.05; break; // mirror plate
    default:  m.baseColor = float3(0.500, 0.500, 0.500); m.metallic = 0.0; m.roughness = 0.90; break;
    }
    return m;
}

#endif // PROCEDURAL_MATERIAL_HLSLI
