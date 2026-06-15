# 논문 초안 v0.1

## 제목 후보

**동일 엔진 내 비교 프레임워크를 통한 래스터 근사 기법과 레이 트레이싱 질의의 파이프라인 수준 분석**

영문 제목:

**Pipeline-Level Analysis of Raster Approximation and Ray-Traced Queries through an In-Engine Comparative Framework**

---

## 초록

실시간 그래픽스에서 래스터라이제이션과 레이 트레이싱은 상호 배타적인 렌더링 방식이 아니라, 요구되는 품질과 성능 조건에 따라 함께 사용되는 보완적 기술이다. 래스터라이제이션은 화면에 투영되는 기하를 효율적으로 처리하지만, 그림자, 반사, 간접광과 같이 화면 밖 또는 다른 시점의 장면 정보가 필요한 효과를 직접 계산하지 못한다. 따라서 shadow map, screen-space reflection, prefiltered environment map, lightmap 및 probe와 같은 근사 기법을 사용한다. 반면 레이 트레이싱은 가속 구조를 대상으로 광선 질의를 수행하여 동일한 효과를 월드 공간에서 직접 계산할 수 있지만, 광선 순회 비용과 확률적 샘플링 노이즈, 엔진 통합 복잡성을 추가로 요구한다.

본 연구는 두 방식의 절대적인 성능 우열을 판정하는 대신, 동일한 DirectX 12 MiniEngine 기반에서 래스터 근사 기법과 대응하는 DXR 기반 질의를 단계적으로 구현하고 비교할 수 있는 실험 프레임워크를 구축한다. 실험 장면은 Cornell Box를 기반으로 단순화하여 복잡한 게임 장면에서 발생하는 변수를 줄이고, 그림자 경계, 화면 공간 정보 손실, 다중 반사, 거친 표면 반사 및 색 번짐과 같은 현상을 의도적으로 관찰할 수 있도록 구성하였다. 또한 두 렌더링 경로가 동일한 카메라, 기하, 재질, 면광원 및 Cook-Torrance 기반 BRDF를 공유하도록 하여, 결과 차이가 가능한 한 가시성 및 radiance 질의 방식의 차이에서 발생하도록 설계하였다.

연구는 Microsoft의 D3D12 Raytracing MiniEngine Sample 구조 분석에서 시작하여 Cornell 스타일 실험 환경 구축, shadow map과 shadow ray 비교, PCSS와 면광원 샘플링 비교, 공통 PBR 조명 모델 도입, SSR과 reflection ray 비교, prefiltered environment map과 GGX importance-sampled glossy reflection 비교, 환경맵 기반 간접광과 재귀 깊이를 제어할 수 있는 diffuse path tracing 비교 순서로 진행된다. 각 단계에서는 렌더링 결과의 현상적 차이뿐 아니라, 필요한 장면 정보의 범위, 좌표 공간 변환, depth bias와 ray epsilon, 재귀 깊이, 샘플링 분산, 리소스 상태 및 셰이더 데이터 정합성 등 파이프라인 수준의 원인을 함께 분석한다.

본 연구의 결과물은 생산 환경의 절대 성능을 대표하는 벤치마크가 아니라, 래스터 근사 기법이 실패하는 조건과 레이 트레이싱이 이를 해결하는 원리를 엔진 수준에서 재현하고 분석하기 위한 교육적·실험적 프레임워크이다. 이를 바탕으로 향후에는 래스터라이제이션을 기본 가시성 경로로 유지하면서, 화면 공간 정보가 불충분하거나 높은 정확도가 필요한 효과에 선택적으로 레이 질의를 적용하는 혼합 렌더러로 확장하고자 한다.

**핵심어:** Rasterization, Ray Tracing, DirectX Raytracing, Hybrid Rendering, Shadow Map, PCSS, SSR, PBR, Glossy Reflection, Global Illumination

---

# 1. 서론

## 1.1 연구 배경

실시간 렌더링에서 래스터라이제이션은 오랜 기간 표준적인 가시성 결정 방식으로 사용되어 왔다. 래스터라이저는 삼각형을 화면 공간으로 투영한 뒤, 픽셀 단위의 depth test와 shading을 수행함으로써 높은 처리량을 제공한다. 그러나 이 구조는 기본적으로 현재 카메라에서 보이는 표면을 중심으로 동작한다. 그림자, 반사, 굴절, 간접광처럼 다른 위치 또는 방향에서 장면의 가시성을 확인해야 하는 효과는 기본 래스터 파이프라인만으로 직접 계산하기 어렵다.

이를 보완하기 위해 실시간 그래픽스에서는 다양한 근사 기법이 발전하였다. Shadow map은 광원 시점의 depth buffer를 이용하여 그림자를 판정하고, screen-space reflection(SSR)은 현재 프레임의 color 및 depth buffer를 이용하여 반사를 추정한다. Prefiltered environment map은 방향별 조명 정보를 미리 필터링하여 거친 표면 반사를 근사하며, lightmap과 probe는 간접광을 사전 계산하거나 제한된 위치에 저장한다. 이러한 기법은 높은 효율을 제공하지만, 사용하는 데이터의 해상도, 투영 범위, 화면 포함 여부, 사전 계산 조건에 의해 구조적인 오차가 발생한다.

DirectX Raytracing(DXR)은 가속 구조를 대상으로 광선을 추적할 수 있는 파이프라인을 제공한다. Shadow ray는 표면과 광원 사이의 실제 차폐 여부를 검사하고, reflection ray는 화면 밖을 포함한 반사 방향의 장면을 탐색하며, diffuse secondary ray는 간접광을 추정할 수 있다. 따라서 레이 트레이싱은 래스터 근사 기법의 정보 부족 문제를 완화할 수 있다. 그러나 광선 순회 비용, 샘플 수에 따른 성능 증가, 확률적 노이즈, denoising 및 기존 엔진과의 데이터 정합성 문제를 새롭게 발생시킨다.

현대 실시간 렌더러는 두 기술 중 하나만을 선택하기보다, 래스터라이제이션의 처리량과 레이 트레이싱의 정확한 장면 질의를 결합하는 방향으로 발전하고 있다. 그러므로 중요한 질문은 “어느 기술이 더 우수한가”가 아니라, “특정 효과에서 래스터 근사가 어떤 정보를 사용하며 어디에서 실패하는가”, “레이 질의는 무엇을 다르게 계산하여 그 문제를 해결하는가”, 그리고 “두 방식을 하나의 엔진에서 어떻게 일관되게 연결할 수 있는가”이다.

## 1.2 문제 정의

래스터라이제이션과 레이 트레이싱의 장단점은 이미 널리 알려져 있다. 단순히 두 방식의 결과 이미지나 프레임 시간을 비교하는 연구는 다음과 같은 한계를 가진다.

첫째, 서로 다른 렌더러의 결과를 비교할 경우 장면, 재질, 조명 모델, 후처리 및 최적화 수준이 달라 결과 차이의 원인을 분리하기 어렵다. 둘째, 복잡한 게임 장면에서의 성능 수치는 실제 응용에는 유용하지만, 특정 artifact가 발생한 파이프라인 원인을 추적하기 어렵다. 셋째, 레이 트레이싱의 절대 성능은 장면 복잡도, 가속 구조, 하드웨어 및 샘플 수에 크게 의존하므로 단순 장면에서 얻은 수치를 일반화하기 어렵다.

본 연구는 이러한 한계를 인정하고 연구 목표를 다르게 설정한다. 동일 엔진 내부에서 동일한 장면과 shading 조건을 유지한 채, 하나의 시각 효과를 래스터 근사 방식과 레이 질의 방식으로 각각 구현한다. 이후 근사 방식의 실패 조건을 의도적으로 재현하고, 결과 이미지와 파이프라인 데이터를 함께 분석한다. 즉, 본 연구에서 단순한 Cornell 스타일 장면은 생산 환경을 대표하기 위한 축소판이 아니라, 변수를 통제하고 원인과 결과를 명확히 연결하기 위한 진단용 실험 장치이다.

## 1.3 연구 질문

본 연구는 다음 질문에 답하고자 한다.

1. Shadow map, PCSS, SSR, prefiltered environment map 및 환경맵 기반 간접광은 각각 어떤 제한된 정보를 사용하며, 어떤 조건에서 구조적으로 실패하는가?
2. 대응하는 shadow ray, area light sampling, reflection ray, GGX importance sampling 및 diffuse secondary ray는 어떤 월드 공간 질의를 수행하여 근사 기법의 한계를 완화하는가?
3. 동일 엔진에서 두 경로를 공정하게 비교하기 위해 어떤 기하, 재질, 조명 및 상수 데이터를 공유해야 하는가?
4. 레이 트레이싱 통합 과정에서 발생하는 bias, epsilon, 좌표계, winding, normal, recursion, resource state 및 temporal sampling 문제는 결과에 어떤 영향을 주는가?
5. 각 비교 결과로부터 어떤 조건에서 래스터 근사를 유지하고, 어떤 조건에서 선택적으로 레이 질의를 사용하는 혼합 렌더러 설계 원칙을 도출할 수 있는가?

## 1.4 연구 가설

본 연구는 다음 세 가지 가설을 중심으로 실험을 구성한다.

**가설 1.** 래스터 근사 기법의 대표적인 artifact는 단순한 파라미터 조정 실패가 아니라, 효과 계산에 필요한 월드 공간 정보가 shadow map, screen buffer 또는 environment map에 포함되지 않을 때 발생한다. 해상도와 filter 조정은 artifact를 완화할 수 있지만, 표현에서 제거된 정보를 복원할 수는 없다.

**가설 2.** 레이 트레이싱은 가속 구조에 대한 월드 공간 질의를 통해 래스터 근사의 구조적인 정보 누락을 줄일 수 있다. 그러나 오차가 완전히 사라지는 것이 아니라, 유한 sample의 분산, ray epsilon, recursion 제한 및 temporal accumulation 문제로 이동한다.

**가설 3.** Raster와 RT 경로가 동일한 장면, 재질, 광원 및 BRDF를 공유하는 비교 프레임워크를 구축하면 결과 차이의 원인을 정보 표현과 질의 방식의 차이로 추적할 수 있다. 이 분석은 효과별로 적절한 방식을 선택하는 혼합 렌더러의 설계 기준으로 연결될 수 있다.

## 1.5 연구 목표

본 연구의 1차 목표는 래스터라이제이션과 레이 트레이싱의 절대적 우열을 제시하는 것이 아니다. 목표는 두 방식의 차이를 “최종 이미지 생성 방식”이 아니라 “필요한 장면 정보를 질의하는 방식”의 차이로 해석하는 것이다.

래스터 근사 기법은 월드 공간의 복잡한 질의를 제한된 표현으로 변환한다. Shadow map은 광원 시점의 2차원 depth texture로, SSR은 현재 화면의 color/depth buffer로, environment map은 위치 정보를 제거한 방향별 radiance로 장면을 축약한다. 이 축약은 효율의 근원이지만, 동시에 정보 손실의 원인이 된다.

레이 트레이싱은 동일한 질문을 가속 구조에 대한 월드 공간 광선 질의로 수행한다. 이는 투영 범위나 화면 포함 여부에 의한 정보 손실을 줄이지만, 광선 수와 재귀 깊이, 확률적 샘플링 분산 및 엔진 통합 비용을 요구한다.

따라서 본 연구의 목표는 다음과 같다.

- 래스터 근사 기법의 실패 현상을 재현 가능한 장면과 카메라 프리셋으로 구성한다.
- 동일 효과에 대응하는 DXR 기반 질의를 구현한다.
- 두 경로가 가능한 한 동일한 BRDF, 재질, 광원 및 장면 데이터를 사용하도록 정합성을 확보한다.
- 결과 차이의 현상적 설명과 파이프라인 수준의 원인을 연결한다.
- 향후 혼합 렌더러를 설계하기 위한 기술 선택 기준을 도출한다.

## 1.6 연구 범위와 제한

본 연구는 Microsoft D3D12 Raytracing MiniEngine Sample을 기반으로 구현한다. 실험 장면은 Cornell Box의 구조를 참고한 폐쇄형 공간, 면광원, 색상이 다른 벽, 두 개의 박스 및 세부 형상을 가진 helmet 모델로 구성한다. 장면은 그림자, 반사, 다중 반사, 거친 표면 반사 및 색 번짐을 관찰하기에 충분하지만, 실제 게임 장면의 기하 복잡도와 동적 오브젝트 수를 대표하지 않는다.

또한 본 연구의 BRDF는 metallic-roughness 재질과 Cook-Torrance 구조를 사용하지만, diffuse 항의 정규화와 environment BRDF LUT 등 일부 요소는 실험 목적에 맞게 단순화되어 있다. RT glossy reflection과 diffuse GI는 제한된 샘플 수 및 TAA 누적을 사용하며, 완전한 production denoiser는 포함하지 않는다.

따라서 본 연구는 단순 장면에서 측정한 GPU 시간을 성능 결론으로 제시하지 않으며, 레이 트레이싱의 절대적 성능 overhead 또는 실제 게임 엔진의 최종 품질을 대표한다고 주장하지 않는다. 대신 sample 수, 재귀 깊이 및 추가 파이프라인 단계가 만드는 계산 복잡도의 차이를 설명한다.

## 1.7 연구 기여

본 연구의 기여는 다음과 같다.

1. 하나의 MiniEngine 기반 실행 파일에서 래스터 근사 방식과 대응하는 RT 방식을 즉시 전환하여 비교할 수 있는 단계적 실험 프레임워크를 구축하였다.
2. Cornell 스타일 장면과 artifact 관찰용 카메라 프리셋을 사용하여 screen edge, off-screen missing, depth discontinuity, shadow bias, PCSS over-blur 및 다중 반사와 같은 실패 조건을 재현하였다.
3. Raster 및 RT 경로가 공통 Cook-Torrance BRDF, 재질 속성, 면광원 및 장면 기하를 공유하도록 구성하여 비교 시 shading 모델 차이를 줄였다.
4. 각 근사 기법의 정보 제한과 대응 RT 질의를 파이프라인 수준에서 연결하고, 구현 과정에서 발생한 버그를 좌표계, 가시성, 샘플링 및 리소스 관리 관점으로 분류하였다.
5. 비교 결과를 바탕으로 향후 혼합 렌더러가 레이 질의를 선택적으로 적용할 수 있는 설계 방향을 제안한다.

본 연구는 새로운 shadow, reflection 또는 GI 알고리즘 자체의 발명을 주장하지 않는다. 기여의 중심은 기존 기법들을 하나의 엔진과 통제 장면 안에서 대응 관계로 재구성하고, 결과 artifact와 내부 파이프라인 원인을 연결하여 분석할 수 있는 비교 방법론 및 구현 프레임워크에 있다.

## 1.8 논문 구성

2장에서는 래스터라이제이션, DXR 파이프라인, 가시성 질의, BRDF 및 혼합 렌더링 관련 이론을 설명한다. 3장에서는 연구에 사용한 엔진 구조, Cornell 스타일 장면, 비교 조건 및 평가 방법을 제시한다. 4장에서는 Phase 0부터 Phase 7까지의 구현과 실험을 순서대로 설명한다. 5장에서는 단계별 결과를 정보 표현, 오차, 비용 및 엔진 통합 문제 관점에서 종합한다. 6장에서는 연구의 한계와 혼합 렌더러 확장 방향을 논의하고, 7장에서 결론을 제시한다.

---

# 2. 관련 기술 및 이론

## 2.1 래스터라이제이션 파이프라인

래스터라이제이션은 정점 셰이더에서 기하를 clip space로 변환하고, 삼각형을 화면의 fragment로 변환한 뒤, depth test와 pixel shading을 수행한다. 이 방식은 화면에 투영되는 삼각형을 높은 병렬성으로 처리한다. 그러나 pixel shader가 기본적으로 접근하는 정보는 현재 fragment의 속성과 바인딩된 texture 및 buffer로 제한된다.

그림자나 반사를 계산하기 위해서는 현재 표면에서 다른 방향으로 장면을 다시 질의해야 한다. 래스터 파이프라인은 이를 직접 제공하지 않으므로, 별도의 pass를 통해 필요한 정보를 texture로 저장하거나 현재 화면의 buffer를 재사용한다. 결과적으로 래스터 기반 효과의 정확도는 저장된 정보의 해상도, 투영 방식, 갱신 주기 및 포함 범위에 의존한다.

## 2.2 레이 트레이싱 파이프라인

DXR은 bottom-level acceleration structure(BLAS)와 top-level acceleration structure(TLAS)를 사용하여 장면 기하에 대한 광선 교차 검사를 가속한다. Ray generation shader는 광선의 origin과 direction을 생성하고, traversal 과정에서 교차 후보를 탐색한다. Closest-hit shader는 가장 가까운 교차점의 shading을 수행하며, miss shader는 광선이 장면과 교차하지 않았을 때의 결과를 결정한다.

Shadow ray는 표면에서 광원 방향으로 광선을 발사하여 광원보다 가까운 교차점이 존재하는지 확인한다. Reflection ray는 반사 방향으로 새로운 광선을 발사하며, diffuse secondary ray는 반구 방향을 샘플링하여 간접광을 추정한다. 이러한 질의는 현재 화면에 포함되지 않은 기하에도 접근할 수 있다.

## 2.3 가시성 질의와 정보 표현

본 연구에서는 래스터 근사와 레이 트레이싱의 차이를 다음과 같은 정보 표현의 차이로 정의한다.

| 효과 | 래스터 근사가 사용하는 정보 | 정보 손실 또는 제약 | 대응 RT 질의 |
|---|---|---|---|
| Hard Shadow | 광원 시점 depth map | 해상도, bias, 투영 범위 | 표면-광원 구간 교차 검사 |
| Soft Shadow | 단일 shadow map의 blocker 및 filter 추정 | 실제 광원 면적별 가시성 부재 | 면광원 위 여러 점으로 shadow ray |
| Reflection | 현재 화면 color/depth | off-screen 및 가려진 기하 부재 | 반사 방향 closest-hit |
| Glossy Reflection | 방향별 prefiltered environment map | 위치 및 국소 차폐 정보 부재 | GGX 분포 기반 반사 광선 |
| Indirect Lighting | lightmap/probe/environment irradiance | 위치 해상도, 동적 변화, 방향 정보 제한 | diffuse secondary ray |

이 표에서 공통적으로 확인할 수 있는 점은 래스터 근사가 월드 공간 질의를 더 작은 데이터 표현으로 축약한다는 것이다. RT는 축약된 texture를 조회하는 대신 광선을 통해 장면에 직접 질문한다.

## 2.4 Shadow Map과 Shadow Ray

Shadow map은 광원 관점에서 장면을 렌더링하여 가장 가까운 depth를 저장한다. 카메라 pass의 표면 위치를 shadow space로 변환하고 저장된 depth와 비교하여 그림자 여부를 판정한다. 이때 동일 표면의 수치 오차로 발생하는 shadow acne를 줄이기 위해 depth bias 또는 slope-scaled depth bias를 사용한다. Bias가 작으면 acne가 발생하고, 크면 물체와 그림자가 분리되는 peter-panning이 발생한다.

Shadow ray는 표면에서 광원까지의 구간에 다른 기하가 존재하는지 직접 검사한다. Shadow map의 texel 해상도나 광원 투영 범위에는 의존하지 않지만, ray origin이 자기 자신과 다시 교차하지 않도록 작은 epsilon을 적용해야 한다. 따라서 shadow map의 depth bias와 shadow ray의 origin epsilon은 목적이 유사하지만 서로 다른 공간과 단위에서 동작하는 수치 안정화 장치이다.

## 2.5 PCSS와 면광원 샘플링

Percentage-Closer Soft Shadows(PCSS)는 shadow map에서 blocker를 탐색하고, receiver와 blocker 거리 차이를 이용하여 penumbra 크기를 추정한 뒤, 가변 반경 PCF를 적용한다. PCSS는 단일 shadow map으로 접촉부에서 날카롭고 멀어질수록 부드러운 그림자를 생성할 수 있다. 그러나 실제 면광원의 각 위치에 대한 가시성을 계산하지 않으므로 blocker 탐색 실패, 과도한 filter radius 및 shadow map 투영 오차의 영향을 받는다.

RT 기반 면광원 그림자는 광원 면적 위 여러 점을 샘플링하고 각 점까지 shadow ray를 발사한다. 가시성 평균은 광원 면적 중 보이는 비율을 근사하며, 실제 차폐 관계에서 penumbra가 형성된다. 샘플 수가 적으면 noise 또는 grid pattern이 발생하고, 샘플 수가 많으면 비용이 증가한다.

## 2.6 Screen-Space Reflection과 Reflection Ray

SSR은 현재 프레임의 depth buffer를 따라 반사 ray를 march하고, 추정된 교차 위치에서 화면 color를 조회한다. 이미 생성된 화면 buffer를 사용하므로 효율적이지만, 화면 밖의 물체, 다른 물체 뒤에 가려진 표면 및 depth buffer에 표현되지 않은 뒷면은 반사할 수 없다. 또한 depth buffer가 표면의 전면 깊이만 저장하기 때문에 얇은 물체, 깊이 불연속 및 grazing angle에서 오차가 증가한다.

Reflection ray는 월드 공간 반사 방향으로 TLAS를 질의하여 가장 가까운 표면을 찾는다. 화면 밖 기하와 가려진 기하를 반사할 수 있으며, 재귀 깊이를 늘려 mirror-in-mirror 효과를 표현할 수 있다. 반면 재귀 깊이에 따라 ray 수와 shading 호출이 증가하고, payload와 RTPSO recursion 설정을 일관되게 관리해야 한다.

## 2.7 Cook-Torrance BRDF와 공통 Shading 기준

본 연구는 Raster 및 RT 경로에서 공통으로 사용할 수 있도록 metallic-roughness 기반 Cook-Torrance BRDF를 구성한다. Specular 항은 GGX normal distribution, Smith geometry term 및 Fresnel-Schlick 근사를 사용한다. Diffuse 재질은 base color에 주로 기여하고, metallic 재질은 base color를 specular reflectance로 사용한다.

공통 BRDF 도입은 독립적인 품질 개선 단계이면서, 이후 비교 실험의 통제 조건이기도 하다. Raster와 RT가 서로 다른 조명 모델을 사용하면 그림자 또는 반사 방식의 차이와 BRDF 차이를 구분하기 어렵다. 따라서 Phase 4 이후의 비교에서는 가능한 한 동일한 재질 파라미터와 `EvaluatePBR` 함수를 공유한다.

## 2.8 Glossy Reflection과 Importance Sampling

거친 금속 표면의 반사는 완전한 mirror direction 하나가 아니라 microfacet 분포에 의해 여러 방향으로 퍼진다. Raster 기반 방식에서는 environment cubemap을 roughness에 따라 서로 다른 mip level로 prefilter하여 이 적분을 근사할 수 있다. 이 방식은 실행 시 texture lookup만 필요하지만, environment capture 위치와 다른 지점에서 발생하는 parallax, 국소 차폐 및 동적 변화에 취약하다.

RT 방식에서는 GGX 분포를 importance sampling하여 반사 방향을 생성할 수 있다. 각 프레임의 샘플은 noisy하지만, 시간 누적과 denoising을 통해 수렴시킬 수 있다. 이 방식은 현재 위치의 실제 가시성을 반영하지만, 샘플 분산과 temporal stability 문제가 발생한다.

## 2.9 Global Illumination

간접광은 직접광을 받은 표면에서 반사된 빛이 다른 표면에 도달하는 현상이다. Raster 기반 실시간 렌더러는 lightmap, irradiance probe, voxel, screen-space GI 또는 environment irradiance 등의 근사 방식을 사용한다. 본 연구의 raster baseline은 prefiltered environment cubemap의 낮은 주파수 정보를 surface normal 방향으로 조회하여 diffuse irradiance를 근사한다.

RT 기반 baseline은 diffuse 표면에서 cosine-weighted hemisphere 방향으로 secondary ray를 발사하고, 교차한 표면의 radiance를 현재 표면의 base color와 결합한다. 본 구현은 재귀 깊이를 제어하여 1-bounce와 2-bounce 결과를 비교할 수 있다. 낮은 sample count에서도 색 번짐과 위치별 차폐를 관찰할 수 있지만, noise를 완화하기 위한 시간 누적이 필요하다.

## 2.10 혼합 렌더링

혼합 렌더링은 래스터라이제이션을 기본적인 primary visibility 및 G-buffer 생성에 사용하고, 그림자, 반사 또는 간접광 중 필요한 일부 질의에 RT를 적용한다. 이 구조에서 중요한 것은 RT를 단순히 활성화하는 것이 아니라, 래스터 데이터가 충분한 경우와 부족한 경우를 구분하는 것이다.

본 연구에서는 이를 “정보 충분성” 관점으로 해석한다. 현재 화면이나 사전 계산 texture가 필요한 정보를 충분히 포함하면 래스터 근사가 효율적이다. 반대로 off-screen 기하, 복잡한 차폐, 위치 종속 반사 또는 동적 간접광이 필요한 경우 월드 공간 ray query의 가치가 증가한다.

---

# 3. 연구 방법 및 실험 프레임워크

## 3.1 기반 엔진

본 연구는 Microsoft DirectX-Graphics-Samples 저장소의 D3D12 Raytracing MiniEngine Sample에서 시작하였다. 원본 샘플은 MiniEngine Model Viewer에 DXR을 연결하고, primary ray, barycentric 시각화, shadow ray 및 reflection ray의 기초 사용 방법을 제공한다.

연구 과정에서는 원본 샘플의 렌더링 모드, root signature, shader table, acceleration structure 생성, raster pass 및 post effect 구조를 분석한 뒤, 비교 실험에 필요한 Cornell 스타일 장면과 공통 shading 경로를 추가하였다. 또한 실행 중 단축키로 Raster, Raster Shadow, Raster SSR, RT, RT Shadow, 재귀 반사, Raster Glossy, RT Glossy, Raster GI 및 RT GI 모드를 전환할 수 있도록 확장하였다.

원본 샘플의 README와 현재 구현 사이에는 기능 차이가 있으므로, 최종 논문에서는 수정된 모드 표와 실행 조건을 별도 표로 제시한다.

## 3.2 Cornell 스타일 진단 장면

실험 장면은 Cornell Box의 대표적 구성을 참고하였다. 장면은 색상이 다른 좌우 벽, 흰색 후면 벽, 바닥, 천장, 면광원, 두 개의 박스 및 helmet 모델로 구성된다. 두 박스는 그림자 차폐 및 반사 실험에 사용되며, 일부 모드에서는 metallic 또는 diffuse 재질로 전환된다.

Cornell Box를 선택한 이유는 다음과 같다.

- 평면 벽과 바닥은 그림자 경계, seam, bias 및 color bleeding을 관찰하기 쉽다.
- 제한된 공간은 면광원과 차폐물의 상대적 위치를 통제하기 쉽다.
- 색상이 다른 벽은 간접광의 색 번짐을 명확히 드러낸다.
- 거울 박스와 helmet은 단일 반사 및 다중 반사 경로를 구성할 수 있다.
- 장면 복잡도가 낮아 pipeline bug와 알고리즘 artifact를 구분하기 쉽다.

이 장면은 생산 환경 성능 측정을 위한 benchmark가 아니라, 렌더링 현상의 원인을 분리하기 위한 diagnostic scene으로 사용한다.

## 3.3 공정한 비교를 위한 통제 조건

두 경로의 비교에서 다음 조건을 가능한 한 동일하게 유지한다.

1. 동일한 기하와 world transform을 사용한다.
2. 동일한 카메라 위치, 방향, FOV 및 출력 해상도를 사용한다.
3. 동일한 면광원 위치, 크기, 색상 및 세기를 사용한다.
4. 동일한 material ID, base color, metallic, roughness 및 AO를 사용한다.
5. 직접광 계산에 공통 Cook-Torrance BRDF 함수를 사용한다.
6. shadow 또는 reflection 방식 외의 후처리 조건을 동일하게 유지한다.
7. artifact 관찰용 카메라 프리셋을 고정하여 반복 촬영이 가능하도록 한다.

완전한 동일 조건을 유지하기 어려운 경우에는 차이를 명시한다. 예를 들어 Raster 면광원 직접광은 제한된 대표 점을 사용하고, RT 면광원 그림자는 64개 광원 위치를 사용한다. 이러한 차이는 결과 해석 시 알고리즘 구성의 일부로 기록한다.

GI 비교 모드에서는 재질 차이가 결과를 오염시키지 않도록 추가 통제를 적용하였다. H(Raster GI), G(RT GI 1-bounce), J(RT GI 2-bounce)가 활성화되면 면광원 패널을 제외한 절차적 표면과 textured mesh의 metallic 값을 0으로 설정하고 roughness를 최소 0.9로 맞춘다. 이에 따라 바닥과 Box A/B의 거울 반사는 제거되며, 세 모드의 차이는 환경 기반 간접광 근사와 diffuse secondary ray의 차이로 제한된다. 일반 reflection 및 glossy 모드에서는 기존 metallic 재질을 유지한다.

## 3.4 비교 프레임워크의 모드

현재 구현의 주요 비교 모드는 다음과 같다.

| 모드 | 목적 |
|---|---|
| Raster | 그림자 없는 raster baseline |
| Raster Shadow | Raster shading + shadow map/PCSS |
| Raster SSR | Raster shading + shadow map + SSR |
| RT | Primary ray shading + shadow map |
| RT Shadow | Primary ray shading + area-light shadow rays |
| RT Reflection Depth 1/2/4 | 재귀 깊이에 따른 반사 비교 |
| Raster Glossy | GGX prefiltered environment map |
| RT Glossy | GGX importance-sampled reflection ray |
| Raster GI | Environment irradiance 기반 diffuse GI 근사 |
| RT GI | Cosine-weighted diffuse secondary ray, 1/2-bounce depth control |

이 구조는 효과별 비교뿐 아니라 혼합 조합을 분석할 수 있게 한다. 예를 들어 primary visibility는 RT를 사용하면서 그림자는 shadow map으로 계산하는 모드를 통해, primary ray와 shadow ray의 영향을 분리할 수 있다.

GI 실험 단축키는 G=RT GI 1-bounce, H=Raster GI, J=RT GI 2-bounce로 구성하였다. 화면 UI에는 현재 모드, 재귀 깊이, TAA 활성 상태 및 단축키 범례를 표시하여 캡처 조건을 확인할 수 있게 하였다. 구현 과정에서 secondary payload의 재귀 깊이가 올바르게 증가하지 않던 문제를 수정하였고, 현재는 G와 J가 각각 의도한 1/2-bounce 깊이를 사용한다. TAA는 확률적 RT Glossy 및 RT GI에서만 활성화하고 deterministic Raster GI와 mirror 모드에서는 비활성화한다.

## 3.5 평가 관점

본 연구의 평가는 정량 성능 하나가 아니라 다음 네 관점을 함께 사용한다.

### 3.5.1 현상적 품질

- 그림자 경계의 aliasing, over-blur 및 contact loss
- SSR의 screen-edge cutoff, off-screen missing 및 depth discontinuity
- reflection depth에 따른 누락
- glossy reflection의 공간 정확도 및 noise
- GI의 color bleeding 및 위치 종속성

### 3.5.2 파이프라인 원인

- 어떤 buffer 또는 acceleration structure를 질의하는가?
- 질의가 어느 좌표 공간에서 수행되는가?
- 필요한 정보가 표현에 포함되어 있는가?
- 오류가 해상도, bias, sampling, recursion 또는 데이터 정합성 중 어디에서 발생하는가?

### 3.5.3 실험 설정 및 계산 복잡도

- shadow/reflection/GI ray 수
- shadow map 해상도 및 PCSS sample count
- RT sample count와 recursion depth
- temporal accumulation에 필요한 frame 수
- 각 효과가 요구하는 pass, buffer, acceleration structure 및 shader 단계

본 연구는 단순화된 진단 장면을 사용하므로 측정된 GPU 시간이 실제 게임 장면의 절대 성능 오버헤드를 대표하기 어렵다. 따라서 GPU frame time의 우열 비교는 평가 범위에서 제외하고, 각 방식에서 추가되는 질의 수, 재귀 깊이, 샘플 수 및 파이프라인 구성의 차이를 계산 복잡도의 지표로 사용한다.

### 3.5.4 구현 복잡성

- 추가 리소스와 descriptor
- BLAS/TLAS 및 shader table 구성
- raster/RT 재질 데이터 동기화
- resource state transition
- 디버깅 난이도와 발생한 버그 유형

## 3.6 재현 가능한 관찰 실험 계획

본 연구는 절대 성능 벤치마크보다 근사 기법의 실패 조건과 그 파이프라인 원인을 재현하는 데 초점을 둔다. 각 실험은 다음 절차로 수행한다.

1. 출력 해상도, 카메라, 장면 기하, 재질 및 광원 조건을 고정한다.
2. 비교하려는 한 가지 독립 변수만 변경하고 동일 구도의 결과 이미지를 기록한다.
3. 화면에 나타난 artifact의 위치와 형태를 관찰하고, 사용된 buffer 또는 ray query의 정보 범위와 연결한다.
4. RT 확률적 효과는 동일한 정적 카메라에서 TAA 누적 전후를 함께 관찰하여 noise와 수렴 경향을 구분한다.
5. 각 Phase의 결과를 ‘관찰 현상, 파이프라인 원인, 대응 방식의 차이, 결론’ 형식으로 정리한다.

권장 실험 변수는 다음과 같다.

| 실험 | 독립 변수 | 관찰 항목 |
|---|---|---|
| Shadow Map | 512, 1024, 2048 해상도 / bias | aliasing, acne, peter-panning |
| PCSS | blocker/filter sample, max radius | penumbra, over-blur |
| Shadow Ray | 1, 4, 16, 64 rays | noise/grid pattern, contact shadow |
| Reflection | depth 0, 1, 2, 4 | 반사 누락, 재귀 깊이에 따른 표현 범위 |
| Glossy | roughness, frame accumulation | blur 정확도, noise, 수렴 |
| GI | bounce 1/2, 누적 frame | color bleeding, 위치별 차폐, noise, 수렴 |

카메라 프리셋 전환은 변수 조절용 좌우 방향키와 충돌하지 않도록 상하 방향키로 분리하였다. 이를 통해 roughness 또는 광원 계수를 변경하는 동안 동일 카메라 구도를 유지할 수 있다.

---

# 4. 단계별 구현 및 비교 실험

## 4.1 Phase 0. Legacy Analysis: DXR Sample 구조 분석

### 4.1.1 목표

Phase 0의 목표는 기존 MiniEngine과 DXR sample의 렌더링 흐름을 이해하고, 이후 비교 실험을 추가할 수 있는 변경 지점을 식별하는 것이다. 분석 대상은 raster scene pass, depth/shadow pass, post effect, raytracing state object, acceleration structure, shader table, root signature 및 constant buffer 전달 경로이다.

### 4.1.2 주요 분석 내용

Raster 경로는 scene geometry를 vertex/pixel shader로 렌더링하고, depth 및 color target을 후속 pass에서 사용한다. DXR 경로는 동일 모델의 vertex/index buffer를 BLAS에 등록하고, instance transform을 포함한 TLAS를 구성한다. Ray generation shader는 camera ray를 생성하고, closest-hit shader는 material 및 texture를 읽어 shading을 수행한다.

이 과정에서 Raster와 DXR은 동일 장면을 사용하더라도 데이터 접근 방식이 다르다는 점을 확인하였다. Raster는 draw call과 root parameter를 중심으로 material state를 전달하지만, DXR은 shader record, geometry index, instance 및 hit group을 통해 데이터를 연결한다. 따라서 두 경로의 비교를 위해서는 geometry/material ID와 transform의 정합성을 명시적으로 유지해야 한다.

### 4.1.3 학습 및 발생 문제

Phase 0에서 확인한 대표적인 통합 문제는 다음과 같다.

- MiniEngine matrix와 DXR instance transform의 행·열 우선 표현 차이
- BLAS geometry 순서와 hit shader material ID 연결
- raster vertex normal과 RT procedural normal 불일치
- root signature의 descriptor register 및 resource binding 정합성
- shader payload 크기와 recursion depth 설정
- UAV/SRV 사용 전 resource state transition

이 단계는 이후 실험의 기반이며, 최종 결과 이미지보다 엔진 데이터 흐름을 이해하는 데 의미가 있다.

## 4.2 Phase 1. Experimental Environment: Cornell Style Scene 구축

### 4.2.1 목표

Phase 1의 목표는 래스터 근사의 실패 조건과 RT 질의의 차이를 반복적으로 관찰할 수 있는 통제 장면을 구축하는 것이다.

### 4.2.2 구현

기존 sample scene에 procedural surface를 추가하여 바닥, 좌우 벽, 후면 벽, 천장, 면광원 및 박스를 구성하였다. Raster 경로는 vertex/index buffer와 procedural material ID를 사용하고, RT 경로는 동일 geometry를 acceleration structure에 등록한다. Helmet 모델은 복잡한 형상과 texture material을 대표하며, 박스는 shadow 및 reflection 경로를 명확히 구성하기 위해 사용한다.

카메라 프리셋은 단순한 구도 저장 기능을 넘어 artifact 재현 장치로 구성하였다. 정면 비교, 그림자 접촉부, SSR screen edge, off-screen object, depth discontinuity, reflection depth, glossy reflection 및 GI color bleeding을 관찰하는 위치를 제공한다.

Hard shadow 비교를 시작하기 전에는 기존 장면을 Cornell Box 비율에 가깝게 축소하고, 후면의 청색 표면을 백색으로 변경하였다. 그림자와 접촉부가 한 화면에 들어오는 고정 카메라를 구성하고, 발표용 출력 해상도와 기본 Raster 모드를 설정했으며, performance overlay를 비활성화하여 시각적 교란을 줄였다. 또한 shadow map 고유의 단일 깊이 비교 결과를 관찰하기 위해 초기 baseline에서는 9-tap PCF를 비활성화하고 단일 `SampleCmpLevelZero` 비교를 사용하였다.

### 4.2.3 발생 문제와 해결

장면 구축 과정에서 Raster와 RT 결과의 seam, 벽-바닥 접촉부 누락 및 면 방향 차이가 발생하였다. 원인은 기하 범위가 정확히 맞닿을 때 발생하는 부동소수점 오차, shadow/ray epsilon, winding order 및 back-face culling 차이였다. 바닥 범위 확장, 벽과 박스의 미세한 하향 이동, raster/RT normal 동기화 및 적절한 bias 조정을 통해 문제를 완화하였다.

이 경험은 동일한 수학적 장면을 정의하는 것만으로 두 pipeline의 결과가 자동으로 일치하지 않으며, 각 pipeline이 사용하는 가시성 규칙과 수치 오차를 함께 관리해야 함을 보여준다.

## 4.3 Phase 2. Visibility/Shadow: Shadow Map vs Shadow Ray

### 4.3.1 실험 목적

Phase 2에서는 한 표면이 광원에서 보이는지를 판정하는 가장 기본적인 visibility 문제를 비교한다. Raster 방식은 shadow map을 사용하고, RT 방식은 shadow ray를 사용한다.

### 4.3.2 Shadow Map 경로

Shadow map 경로는 광원 중심을 shadow camera로 사용하여 장면을 먼저 rasterize하고, 광원에 가장 가까운 표면의 깊이를 shadow map에 기록한다. 본 엔진은 Reverse-Z를 사용하므로 depth test와 comparison sampler가 `GREATER_EQUAL`로 설정된다. 즉 더 큰 깊이값을 광원에 가까운 표면으로 판정하여 기록하며, camera pass에서는 현재 표면의 light-space 깊이를 shadow map의 값과 비교한다. 비교를 통과하면 빛을 받고, 저장된 표면보다 뒤에 있으면 다른 물체에 가려진 그림자로 판정한다.

Shadow map 생성은 rasterization 규칙의 영향을 받는다. 초기 실험에서는 shadow pass의 back-face culling 때문에 일부 벽면과 절차적 표면이 shadow caster에서 제외되어 그림자가 누락되었다. Shadow pass에 `RasterizerShadowTwoSided`를 적용하여 culling을 제거한 뒤 벽면과 양면 geometry의 그림자가 복구되었다. 이는 camera에서 보이는 표면이라도 shadow camera의 rasterizer가 해당 면을 제거하면 shadow map에는 존재하지 않는다는 점을 보여준다.

Depth bias는 Reverse-Z shadow map의 깊이를 이동시켜 자기 그림자를 억제하지만, 접촉 정확도와 self-shadowing 사이의 trade-off를 만든다. 초기 공통 shadow rasterizer 값인 `DepthBias=-100`, `SlopeScaledDepthBias=-1.5`에서는 그림자가 물체에서 떨어져 보이는 Peter Panning이 두드러졌다. Bias를 `-1`, `0.0`에 가깝게 줄이면 접촉 그림자는 개선되었지만 표면이 자기 자신을 가리는 Shadow Acne가 발생하였다. 여러 값을 비교한 결과 현재 실험 환경에서는 `DepthBias=-16`, `SlopeScaledDepthBias=0.0`을 중간값으로 사용하였다.

Shadow map 해상도를 512로 낮춘 실험에서는 texel 경계가 드러났지만, 충분히 높은 2048×2048 해상도에서는 계단 현상보다 bias와 culling에 의한 접촉부 차이가 더 두드러졌다. 따라서 본 Phase의 핵심 관찰 대상은 해상도 자체보다 Peter Panning, Shadow Acne 및 shadow caster 누락으로 설정하였다.

### 4.3.3 Shadow Ray 경로

Shadow ray 경로는 primary hit point에서 광원 위치까지 유한 길이의 광선을 발사한다. Payload의 `RayHitT`를 `FLT_MAX`로 초기화하고, closest-hit에서 `RayTCurrent()`를 기록한다. Trace 이후 `RayHitT < FLT_MAX`이면 광원까지 장애물이 존재하므로 그림자, 초기값이 유지되면 경로가 열려 있으므로 빛을 받는 것으로 판정한다. `RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH`를 사용하여 첫 장애물을 찾은 즉시 탐색을 종료하므로, hard shadow visibility에는 가장 가까운 표면의 전체 shading 결과가 필요하지 않다.

RT에서도 자기 교차를 방지하기 위한 ray origin offset과 `TMin` epsilon이 필요하다. 초기 `TMin=0.1`은 현재 표면 근처의 실제 occluder까지 건너뛰어 바닥-박스 및 바닥-벽 접촉부에 Peter Panning과 유사한 흰 틈을 만들었다. Epsilon을 `1e-5`로 줄이고 일반 mesh와 procedural geometry에 동일한 origin offset 및 `TMin` 기준을 적용한 뒤 접촉부 visibility가 복원되었다.

Shadow ray의 epsilon은 shadow map의 depth comparison 오차를 보정하는 bias가 아니라, ray가 출발 표면과 즉시 재교차하는 것을 방지하기 위한 world-space 거리이다. 본 실험에서는 적절한 epsilon을 사용한 RT 결과에서 Shadow Acne가 관찰되지 않았지만, epsilon이 지나치게 작거나 normal과 geometry가 불일치하면 self-intersection에 의한 유사 artifact가 여전히 발생할 수 있다.

### 4.3.4 비교 결과 해석

Hard shadow 실험에서 관찰한 단계별 현상은 다음과 같다.

| 실험 조건 | 관찰 현상 | 파이프라인 원인 | 조치 |
|---|---|---|---|
| Shadow caster culling 활성 | 일부 벽면 그림자 누락 | shadow camera rasterization에서 면 제거 | shadow pass two-sided rasterizer 적용 |
| Shadow map bias 과대 | Peter Panning, 접촉 그림자 분리 | 저장 depth가 receiver에서 과도하게 이동 | bias 감소 |
| Shadow map bias 과소 | Shadow Acne | receiver와 caster의 제한된 depth 정밀도 및 자기 비교 | 중간 bias 설정 |
| Shadow map 512×512 | 그림자 경계 texel화 | 제한된 light-space texture 해상도 | 해상도 증가 또는 filtering |
| Shadow ray `TMin=0.1` | 접촉부 흰 틈과 occluder 누락 | ray 시작 구간이 실제 가림 물체를 건너뜀 | epsilon을 `1e-5`로 감소 |
| Shadow ray epsilon 통일 | 바닥-벽 및 바닥-박스 접촉 복원 | mesh/procedural 경로가 동일한 visibility 규칙 사용 | 공통 origin offset 및 `TMin` 유지 |

Shadow map의 오차는 광원 시점의 depth texture와 rasterizer 상태가 실제 visibility를 충분히 표현하지 못할 때 발생한다. 해상도, culling 및 bias가 모두 최종 판정에 관여하며, 특히 bias 조정에는 Peter Panning과 Shadow Acne 사이의 균형점이 필요했다. 반면 shadow ray는 실제 geometry와의 교차 여부를 질의하므로 texture 해상도와 shadow camera culling에 의존하지 않았고, 접촉부와 코너에서 더 직접적인 visibility를 제공하였다.

그러나 RT가 수치 문제를 완전히 제거하는 것은 아니다. Shadow map의 핵심 조정값이 depth bias라면 shadow ray의 핵심 조정값은 world-space epsilon이다. 두 값 모두 자기 교차를 피하기 위해 사용되지만, shadow map bias는 저장·비교되는 깊이를 이동시키며 shadow ray epsilon은 ray의 유효 시작 구간을 이동시킨다는 차이가 있다.

### 4.3.5 결과 작성용 문장

> Shadow map은 광원 시점의 depth texture를 재사용하여 효율적으로 hard shadow를 생성했지만, shadow caster culling과 depth bias에 따라 그림자 누락, Peter Panning 및 Shadow Acne가 발생하였다. Shadow ray는 hit point와 광원 사이의 실제 geometry 교차를 검사하여 접촉부 visibility를 직접 복원하였으며, 적절한 `1e-5` epsilon 조건에서는 본 실험의 Shadow Acne가 관찰되지 않았다. 다만 과도한 epsilon은 가까운 occluder를 건너뛰어 Peter Panning과 유사한 흰 틈을 만들 수 있으므로, RT 역시 수치적 시작점 조정이 필요하였다.

## 4.4 Phase 3. Visibility(area)/Soft Shadow: PCSS vs Area Light Sampling

### 4.4.1 실험 목적

Phase 3에서는 면광원에 의해 생성되는 soft shadow를 비교한다. Raster 경로는 PCSS를 사용하고, RT 경로는 면광원 위의 여러 위치로 shadow ray를 발사한다.

실험 장면은 천장 면광원이 lit 영역, 완전히 가려진 umbra, 광원의 일부만 보이는 penumbra가 한 화면에서 드러나도록 카메라와 차폐물 위치를 조정하였다. 이 과정에서 조명과 무관한 ambient 성분이 남아 있으면 그림자 대비를 판독하기 어려웠으므로 directional/ambient 기여를 최소화하고, visible emissive panel과 실제 면광원 중심의 높이를 동일하게 맞췄다. 패널은 광원의 시각적 표현이며, 실제 직접광과 shadow 계산은 패널 중심 주변의 별도 sample 위치를 사용한다.

Ambient를 0으로 설정했는데도 장면이 밝게 보이는 문제는 MiniEngine의 `ExpVar` 동작과 관련되어 있었다. `ExpVar`는 입력값의 `log2`를 지정 범위로 제한한 뒤 읽을 때 `exp2`를 반환한다. 따라서 최소 지수값이 0이면 실제 최소값은 `exp2(0)=1`이며 완전히 끌 수 없다. Ambient 최소 지수 범위를 -16으로 변경하면 0 입력은 약 `2^-16` 수준으로 낮아져 그림자 비교에 미치는 영향을 사실상 제거할 수 있었다. 이 문제는 렌더링 artifact처럼 보이는 현상이 실제로는 엔진 tuning variable의 값 표현 방식에서 발생할 수 있음을 보여준다.

### 4.4.2 PCSS 구현

Raster 경로에서는 방향광 기반 직교 shadow camera 대신 천장 면광원 중심에 원근 shadow camera를 배치하였다. 면광원의 모든 위치를 하나의 shadow map에 직접 저장할 수는 없으므로, 광원 중심에서 생성한 단일 shadow map을 기준으로 penumbra를 근사한다.

현재 PCSS 구현은 8×8 고정 grid를 disk 형태로 변환하여 blocker search와 filtering에 각각 64개 sample을 사용한다. 먼저 shadow map 주변에서 receiver보다 광원에 가까운 blocker를 탐색하고 평균 blocker 거리를 계산한다. 이후 receiver와 blocker 거리 차이로 penumbra ratio를 추정하고, 그 결과에 따라 PCF filter 반경을 동적으로 조절한다.

PCF와 PCSS의 역할은 구분할 필요가 있다. PCF는 고정된 filter 반경에서 여러 depth comparison 결과를 평균하여 hard shadow 경계를 부드럽게 보이게 한다. 반면 PCSS는 blocker 거리를 이용하여 filter 반경 자체를 변화시키므로 접촉부는 날카롭고 멀어질수록 넓어지는 physically plausible penumbra를 근사한다. 즉 PCF는 PCSS의 마지막 filtering 단계로 사용되며, PCSS의 거리 기반 penumbra 추정을 단독으로 제공하지는 않는다.

PCSS는 단일 shadow map만으로 접촉부에서 날카롭고 멀어질수록 부드러운 그림자를 표현할 수 있었다. 그러나 광원 중심 시점의 shadow map 하나만 사용하므로, 광원 전체에서의 실제 가시성을 직접 계산하지 않는다. Raster 직접광은 면광원 주변의 4개 대표 위치를 평가하지만, 그림자 visibility는 중심 shadow map에서 계산한 하나의 PCSS 값을 공유한다. 따라서 PCSS/PCF sample 수를 16에서 64로 늘리면 filter의 이산성은 감소하지만, 중심 투영에서 비롯된 과도한 암부와 형태 오차는 제거되지 않았다.

초기 구현에서는 평균 blocker와 원형 filter의 반경이 과도하게 증가하여 penumbra가 실제보다 넓어지고 그림자 외곽이 둥글게 팽창하는 over-blur 또는 shadow bleeding이 관찰되었다. 이를 완화하기 위해 blocker와 receiver의 최소 분리 거리를 적용하고, 최종 filter 반경을 blocker search 범위와 최대 PCSS 반경 안으로 제한하였다. PCSS는 이러한 안정화 이후에도 shadow map의 bias, 해상도 및 중심 투영 오차를 상속한다.

### 4.4.3 RT 면광원 샘플링 구현

RT 경로는 hit point에서 면광원 영역의 여러 위치까지 shadow ray를 발사하고, 보이는 sample의 비율을 visibility로 사용한다. 이 값이 0이면 umbra, 1이면 완전한 lit 영역이며, 그 사이 값은 광원의 일부만 보이는 penumbra를 나타낸다.

샘플링 방식은 4-ray 고정 grid에서 시작하였다. 4개 sample의 평균은 visibility가 0, 0.25, 0.5, 0.75, 1의 다섯 단계로만 표현되어 penumbra는 나타났지만 부드럽지 않았다. 16개와 64개로 증가하면 단계 수는 늘었지만, 모든 pixel이 정렬된 동일 grid를 사용하여 그림자 경계에 coherent band와 grid pattern이 나타났다.

이를 줄이기 위해 최종 구현은 각 pixel 위치를 hash하여 얻은 각도로 8×8 고정 grid를 회전한다. 회전된 sample은 사각형 광원 영역 내부로 다시 배치하며, 총 64개의 shadow ray를 발사한다. 픽셀별 회전은 sample 수를 증가시키지 않고 공간적으로 반복되는 경계선을 분산시켰다. 완전한 stochastic sample도 실험하였으나 전형적인 고주파 noise와 temporal jitter가 크게 나타나, 안정적인 비교 이미지를 위해 per-pixel rotated fixed grid로 되돌렸다.

RT 방식은 실제 면광원 sample 위치 각각에 대한 visibility를 직접 검사하므로 차폐물과 receiver의 기하 관계에 따른 penumbra를 생성한다. 반면 pixel당 64개의 traversal이 필요하며, 유한 sample에 의한 양자화 또는 pattern을 완전히 제거하지는 못한다.

### 4.4.4 비교 결과 해석

Soft shadow 실험의 단계별 관찰 결과는 다음과 같다.

| 실험 조건 | 관찰 현상 | 원인 및 해석 |
|---|---|---|
| Ambient 최소 지수 0 | 조명 세기를 0으로 설정해도 장면이 밝음 | `ExpVar`의 실제 최소값이 1로 제한됨 |
| Emissive panel과 광원 높이 불일치 | 패널 색과 조명 위치가 시각적으로 어긋남 | 보이는 발광체와 실제 sample 중심이 다름 |
| RT 4-ray fixed grid | 다섯 단계의 거친 penumbra | 보이는 광원 sample 수가 0~4로 양자화됨 |
| RT 16/64-ray fixed grid | 경계선 및 grid pattern | 정렬된 sample pattern이 공간적으로 반복됨 |
| RT per-pixel rotated 64-ray grid | 반복 경계 감소, 비교적 안정된 penumbra | pixel별 sample 방향 decorrelation |
| RT stochastic sampling | 고주파 noise와 temporal jitter | 무작위 sample의 높은 variance |
| PCSS 64+64 samples | 접촉부에서 날카롭고 멀수록 부드러운 경계 | blocker 거리 기반 가변 PCF 반경 |
| PCSS filter 반경 과대 | over-blur, shadow bleeding, 둥근 팽창 | 단일 중심 shadow map과 평균 blocker 기반 반경 추정 |

PCSS의 soft shadow는 blocker 거리로 filter 크기를 추정한 결과이며, 광원 면적의 가시성을 직접 계산한 결과가 아니다. 따라서 낮은 비용으로 plausible penumbra를 생성하지만, 중심 shadow camera에서 보이지 않는 정보와 복잡한 blocker 구성을 복원할 수 없으며 실제 면광원보다 그림자가 과도하게 확장될 수 있다.

RT 면광원 sampling은 광원 표면의 visibility 적분 자체를 유한 sample로 근사한다. Sample 수가 충분할수록 실제 soft shadow에 접근하지만, 비용과 variance가 증가한다. 이 비교는 래스터 근사의 오차와 RT 샘플링 오차가 서로 다른 성격을 가짐을 보여준다. PCSS의 오차는 단일 shadow map 표현과 heuristic penumbra 계산에서 발생하고, RT의 오차는 유한 sample의 양자화, pattern 및 variance에서 발생한다.

### 4.4.5 결과 작성용 문장

> PCSS는 광원 중심에서 생성한 단일 shadow map의 blocker depth를 이용하여 PCF 반경을 동적으로 조절함으로써 접촉부는 날카롭고 멀어질수록 부드러운 penumbra를 근사하였다. 그러나 평균 blocker와 제한된 투영 정보로 인해 그림자가 실제보다 넓고 둥글게 팽창하는 over-blur가 발생할 수 있었다. 반면 면광원 영역에 대한 64개의 shadow ray는 실제 가시 sample 비율을 계산하여 기하 관계에 따른 penumbra를 생성했으나, 고정 grid에서는 반복 경계가, stochastic sample에서는 noise가 나타나 최종적으로 per-pixel rotated grid를 사용하였다.

## 4.5 Phase 4. PBR Lighting: Legacy Lighting vs PBR

### 4.5.1 단계의 역할

Phase 4는 단순히 legacy lighting보다 PBR이 더 사실적임을 보이기 위한 단계가 아니다. 이후 shadow, reflection 및 GI 비교에서 두 경로가 동일한 표면 반응을 사용하도록 만드는 통제 단계이다.

### 4.5.2 Legacy 재질 경로 진단

초기 FlightHelmet 렌더링에서 금속과 가죽의 차이가 약하고 specular가 사실상 나타나지 않는 현상을 확인하였다. 이는 BRDF 자체보다 재질 데이터가 셰이더까지 전달되는 경로의 문제였다. H3D 재질은 BaseColor, Specular, Normal의 세 texture reference를 가지지만, 실제 FlightHelmet 자산은 두 번째 슬롯에 대응하는 legacy specular texture 대신 `*_OcclusionRoughMetal.dds`를 제공한다. 기존 loader는 이 파일명을 탐색하지 않아 두 번째 슬롯을 검은 fallback texture로 채웠다.

이 오류는 두 렌더링 경로에서 서로 다른 형태로 이어졌다. Raster 경로는 검은 두 번째 texture의 채널을 specular mask로 사용하여 specular 기여가 0이 되었고, RT 경로는 local root signature가 diffuse와 normal에 해당하는 `t6`, `t7`만 노출한 상태에서 hit shader의 specular mask도 0으로 고정되어 있었다. 따라서 초기 결과는 metallic, roughness 및 texture AO를 반영하지 못했으며, 모든 재질이 유사한 표면 반응을 보였다.

### 4.5.3 ORM 데이터 경로 복구

`ModelH3D::LoadTextures()`에 BaseColor 파일명으로부터 `*_OcclusionRoughMetal.dds`를 유도하는 fallback을 추가하였다. 복구된 ORM texture는 glTF 관례에 따라 R=AO, G=Roughness, B=Metallic으로 해석하였다. Raster pixel shader는 기존 `t1`에서 ORM을 읽으며, texture AO와 SSAO를 곱해 재질 내부 차폐와 화면 공간 차폐를 함께 반영한다.

RT 경로에서는 local descriptor range를 두 개에서 세 개로 확장하여 `t8`에 ORM을 추가하고, material descriptor table에도 diffuse, normal, ORM 순서로 SRV를 배치하였다. Descriptor table이 가리키는 descriptor 수가 증가하더라도 shader record에는 동일한 GPU descriptor handle 하나가 저장되지만, local root signature, shader table 구성 및 hit shader register 선언이 동시에 일치해야 한다. 이 과정은 같은 texture 자산을 사용하더라도 Raster와 RT의 resource binding 구조가 다르므로 한쪽 수정만으로는 동일한 재질 결과를 얻을 수 없음을 보여준다.

### 4.5.4 공통 Cook-Torrance 평가

공통 `PBR.hlsli`에 GGX normal distribution, Smith geometry term, Fresnel-Schlick 및 Cook-Torrance 평가 함수를 구성하였다. Raster pixel shader와 RT closest-hit shader는 각각의 visibility 결과를 구한 뒤 동일한 `EvaluatePBR` 함수를 호출한다. Metallic workflow에서는 diffuse 기여를 `baseColor * (1-metallic)`으로 억제하고, normal incidence reflectance인 F0를 `lerp(0.04, baseColor, metallic)`으로 계산한다. Roughness는 GGX 분포와 geometry term에 사용된다.

Roughness가 0에 가까우면 GGX 분모가 매우 작아져 specular가 폭증할 수 있으므로 최소값 0.04와 분모 하한을 적용하였다. 또한 현재 diffuse 항은 기존 장면의 광원 세기를 유지하기 위해 Lambertian의 `1/PI` 정규화를 생략하였다. 따라서 본 구현은 metallic/roughness에 따른 상대적인 표면 반응과 Raster/RT 정합성을 제공하지만, 절대적인 radiometric calibration까지 완료한 참조 path tracer는 아니다.

직접광이 없는 영역의 metallic 표면이 완전히 검게 되는 것을 막기 위해 `AmbientPBR`은 diffuse와 specular의 단색 ambient 기준값을 제공한다. 이는 완전한 image-based lighting이 아니라 실험 장면을 위한 placeholder이므로, visibility 비교에서는 ambient를 통제하고 environment lighting을 사용하는 후속 단계와 구분하였다.

### 4.5.5 절차적 재질과 실험 모드 통제

FlightHelmet은 BaseColor, Normal, ORM texture를 통해 재질 값을 얻고, Cornell 스타일의 절차적 표면은 material ID로 값을 선택한다. 두 데이터 경로는 다르지만, 공통 `ProceduralMaterial.hlsli`와 `PBR.hlsli`를 통해 Raster와 RT가 동일한 재질 파라미터와 BRDF 평가를 사용한다.

최종 장면에서는 벽과 천장을 비금속 고 roughness 기준면으로 유지하고, 바닥과 Box A 및 Box B에는 reflection과 glossy reflection 실험을 위한 metallic 재질을 배치하였다. 반면 GI 비교 모드에서는 emissive panel을 제외한 재질의 metallic을 0으로 만들고 roughness를 최소 0.9로 높인다. 이는 초기 설계의 별도 mirror plate 제안이 이후 mirror box와 모드별 재질 정책으로 발전한 결과이며, reflection 실험과 diffuse GI 실험이 서로의 재질 조건을 오염시키지 않게 한다.

### 4.5.6 디버그 뷰와 검증

AO, Roughness, Metallic 및 world normal을 직접 출력하는 공통 debug view를 추가하였다. Metallic view에서 헬멧의 금속 부품은 밝고 가죽 부품은 어둡게 나타나야 하며, Roughness view에서는 표면별 광택 차이가 명확해야 한다. 이 검증은 최종 조명 결과만 보아서는 구분하기 어려운 ORM 채널 순서 오류와 texture loading 실패를 먼저 분리해 낸다.

동일한 debug view에서도 Raster와 RT 결과가 다르면 ORM 채널보다 normal 변환, TBN 구성 또는 view direction 부호를 우선 확인해야 한다. 또한 검은 ORM fallback으로 AO가 0이 되는 경우를 막기 위한 최소 ambient guard는 안전장치일 뿐이며, 올바른 texture loading을 대신하지는 않는다.

| 관찰 또는 문제 | 파이프라인 원인 | 반영한 해결 |
|---|---|---|
| Helmet의 specular가 사라지고 재질 차이가 약함 | ORM 파일을 찾지 못해 두 번째 material texture가 검은 fallback으로 대체됨 | BaseColor 이름으로부터 ORM 경로를 유도 |
| RT에서 ORM을 사용할 수 없음 | Local root signature와 shader table이 diffuse/normal 두 SRV만 제공 | descriptor range를 세 개로 확장하고 `t8`에 ORM 바인딩 |
| Raster와 RT의 표면 반응이 다름 | 각 경로의 재질 lookup과 lighting 함수가 분리됨 | 공통 procedural material table과 `EvaluatePBR` 사용 |
| 낮은 roughness에서 과도한 highlight 가능 | GGX 분모의 수치 불안정 | roughness 및 분모 하한 적용 |
| 최종 색만으로 오류 원인을 구분하기 어려움 | material data, normal 및 lighting 오류가 합성 결과에 함께 나타남 | AO/Roughness/Metallic/Normal debug view 추가 |

### 4.5.7 비교 결과 해석

Legacy lighting과 PBR의 차이는 본 논문의 최종 비교 대상이면서 동시에 실험 오염 요인이다. 따라서 Phase 4 이후에는 PBR을 공통 기준으로 사용하고, legacy 결과는 엔진 변경 전후의 shading 구조 차이를 설명하는 보조 실험으로 제시한다.

이 단계의 핵심 결과는 PBR 수식을 추가했다는 사실보다, 재질 자산이 loader, descriptor, shader register 및 BRDF 평가를 거쳐 두 파이프라인에 동일하게 도달하도록 만든 것이다. 이후 shadow와 reflection 비교에서 나타나는 차이를 visibility 방식의 차이로 해석하려면 먼저 이러한 material 및 shading 조건이 통제되어야 한다.

## 4.6 Phase 5. Reflection: SSR vs Reflection Ray

### 4.6.1 실험 목적

Phase 5에서는 반사 방향에서 장면 정보를 찾는 방법을 비교한다. Raster 경로는 SSR을 사용하고, RT 경로는 reflection ray를 사용한다.

### 4.6.2 SSR 실패 조건

SSR은 현재 화면 buffer에 존재하는 정보만 사용할 수 있다. 본 연구에서는 다음 세 가지 artifact를 관찰하기 위한 카메라 프리셋을 구성하였다.

1. **Screen-edge cutoff:** 반사 ray가 화면 경계를 벗어나면서 반사가 갑자기 사라진다.
2. **Off-screen missing:** 반사되어야 하는 물체가 현재 카메라 화면 밖에 있어 결과에 나타나지 않는다.
3. **Depth discontinuity:** ray march가 박스 모서리와 같은 급격한 depth 변화 구간을 통과하며 잘못된 교차 또는 누락을 생성한다.

각 artifact의 데이터 수준 원인은 다음과 같다. Screen-edge cutoff는 ray march가 UV 범위를 벗어나는 순간 반사 color 조회가 실패하고 fallback(검정 또는 배경색)으로 대체되기 때문이다. Off-screen missing은 반사되어야 할 물체가 현재 camera frustum 밖에 있어 depth/color buffer 자체에 해당 정보가 존재하지 않는다. Depth discontinuity는 ray march가 depth가 급변하는 박스 모서리 근처에서 실제 교차 표면을 건너뛰거나 잘못된 배경 depth에 조기 히트하는 것으로, step size와 두께 허용치를 조절해도 모서리 근방에서의 오판은 남는다.

이 현상들은 tuning만으로 완전히 해결하기 어렵다. SSR이 사용하는 현재 화면의 depth/color 정보에 필요한 장면이 존재하지 않기 때문이다.

### 4.6.3 Reflection Ray 구현

RT 경로는 closest-hit 위치에서 HLSL `reflect(incident, normal)` 함수로 반사 방향을 계산하고, 해당 방향으로 secondary ray를 발사한다. Reflection ray는 TLAS 전체를 질의하므로 화면 밖 물체와 가려진 기하를 찾을 수 있다.

자기 교차를 방지하기 위해 shadow ray와 동일하게 작은 world-space epsilon을 TMin에 적용하였다. Epsilon이 지나치게 크면 발사 표면 바로 앞의 실제 반사 물체를 건너뛰는 문제가 발생하므로, 반사 origin offset과 TMin을 함께 조정하였다.

재귀 구조는 payload에 현재 깊이를 전달하고, 최대 깊이에 도달하면 추가 TraceRay를 호출하지 않고 환경 기여값을 반환하도록 구성하였다. RTPSO의 `MaxTraceRecursionDepth`는 지원할 최대 깊이보다 1 이상 크게 설정해야 하며, 이 값이 작으면 런타임 오류나 블랙 결과가 발생한다. 본 실험에서는 최대 Depth 5를 지원하기 위해 `MaxTraceRecursionDepth=6`으로 설정하였다.

Mirror box 배치는 좌측 박스(Left Mirror Box)의 우측 면이 우측 박스(Right Mirror Box)를 향하고, 우측 박스의 좌측 면이 헬멧 방향을 향하도록 구성하였다. 이에 따라 `Camera → Floor → Left Box → Right Box → Helmet` 반사 체인이 구성되며, 재귀 깊이가 늘어날수록 체인의 더 깊은 단계가 화면에 나타난다. 이 장면은 reflection depth가 단순 성능 파라미터가 아니라 표현 가능한 광로의 길이를 결정함을 보여준다.

### 4.6.4 발생 문제

다중 반사 구현에서 발생한 문제와 조치는 다음과 같다.

| 발생 조건 | 관찰 현상 | 파이프라인 원인 | 조치 |
|---|---|---|---|
| Raster geometry와 RT procedural normal 불일치 | 박스 면 경계에서 반사 결과가 Raster와 RT 사이에 어긋남 | Raster 삼각형 법선과 RT procedural 법선이 다른 방향을 사용 | RT procedural normal을 Raster geometry 기준에 맞춰 통일 |
| 거울 면 방향 설정 오류 | 반사 경로가 예상 대상을 향하지 않음 | 박스 면의 법선 방향이 반사 대상을 가리키지 않음 | 박스 위치와 각 면의 법선 방향을 재배치 |
| `MaxTraceRecursionDepth` 부족 | 깊은 재귀 설정 시 블랙 출력 또는 런타임 오류 | RTPSO 재귀 한도 초과 | `MaxTraceRecursionDepth`를 사용할 최대 Depth보다 1 이상 크게 설정 |
| Ray origin epsilon 과소 | 발사 표면과 재교차하는 self-intersection artifact | reflection ray가 출발한 표면과 즉시 교차 | TMin epsilon을 shadow ray와 동일 수준으로 조정 |
| Ambient와 reflection contribution 혼용 | Metallic 표면에 ambient가 포함되어 순수 반사 비교 불가 | ambient specular baseline이 reflection color와 합산됨 | Reflection 모드에서 ambient 기여를 통제하여 분리 관찰 |
| Primary ray 화면과 reflection mode 화면 혼동 | 모드 전환 시 의도하지 않은 결과 출력 | UI 없이 두 모드를 구분하기 어려움 | 화면 overlay에 현재 Reflection Depth 및 모드 표시 추가 |

### 4.6.5 비교 결과 해석

SSR artifact 실험에서 관찰한 단계별 현상은 다음과 같다.

| 실험 조건 | 관찰 현상 | 파이프라인 원인 | 비고 |
|---|---|---|---|
| SSR: 반사 대상이 화면 밖 | 반사가 갑자기 사라지거나 검정으로 대체됨 | color/depth buffer에 해당 물체 정보 없음 | 카메라를 이동해도 SSR로 복원 불가 |
| SSR: 반사 ray가 화면 경계 도달 | 경계 방향으로 갈수록 반사가 점차 끊김 | UV 범위 이탈 시 buffer 조회 실패 | edge fade 처리로 완화 가능하나 구조적 누락은 유지 |
| SSR: 박스 모서리 근처 | 잘못된 교차 또는 조기 히트로 반사가 왜곡됨 | ray march가 depth discontinuity를 가로질러 오판 | step size 감소로 부분 완화, 근본 해결 불가 |
| Reflection Ray Depth 2 | 벽과 그림자가 주로 반사됨, 헬멧 정보 없음 | 1회 반사만 가능한 광로 길이 | 반사 체인의 첫 단계만 열림 |
| Reflection Ray Depth 3 | 좌측 박스 우측면에 우측 박스가 보이기 시작 | 2회 반사 광로 열림 | 바닥-박스 간 재귀 반사 더 명확해짐 |
| Reflection Ray Depth 5 | 좌측 박스 우측면에 헬멧 반사 등장, 바닥에 전체 체인 완성 | 4회 반사로 Camera→Floor→Left Box→Right Box→Helmet 경로 완성 | Depth 5 이상은 헬멧이 순수 거울이 아니므로 추가 변화 없이 수렴 |

SSR의 artifact는 screen-space 정보가 구조적으로 불완전하기 때문에 발생한다. 화면에 존재하지 않는 정보는 step size, 반복 횟수, edge fade 등을 조정해도 복원할 수 없다. Reflection ray는 월드 공간 장면을 직접 질의하여 이 구조적 누락을 해결하며, 재귀 깊이를 통해 표현 가능한 반사 체인의 길이를 제어한다.

그러나 RT에서도 표현 가능성은 재귀 깊이로 제한되며, 깊이가 늘어날수록 ray 발사와 hit shading 비용이 증가한다. 또한 완전한 거울 재질이 아닌 rough surface에서는 하나의 deterministic ray만으로 충분하지 않아 Glossy Reflection 단계(Phase 6)가 필요하다. 4.6.7의 Depth별 관찰 결과에 따르면 본 실험 장면에서는 Depth 5 부근에서 반사 정보가 수렴하며, 그 이상의 재귀 비용은 시각적 이득 없이 연산만 늘린다.

### 4.6.6 결과 작성용 문장

> SSR에서 관찰된 screen-edge cutoff, off-screen missing, depth discontinuity artifact는 ray marching 정밀도보다 color/depth buffer에 필요한 장면 정보 자체가 존재하지 않기 때문에 발생하였다. Reflection ray는 TLAS를 통해 화면 밖 기하를 탐색하여 이 구조적 누락을 해결하였다. 재귀 깊이 2에서는 1회 반사까지만 열려 벽과 그림자가 주로 반사되었으나, Depth 5에서는 `Camera → Floor → Left Box → Right Box → Helmet` 체인이 완성되어 헬멧 반사가 바닥과 좌측 박스 우측면에 나타났다. 본 실험 장면에서 반사 결과는 Depth 5 부근에서 수렴하였으며, 그 이상의 재귀 깊이는 추가적인 시각적 변화 없이 비용만 증가하였다.

### 4.6.7 Depth별 반사 관찰 결과

Reflection Depth를 단계별로 증가시키면서 각 Depth에서 관찰된 반사 패턴을 정리한다. 실험 Scene은 좌측 박스(Left Mirror Box)가 우측 박스(Right Mirror Box)를 향하고, 우측 박스가 헬멧을 향하도록 배치하여 `Camera → Floor → Left Box → Right Box → Helmet` 반사 체인을 구성하였다.

**Depth 2 (1회 반사):**

좌측 박스 좌측면은 주로 왼쪽 녹색 벽과 이동의 그림자 영역을 반사한다. 좌측 박스 우측면은 아직 우측 박스 영역에 도달하지 못하므로 이동의 벽/일부만 보인다. 우측 박스 좌측면과 우측면도 대부분 벽과 그림자만 보이며, 헬멧 정보는 거의 나타나지 않는다. 바닥은 거울 반사로 박스 실루엣과 관련 반사를 일부 보여주지만, 반사 체인이 짧아 헬멧까지는 보이지 않는다.

**Depth 3 (2회 반사):**

좌측 박스 좌측면은 여전히 녹색 벽 중심이라 변화가 없다. 좌측 박스 우측면에는 우측 박스가 보이기 시작하므로 Depth 2보다 정보량이 늘어난다. 우측 박스 좌측면은 좌측 박스도 방 내부 일부를 반사하지만 헬멧은 아직 미약하게만 보인다. 우측 박스 우측면은 빨간 벽과 그림자 영향이 커서 변화가 있다. 바닥에는 `Floor → Left Box → Right Box` 경로가 열리면서 박스 간 재귀 반사가 더 명확해진다.

**Depth 5 (4회 반사):**

좌측 박스 좌측면은 여전히 녹색 벽을 주로 보기 때문에 Depth 증가에 따른 변화가 없다. 좌측 박스 우측면은 핵심 변화 지점으로, `Left Box → Right Box → Helmet` 경로가 열리면서 우측 박스 안에 헬멧 반사가 나타난다. 우측 박스 좌측면은 헬멧에 인접한 면이므로 헬멧 관련 반사 정보를 일부 포함하나 낮은 Depth에서도 일부 보여 변화 폭이 적다. 우측 박스 우측면은 빨간 벽과 그림자 쪽을 향해 변화가 제한된다. 바닥에는 `Floor → Left Box → Right Box → Helmet` 체인이 완성되어 헬멧 반사까지 포함되며, Depth 3보다 가장 명확한 차이를 만든다. Depth 5 이상에서는 헬멧이 완전한 거울 재질이 아니므로 추가 반사 정보가 거의 발생하지 않으며, 반사 결과는 Depth 5 부근에서 사실상 수렴하는 모습을 보였다.

## 4.7 Phase 6. Glossy Reflection: Prefiltered Environment Map vs Glossy Reflection Ray

### 4.7.1 실험 목적

Phase 6에서는 roughness가 있는 metallic 표면의 반사를 비교한다. Raster 경로는 GGX prefiltered environment cubemap을 사용하고, RT 경로는 GGX importance-sampled reflection ray를 사용한다.

### 4.7.2 Raster Glossy 경로

Raster 경로는 startup 과정에서 environment cubemap을 capture하고, GGX 분포에 따라 mip chain을 prefilter한다. Pixel shader는 reflection direction과 roughness를 사용하여 적절한 mip level을 조회한다. 이 방식은 실행 시 적은 texture lookup으로 안정적인 blur를 제공한다.

그러나 environment map은 capture 위치를 기준으로 방향별 radiance만 저장한다. 따라서 shading point의 위치 차이, 가까운 물체에 의한 parallax, 국소 차폐 및 동적 장면 변화가 정확히 반영되지 않는다. 현재 구현은 단순화를 위해 split-sum BRDF LUT를 생략하고 제한된 형태의 IBL을 사용한다.

### 4.7.3 RT Glossy 경로

RT 경로는 roughness와 surface normal을 사용하여 GGX half-vector를 importance sampling하고, 해당 방향으로 reflection ray를 발사한다. 현재 구현은 metallic hit마다 frame당 reflection ray 1개를 발사하는 1 spp/frame 방식이며, frame index 기반 sample을 TAA로 시간적으로 누적한다. Roughness가 매우 낮은 표면은 확률적 GGX sampling 대신 deterministic mirror 방향을 사용한다.

이 방식은 현재 shading point에서 실제 장면을 질의하므로 위치 종속 반사와 차폐를 반영할 수 있다. 반면 frame당 sample 수가 제한되면 noise가 발생하고, 카메라 또는 물체가 움직일 때 누적 history의 유효성이 감소한다.

### 4.7.4 비교 결과 해석

Prefiltered environment map은 radiance 적분 결과를 사전에 방향별 texture로 축약한 방식이다. RT glossy reflection은 적분을 실행 중 확률적으로 추정한다. 전자는 안정성과 효율이 강점이며, 후자는 공간 정확성과 동적 장면 대응이 강점이다.

이 단계는 혼합 렌더러의 필요성을 명확히 보여준다. 원거리 또는 낮은 중요도의 rough reflection은 prefiltered environment map으로 충분할 수 있으며, 근거리·고반사·위치 종속 표면에는 RT를 선택적으로 적용할 수 있다.

### 4.7.5 결과 작성용 문장

> Prefiltered environment map은 roughness에 따른 안정적인 glossy reflection을 낮은 실행 비용으로 제공했지만, capture 위치와 shading 위치의 차이로 인해 parallax 및 국소 차폐 오차가 발생하였다. GGX importance-sampled reflection ray는 현재 표면 위치의 실제 가시성을 반영했으나, 낮은 sample 수에서 noise가 발생하여 temporal accumulation이 필요하였다.

## 4.8 Phase 7. Global Illumination: Environment/Probe Approximation vs Path Tracing

### 4.8.1 실험 목적

Phase 7에서는 직접광 이후의 diffuse 간접광을 비교한다. Raster baseline은 prefiltered environment cubemap의 낮은 주파수 정보를 사용하고, RT 경로는 cosine-weighted diffuse secondary ray와 재귀 깊이 제어를 사용하여 1-bounce 및 2-bounce 결과를 생성한다.

### 4.8.2 Raster GI 경로

Raster GI 경로는 surface normal 방향으로 environment cubemap의 높은 mip level을 조회하여 diffuse irradiance를 근사한다. 이 방식은 안정적이고 저렴하지만, 위치 정보를 거의 사용하지 않기 때문에 같은 normal을 가진 서로 다른 위치가 유사한 간접광을 받을 수 있다. 벽 근처의 color bleeding, 물체 뒤의 차폐 및 국소적인 간접광 변화 표현에는 한계가 있다.

### 4.8.3 RT GI 경로

RT GI 경로는 diffuse 표면에서 cosine-weighted hemisphere 방향을 생성하고 secondary ray를 발사한다. Secondary hit에서 얻은 radiance를 현재 표면의 diffuse color와 결합하며, 최대 재귀 깊이를 1 또는 2로 설정하여 간접광의 전달 범위를 비교한다. Cornell 스타일 장면의 색 벽과 흰 표면을 이용하여 위치별 color bleeding과 추가 bounce에 따른 광 전달 변화를 관찰한다.

현재 구현은 각 diffuse hit에서 GI continuation ray를 1개만 생성하는 1 spp/frame progressive path tracing 구조이다. 여기서 면광원 직접광을 계산하는 64개 ray는 GI 경로를 64갈래로 분기하는 ray가 아니라, 각 shading hit에서 면광원 sample의 가시성을 확인하는 shadow ray이다. 따라서 G의 최악 조건은 primary ray 1개, primary/secondary hit의 shadow ray 각 64개, GI continuation ray 1개로 약 130회의 ray query이며, J는 두 번째 GI continuation ray가 추가되어 약 131회의 ray query가 된다. 재귀 깊이 2의 hit에서는 RTPSO 재귀 제한을 피하기 위해 추가 shadow ray 발사를 생략한다.

절차적 diffuse 표면은 1-bounce와 2-bounce를 지원하지만 textured mesh의 GI 경로는 1-bounce로 제한된다. 또한 multiple importance sampling과 production 수준 denoiser는 포함하지 않는다. 정적 카메라에서는 매 frame 다른 cosine-weighted 방향을 선택하고 TAA로 누적하여 경향을 확인할 수 있지만, 낮은 sample 수에서는 noise가 남는다.

### 4.8.4 비교 결과 해석

Environment 기반 GI는 위치 종속성을 제거하여 매우 압축된 형태의 간접광을 제공한다. RT GI는 실제 secondary visibility와 hit radiance를 사용하여 위치별 색 번짐과 차폐를 표현할 수 있다. 그러나 GI는 shadow나 mirror reflection보다 적분 차원이 높기 때문에 RT 비용과 noise 문제가 가장 크게 나타나는 단계이다.

실제 관찰에서 H는 색 벽의 영향이 장면 전체에 비교적 균일하게 퍼져 color bleeding처럼 보였지만, 이는 특정 벽과 표면 사이의 실제 전달 경로를 구분한 결과라기보다 environment irradiance가 제공하는 저주파 색조에 가깝다. G와 J는 국소 위치에 따른 색 번짐을 표현할 수 있으나 1 spp/frame의 강한 noise 때문에 누적 전 화면에서는 차이를 판독하기 어려웠다.

초기 J 실험에서는 G보다 거울 안의 거울이 더 보이는 현상이 관찰되었다. 그러나 이는 2-bounce diffuse GI의 증거가 아니라 GI 장면에 남아 있던 metallic 바닥과 Box B가 reflection 경로를 생성한 교란 요인이었다. 이후 H/G/J 모두의 비발광 재질을 rough diffuse로 통일하여 거울 반사를 제거하였다. 따라서 수정 후 J의 관찰 대상은 mirror-in-mirror가 아니라 G에 비해 추가된 두 번째 diffuse bounce가 만드는 간접광 전달 범위와 국소 색 변화이다.

그러나 재질 통제 이후에도 RT GI의 높은 sampling variance로 인해 G와 J의 국소 색 번짐 및 bounce 차이를 안정적으로 판독하기 어려웠다. 현재 결과는 RT GI가 위치 종속 간접광을 계산할 수 있다는 파이프라인 구조와 noise 발생 원인을 확인하는 데에는 유효하지만, 1-bounce와 2-bounce의 화질 차이를 최종적으로 입증하는 수렴 영상으로 사용하기에는 부족하다. 이 관찰 한계 자체를 1 spp 실시간 RT와 후처리 의존성의 사례로 기록하고, 더 높은 SPP 또는 GI 전용 denoising은 후속 연구로 남긴다.

### 4.8.5 결과 작성용 문장

> Environment irradiance 기반 raster GI는 안정적인 저주파 간접광을 제공하였으나, 위치별 차폐와 색 번짐을 구분하지 못하였다. Diffuse secondary ray는 실제 hit 위치와 재귀 경로를 사용하므로 위치 종속 color bleeding과 추가 bounce를 계산할 수 있지만, 본 구현의 1 spp/frame 결과에서는 높은 variance가 해당 차이를 가렸다. 따라서 현재 실험은 GI 질의 구조의 차이와 시간 누적의 필요성을 확인하였으며, 수렴된 1/2-bounce 화질 비교는 다중 sample 또는 denoising을 요구하는 후속 과제로 남는다.

---

# 5. 종합 분석

## 5.1 근사 기법의 공통 구조

각 Phase의 래스터 기법은 서로 다른 효과를 다루지만 공통 구조를 가진다. 필요한 월드 공간 질의를 더 작은 데이터 표현으로 변환하고, 실행 중 해당 표현을 조회한다.

- Shadow map은 광원별 visibility를 2D depth texture로 축약한다.
- PCSS는 면광원 가시성을 blocker depth와 filter radius로 축약한다.
- SSR은 반사 장면을 현재 화면 buffer로 제한한다.
- Prefiltered environment map은 위치별 반사 radiance를 방향과 roughness로 축약한다.
- Environment GI는 위치별 간접광을 낮은 주파수 방향 정보로 축약한다.

이러한 축약은 높은 효율과 안정성을 제공한다. 동시에 축약 과정에서 제거된 정보가 필요한 조건에서는 구조적인 artifact가 발생한다.

## 5.2 레이 트레이싱의 공통 구조

대응하는 RT 방식은 대부분 “현재 hit point에서 새로운 방향으로 광선을 발사하고, 장면과의 교차 결과를 사용한다”는 공통 구조를 가진다.

- Shadow ray는 구간 내 any-hit 존재 여부를 질의한다.
- Area-light shadow ray는 여러 광원 sample에 대한 visibility를 적분한다.
- Reflection ray는 반사 방향의 closest-hit radiance를 질의한다.
- GGX ray는 microfacet 분포에 따른 방향의 radiance를 샘플링한다.
- Diffuse secondary ray는 반구 방향의 incident radiance를 샘플링한다.

RT는 근사 표현에서 누락된 월드 공간 정보를 복원하는 것이 아니라, 필요한 정보를 실행 중 직접 질의한다. 이 차이가 구조적 artifact를 줄이는 원인이다.

## 5.3 오차의 성격 비교

래스터 근사와 RT의 오차는 서로 다른 성격을 가진다.

| 구분 | Raster 근사 | Ray Tracing |
|---|---|---|
| 주요 오차 원인 | 정보 축약, 해상도, 투영, heuristic | 유한 sample, epsilon, recursion 제한 |
| 시간적 특성 | 대체로 안정적이나 구조적 artifact 지속 | sample noise가 있으나 누적으로 감소 가능 |
| 공간 범위 | screen/light/capture 범위에 제한 | acceleration structure에 등록된 월드 전체 |
| 비용 제어 | texture 해상도와 filter 복잡도 | ray 수, hit shading, recursion depth |
| 디버깅 중심 | 좌표 변환, depth, buffer 내용 | ray direction, hit geometry, payload, AS |

이 비교를 통해 “Raster는 부정확하고 RT는 정확하다”는 단순 결론을 피할 수 있다. Raster의 오차는 예측 가능하고 안정적인 대신 특정 조건에서 사라지지 않으며, RT의 오차는 sampling을 통해 줄일 수 있지만 비용과 시간적 안정성 문제가 발생한다.

## 5.4 구현 과정의 버그 분류

본 연구 과정에서 발생한 문제는 다음 네 범주로 분류할 수 있다.

### 5.4.1 기하 및 좌표계 정합성

- Raster와 RT의 transform 행렬 표현 차이
- procedural geometry의 vertex 위치 및 normal 불일치
- winding order와 back-face culling
- 벽, 바닥 및 박스 접촉부 seam

### 5.4.2 수치 안정성

- Shadow map depth bias와 slope-scaled bias
- Shadow ray 및 reflection ray origin epsilon
- 접촉부 light leak와 self-intersection
- roughness가 0에 가까울 때 BRDF 수치 폭증

### 5.4.3 샘플링 및 시간 누적

- 고정 grid pattern
- per-pixel rotated grid
- stochastic jitter
- GGX importance sampling noise
- TAA history와 카메라 이동
- 확률적 RT 효과와 deterministic raster 효과에 대한 TAA 활성 조건 분리
- 1 spp/frame 결과와 hit별 64개 면광원 shadow ray의 역할 구분

### 5.4.4 엔진 리소스 및 파이프라인

- descriptor register 충돌
- H3D loader가 ORM 파일명을 인식하지 못해 검은 fallback texture를 사용한 문제
- RT local root signature와 shader table에 ORM SRV가 누락된 문제
- UAV/SRV resource transition
- shader payload 초기화
- RTPSO recursion depth 제한
- GI secondary payload의 recursion depth 전달 오류
- raster/RT material 및 emissive 처리 불일치
- `ExpVar`의 지수 범위 설정으로 인해 ambient가 완전히 꺼지지 않은 문제

이러한 문제는 최종 이미지 품질뿐 아니라 두 렌더링 방식의 내부 구조를 이해하는 학습 과정 자체가 연구 결과임을 보여준다.

## 5.5 혼합 렌더러 설계 원칙

본 연구 결과로부터 다음과 같은 혼합 렌더러 설계 원칙을 제안할 수 있다.

1. **Raster를 기본 primary visibility 경로로 사용한다.** 화면에 보이는 기하의 기본 shading과 G-buffer 생성은 raster가 높은 처리량을 제공한다.
2. **정보가 충분한 경우 기존 근사를 유지한다.** 작은 광원, 원거리 그림자, 낮은 중요도의 rough reflection 및 정적 간접광은 shadow map, environment map 또는 probe가 효율적이다.
3. **정보 손실이 명확한 경우 RT를 적용한다.** Off-screen reflection, 복잡한 접촉 그림자, 큰 면광원의 가시성, 근거리 glossy reflection 및 동적 color bleeding은 ray query의 가치가 높다.
4. **재질 및 중요도에 따라 ray budget을 배분한다.** Metallic, 낮은 roughness, 화면 중심, 큰 projected area 및 높은 contrast 영역에 더 많은 ray를 배분할 수 있다.
5. **Raster 결과를 RT의 fallback 또는 guide로 사용한다.** Shadow map과 SSR 결과를 우선 사용하고, confidence가 낮은 pixel에만 ray를 발사하는 구조로 확장할 수 있다.
6. **시간 누적과 denoising을 파이프라인 일부로 취급한다.** RT 효과의 sample count만 비교하지 않고, temporal reuse 비용과 안정성을 함께 평가해야 한다.

## 5.6 제안하는 후속 혼합 렌더러

향후 구현할 혼합 렌더러는 다음 순서로 구성할 수 있다.

1. Raster primary pass에서 depth, normal, material, motion vector 및 direct lighting을 생성한다.
2. Shadow map과 SSR을 기본 결과로 계산한다.
3. Shadow map 경계, SSR miss, screen edge 및 high-metallic pixel에 confidence 값을 계산한다.
4. Confidence가 낮거나 시각적으로 중요한 pixel에만 shadow/reflection ray를 발사한다.
5. RT 결과를 raster 결과와 결합하고 temporal accumulation 및 denoising을 적용한다.
6. GPU 시간 budget에 따라 ray 수와 적용 영역을 동적으로 조정한다.

이 구조는 본 연구의 각 Phase를 독립적인 데모에서 하나의 선택적 hybrid pipeline으로 연결하는 최종 확장 방향이다.

---

# 6. 논의 및 한계

## 6.1 단순 장면의 의미와 한계

Cornell 스타일 장면은 복잡한 production scene의 성능과 다양성을 대표하지 않는다. 기하 수가 적고 대부분 정적이며, 광원과 재질 종류도 제한적이다. 따라서 acceleration structure build/update 비용, 다수 동적 오브젝트, vegetation alpha test, animation 및 대규모 streaming 조건을 평가할 수 없다.

그러나 단순 장면은 특정 artifact의 인과 관계를 명확히 관찰할 수 있다는 장점이 있다. 본 연구는 이 장점을 활용하여 shadow bias, screen-space 정보 누락, reflection depth 및 color bleeding을 분리하여 분석한다.

## 6.2 성능 평가의 범위

본 장면은 기하와 재질이 제한된 진단 장면이므로 여기서 측정한 GPU 시간은 실제 게임 장면에 일반화할 수 없다. 장면 복잡도가 낮으면 traversal이 상대적으로 저렴할 수 있으며, 반대로 sample 수가 높은 실험 효과는 실제 production 설정보다 비쌀 수 있다. 이러한 이유로 본 연구는 GPU ms 비교를 평가 범위에서 제외하고, sample 수, 재귀 깊이, 필요한 장면 표현 및 추가 파이프라인 단계의 차이를 통해 각 방식의 계산 요구를 설명한다.

## 6.3 Shading 모델의 단순화

공통 Cook-Torrance BRDF를 사용하지만, diffuse normalization, energy compensation, BRDF LUT, multiple scattering 및 완전한 emissive transport는 단순화되어 있다. 따라서 결과는 물리적으로 완전한 reference rendering이 아니라 비교 실험용 shading baseline이다.

## 6.4 Sampling과 Denoising

RT glossy 및 GI는 모두 frame당 확률적 ray 1개를 선택하고 TAA를 활성화하여 시간적으로 누적한다. Raster GI와 deterministic mirror 모드는 확률적 sample 누적이 필요하지 않으므로 TAA를 비활성화한다. 현재 TAA는 엄밀한 독립 sample 평균이나 production 수준 denoiser가 아니라 history blending 기반의 시간 필터이므로, disocclusion과 빠른 카메라 이동에서 ghosting 또는 history invalidation 문제가 발생할 수 있다. 향후 SVGF, ReBLUR 또는 효과별 temporal-spatial filter와 유사한 구조를 검토할 필요가 있다.

현재 확률적 RT 파이프라인은 다음과 같이 요약할 수 있다.

```text
RayGen: primary ray 1개/px
    → closest-hit: glossy 또는 GI continuation ray 1개/hit
    → 직접광 및 간접광을 scene color에 합산
    → 공용 TAA history blend
    → output
```

이 구조에서는 한 frame의 확률적 sample 수가 1개이므로 variance가 매우 높다. 또한 공용 TAA는 현재 color와 history를 가중 혼합하고 neighborhood clipping 및 motion 정보를 적용하는 시간 필터이며, 독립 sample의 단순 산술 평균으로 무한히 수렴하는 accumulation buffer와는 다르다. 카메라 이동과 disocclusion에서는 과거 frame의 표면 대응이 틀어져 ghosting과 blur가 함께 발생할 수 있다. GI가 scene color에 직접 합산되므로 direct lighting, reflection 및 GI의 variance와 history를 효과별로 분리하여 조절할 수도 없다.

## 6.5 노이즈로 인한 관찰 한계와 단계별 후속 연구

현재 구현에서 가장 큰 관찰 한계는 알고리즘이 GI 경로를 생성하지 못하는 것이 아니라, 생성된 결과의 variance가 커서 H/G/J의 차이를 안정적으로 판독하기 어렵다는 점이다. 이를 해결하기 위한 후속 구현은 다음 세 단계로 구분할 수 있다.

### 6.5.1 Level 1: N-SPP 파라미터화

가장 직접적인 방법은 frame당 확률적 ray 수를 1/4/8 등으로 변경하고 평균하는 것이다. 이 프로젝트에서는 두 가지 범위를 구분해야 한다.

1. RayGen에서 primary path 전체를 N회 반복하면 진정한 N spp에 가깝지만, primary traversal, hit shading 및 hit별 64개 면광원 shadow ray까지 함께 반복되어 비용이 거의 N배 증가한다.
2. Closest-hit shader에서 glossy 또는 GI continuation ray만 N개 발사하여 평균하면 효과별 noise를 직접 줄이고 기존 primary ray를 재사용할 수 있다. 다만 각 secondary hit의 직접광 계산 비용은 여전히 크다.

N-SPP 파라미터화는 SPP 증가에 따른 noise 감소와 실행 비용 증가를 직접 비교할 수 있으므로, 품질-비용 trade-off를 설명하는 후속 실험에 가장 적합하다. 구현 난이도는 낮지만 실시간 성능은 sample 수에 비례하여 감소한다.

### 6.5.2 Level 2: GI 버퍼 분리와 공간 필터

두 번째 단계는 GI를 scene color에 즉시 더하지 않고 별도의 `g_GIBuffer`에 저장하는 것이다. 이후 depth와 normal을 guide로 사용하는 5×5 또는 7×7 bilateral compute filter를 적용하고, 필터링된 GI를 direct lighting과 합성한다.

```text
RT 1-SPP GI buffer
    → depth/normal-guided bilateral filter
    → GI temporal accumulation
    → direct lighting과 composite
```

이 구조는 geometry edge를 가능한 한 보존하면서 동일 표면 내부의 고주파 noise를 줄이고, GI에만 강한 필터를 적용할 수 있다. 반면 GI 전용 UAV/SRV, compute pass, resource transition 및 composite 경로가 추가되며, 얇은 기하와 접촉부에서는 blur 또는 light leak가 발생할 수 있다.

### 6.5.3 Level 3: SVGF 기반 시공간 Denoising

더 높은 품질을 목표로 할 경우 motion vector를 이용한 history reprojection, temporal accumulation, variance estimation 및 여러 단계의 À-trous wavelet filter로 구성된 SVGF 계열 구조를 적용할 수 있다. 이 방식은 1 spp 입력에서도 시간·공간 정보를 함께 사용하여 noise를 크게 줄일 수 있지만, history validation, disocclusion 처리, variance buffer 및 반복 compute pass가 필요하다. 본 프로젝트의 범위를 크게 확장하므로, denoising 자체를 핵심 기여로 삼는 후속 연구에 적합하다.

| 후속 목표 | 권장 단계 | 기대 결과 |
|---|---|---|
| SPP와 품질·비용 관계 비교 | Level 1 N-SPP | 1/4/8 spp 비교표 및 noise 감소 경향 |
| 최종 GI 비주얼 개선 | Level 2 GI 버퍼 + bilateral filter | 효과별 공간 필터와 안정된 캡처 |
| 실시간 RT denoising 연구 | Level 3 SVGF | variance-guided 시공간 복원 |

현 프로젝트의 자연스러운 확장 순서는 Level 1로 sample 수에 따른 관찰 가능성을 먼저 확인한 뒤, Level 2에서 GI를 독립 버퍼로 분리하는 것이다. Level 3은 구현 비용이 크므로 별도의 연구 범위로 남긴다.

## 6.6 기타 향후 연구

- Raster confidence 기반 선택적 shadow/reflection ray
- Ray budget의 화면 중요도 기반 동적 배분
- Dynamic BLAS/TLAS update 비용 측정
- 2-bounce를 초과하는 다중 bounce GI, multiple importance sampling 및 denoising
- Probe/lightmap update와 RT GI 혼합
- 복잡한 공개 장면에서의 재검증
- Reference path tracer와의 정량 이미지 오차 비교

---

# 7. 결론

본 연구는 래스터라이제이션과 레이 트레이싱을 서로 경쟁하는 완전한 렌더러로 비교하는 대신, 동일한 시각 효과를 계산하기 위해 서로 다른 장면 정보 질의를 사용하는 기술로 분석하였다. Microsoft D3D12 Raytracing MiniEngine Sample을 기반으로 Cornell 스타일 진단 장면과 단계별 비교 모드를 구축하고, shadow map과 shadow ray, PCSS와 면광원 sampling, SSR과 reflection ray, prefiltered environment map과 GGX importance sampling, environment irradiance와 1/2-bounce diffuse ray를 동일 엔진에서 구현하였다.

비교 결과, 래스터 근사 기법의 주요 artifact는 제한된 texture 또는 screen-space 표현에 필요한 장면 정보가 포함되지 않을 때 발생한다. RT는 가속 구조를 대상으로 월드 공간 질의를 수행하여 이러한 구조적 누락을 완화할 수 있다. 그러나 RT 역시 ray epsilon, recursion depth, sampling variance, temporal accumulation 및 엔진 통합 복잡성을 요구한다.

따라서 실시간 렌더링에서의 핵심은 한 방식을 다른 방식으로 완전히 대체하는 것이 아니다. Raster의 높은 처리량과 안정적인 근사를 유지하면서, 정보가 부족하거나 정확도가 중요한 지점에 선택적으로 ray query를 적용하는 것이 중요하다. 본 연구에서 구축한 비교 프레임워크는 이러한 혼합 렌더러를 설계하기 위한 실험 기반을 제공하며, 각 렌더링 기법의 결과뿐 아니라 그 결과가 발생하는 파이프라인 원인을 학습하고 분석할 수 있다는 점에 의의가 있다.

---

# 8. 결과 그림 및 표 구성안

## 8.1 필수 그림

1. 전체 시스템 구조도: Raster pipeline, DXR pipeline, 공유 scene/material/light data
2. Cornell 스타일 실험 장면과 오브젝트 배치 Top View
3. Phase 2: Shadow caster culling, bias 변화 및 shadow ray TMin 접촉부 비교
4. Phase 3: RT 4/16/64-ray grid, stochastic noise, rotated grid 및 PCSS over-blur 비교
5. Phase 4: Legacy 재질 경로와 PBR 전환 후 FlightHelmet 비교
6. Phase 4: AO/Roughness/Metallic/Normal debug view의 Raster/RT 비교
7. Phase 5: SSR screen-edge/off-screen/depth-discontinuity 대 reflection ray
8. Phase 5: Reflection Depth 2/3/5 비교 — 반사 체인 진행 단계별 캡처
9. Phase 6: Prefiltered environment map 대 RT glossy reflection
10. Phase 7: Raster GI 대 RT 1/2-bounce color bleeding
11. 구현 과정 bug 사례: seam, acne, peter-panning, ray epsilon light leak
12. 향후 hybrid renderer 구조도

## 8.2 필수 표

1. 원본 Microsoft sample과 수정 프로젝트 기능 차이
2. 렌더링 모드 및 단축키
3. Phase별 Raster 표현, RT 질의, 예상 artifact 및 계산 복잡도
4. 실험 환경: GPU, 해상도, build configuration, shadow map 크기, sample 수
5. 독립 변수 변화에 따른 시각적 현상
6. Phase별 관찰 현상, 파이프라인 원인 및 결론
7. 발생 버그와 원인 및 해결 방법

## 8.3 결과 표 템플릿

| 비교 모드 | 설정 | 관찰 현상 | 파이프라인 원인 | 결론 |
|---|---|---|---|---|
| Raster Shadow | Shadow map 512 | 경계 aliasing | 제한된 광원 depth texture 해상도 | 해상도 의존적 오차 |
| Raster Shadow | Shadow map 2048 | 경계 개선 | 더 조밀한 depth sample | 품질은 향상되지만 구조적 근사는 유지 |
| Raster Shadow | shadow caster culling 활성 | 일부 벽면 그림자 누락 | shadow camera rasterization에서 면 제거 | two-sided shadow pass 필요 |
| Raster Shadow | bias 과대/과소 | Peter Panning / Shadow Acne | Reverse-Z depth 이동과 자기 비교 | 접촉 정확도와 self-shadowing 사이 조정 필요 |
| RT Shadow | 1 ray | hard shadow | 광원 중심 한 점에 대한 visibility query | 정확한 접촉부, 면광원 penumbra 없음 |
| RT Shadow | `TMin=0.1` | 접촉부 흰 틈 | 가까운 occluder를 ray 시작 구간에서 건너뜀 | 작은 공통 epsilon 필요 |
| RT Shadow | epsilon `1e-5` | 접촉부 visibility 복원 | 실제 geometry 교차 검사 | 본 장면에서 안정적인 hard shadow |
| RT Soft Shadow | 4-ray fixed grid | 다섯 단계의 거친 penumbra | 가시 sample 수의 양자화 | sample 수 부족 |
| RT Soft Shadow | 16/64-ray fixed grid | 반복 경계와 grid pattern | 정렬된 sample 위치의 공간적 반복 | sample 수만으로 pattern 해결 불가 |
| RT Soft Shadow | 64-ray stochastic | 고주파 noise와 temporal jitter | 무작위 sample variance | 누적 또는 denoising 필요 |
| RT Soft Shadow | 64-ray per-pixel rotated grid | 반복 경계가 감소한 안정적 penumbra | pixel별 grid 방향 decorrelation | 최종 RT soft shadow 설정 |
| Raster PCSS | blocker/filter 각 64 samples | 거리별 penumbra | 평균 blocker 기반 가변 PCF 반경 | 단일 shadow map으로 plausible soft shadow |
| Raster PCSS | filter 반경 과대 | over-blur와 둥근 shadow bleeding | 중심 shadow map과 heuristic 반경 추정 | 최대 반경 제한 필요 |
| Legacy Material | FlightHelmet ORM 미로딩 | specular가 사라지고 금속/가죽 구분이 약함 | 검은 fallback texture와 비활성화된 RT specular | BRDF 이전에 material data path 검증 필요 |
| PBR Debug View | AO/Roughness/Metallic/Normal | 채널별 재질 패턴과 Raster/RT 차이를 직접 확인 | 합성 lighting을 우회해 입력 데이터를 출력 | 재질 오류와 lighting 오류를 분리 가능 |
| Shared PBR | 공통 ORM 및 Cook-Torrance | 두 경로에서 metallic/roughness 기반 표면 반응 | 공통 material table과 `EvaluatePBR` | 이후 visibility 비교의 shading 통제 조건 |
| Raster SSR | screen-edge 반사 | 경계 방향 반사가 끊김 | UV 이탈 시 buffer 조회 실패 | edge fade로 완화 가능, 구조적 누락은 유지 |
| Raster SSR | off-screen 반사 대상 | 반사가 완전히 누락됨 | color/depth buffer에 해당 물체 정보 없음 | 화면 밖 정보 복원 불가 |
| Raster SSR | 박스 모서리 depth discontinuity | 잘못된 반사 교차 또는 왜곡 | ray march가 depth 급변 구간을 가로질러 오판 | step 수 조정으로 부분 완화, 근본 해결 불가 |
| RT Reflection | Depth 2 (1회 반사) | 벽·그림자가 주로 반사됨, 헬멧 미관찰 | 1회 반사 광로만 열림 | 반사 체인의 첫 단계 |
| RT Reflection | Depth 3 (2회 반사) | 좌측 박스 우측면에 우측 박스 등장 | 2회 반사로 Box–Box 경로 열림 | 바닥-박스 간 재귀 반사 더 명확 |
| RT Reflection | Depth 5 (4회 반사) | 헬멧 반사가 바닥·좌측 박스 우측면에 등장, 체인 완성 | 4회 반사로 Camera→Floor→Left→Right→Helmet 완성 | Depth 5 이상에서 추가 변화 없이 수렴 |
| Raster Glossy | roughness 0.3 | 안정적, parallax 오차 | 위치가 압축된 prefiltered cubemap | 안정성과 위치 정확도의 교환 |
| RT Glossy | roughness 0.3, 1 spp/frame + TAA | 누적 전 noise, 누적 후 roughness blur 관찰 가능 | 현재 hit 위치의 GGX 방향 sampling | 정확한 가시성과 시간 누적 필요성 |
| Raster GI H | 공통 diffuse 재질, environment irradiance | 색 영향이 넓고 균일하게 퍼짐 | 방향 중심의 저주파 환경 정보 | 안정적이나 위치별 전달 경로 구분 제한 |
| RT GI G | 공통 diffuse 재질, 1-bounce, 1 spp/frame + TAA | 강한 초기 noise, 국소 색 변화는 누적 후 검증 필요 | cosine-weighted diffuse secondary ray 1개 | 위치 종속 간접광과 시간 누적 필요성 |
| RT GI J | 공통 diffuse 재질, 2-bounce, 1 spp/frame + TAA | 추가 diffuse 전달 가능, noise로 판독 어려움 | 두 번째 diffuse continuation ray | 충분한 누적 또는 denoising 필요 |

---

# 9. 참고문헌 구성안

최종 논문에서는 다음 문헌 범주를 포함한다.

1. DirectX Raytracing specification 및 Microsoft D3D12 Raytracing samples
2. Real-Time Rendering
3. Physically Based Rendering: From Theory to Implementation
4. Shadow Mapping 및 Percentage-Closer Filtering
5. Percentage-Closer Soft Shadows
6. Screen-Space Reflection 관련 논문 및 기술 자료
7. Cook-Torrance microfacet BRDF와 GGX
8. Importance Sampling 및 Monte Carlo integration
9. Real-time ray tracing denoising
10. Hybrid rendering 및 production ray tracing 사례
11. Schied et al., *Spatiotemporal Variance-Guided Filtering: Real-Time Reconstruction for Path-Traced Global Illumination*, 2017

---

# 10. 작성 시 유지할 핵심 주장

논문 전체에서 다음 표현을 일관되게 유지한다.

> 본 연구는 Rasterization과 Ray Tracing의 절대적 우열을 판정하는 성능 벤치마크가 아니다. 제한된 장면 정보에 기반한 Raster 근사의 실패 조건을 재현하고, 대응하는 월드 공간 ray query가 무엇을 다르게 계산하는지 엔진 파이프라인 수준에서 분석하는 비교 연구이다.

> 단순한 Cornell 스타일 장면은 실제 게임 장면을 대표하기 위한 것이 아니라, 변수 통제와 artifact 원인 분석을 위한 diagnostic scene이다.

> RT는 모든 문제를 자동으로 해결하지 않는다. Raster의 구조적 정보 손실을 줄이는 대신 traversal 비용, sampling variance, recursion, epsilon 및 엔진 통합 문제를 새롭게 요구한다.

> 최종 목표는 Raster를 제거하는 것이 아니라, Raster 데이터가 충분한 영역에서는 근사를 유지하고 정보가 부족한 영역에 선택적으로 RT 질의를 연결하는 혼합 렌더러를 설계하는 것이다.
