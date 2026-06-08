---
page_type: sample
languages:
- cpp
products:
- windows-api-win32
name: Direct3D 12 raytracing samples
urlFragment: d3d12-raytracing-samples-win32
description: This collection of samples act as an introduction to DirectX Raytracing (DXR).
extendedZipContent:
- path: LICENSE
  target: LICENSE
---

# Direct3D 12 raytracing samples
This collection of samples act as an introduction to DirectX Raytracing (DXR). The samples are divided into tutorials and advanced samples. Each tutorial sample introduces a few new DXR concepts. Advanced samples demonstrate more complex techniques and applications of raytracing.

### Requirements
* GPU and driver with support for [DirectX 12 Ultimate](http://aka.ms/DirectX12UltimateDev)

### Getting Started
* DXR spec/documentation is available at [DirectX Specs site](https://microsoft.github.io/DirectX-Specs/d3d/Raytracing.html).

# Known issues
Depending on your Visual Studio version, some samples may fail to compile with these errors:
 * The system cannot find the path specified. *.hlsl.h
 * error MSB6006: "dxc.exe" exited with code 1.

Please see this GitHub issue for details on how to fix it: https://github.com/microsoft/DirectX-Graphics-Samples/issues/657

## [MiniEngine Sample](src/D3D12RaytracingMiniEngineSample/readme.md)
This sample demonstrates integration of the DirectX Raytracing in the MiniEngine's Model Viewer and several sample uses of raytracing.

![D3D12 Raytracing Mini Engine](src/D3D12RaytracingMiniEngineSample/Screenshot_small.png)


## Further resources
* [Nvidia's DXR samples Github](https://github.com/NVIDIAGameWorks/DxrTutorials)

## Feedback and Questions
We welcome all feedback, questions and discussions about DXR on our [discord server](http://discord.gg/directx).
