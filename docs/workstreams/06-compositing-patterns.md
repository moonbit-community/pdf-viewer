# W6 透明合成与 pattern/shading

TODO：M-01、M-02、M-03、H-01、H-02、H-03

状态：归档专题资料。本文的旧文件归属和多角色安排已被
[PARALLEL.md](../PARALLEL.md) 中的两条主线替代，不作为当前分工。

## 复用策略

与 W5 先验证 [绘制候选](../codec-candidates.md#绘制与合成) 已提供的 surface、clip、
blend、渐变/网格插值；不另建通用 compositor/raster 栈。PDF non-isolated/knockout、
soft-mask BC/TR、pattern 资源/矩阵与 Coons/tensor patch 适配仍需核查。
明确候选能覆盖的分支，先评估扩接口或局部补充，不因库支持 blend 就勾选整组透明语义。

## 负责范围

补组级透明合成、完整 blend/soft mask、复杂 pattern 与逐像素 shading。
image-local SMask/Matte 属于 W3；ExtGState/Form/group 的 mask 属于本模块。
现有 SVG group 标记和 mesh triangle 不能当成完整 backdrop/knockout/插值实现。

| TODO | 子任务与验收重点 |
| --- | --- |
| M-01 | non-isolated backdrop、knockout 与嵌套 transparency groups |
| M-02 | Alpha/Luminosity、BC 空间、TR、组边界与 mask 作用域 |
| M-03 | 完整 blend modes，确定性输出/回退与实际像素对照 |
| H-01 | uncolored pattern 的基础色、matrix、重复边界与最终像素 |
| H-02 | 文字/图片/Form/透明组/独立资源的复杂 pattern cell 和描边 |
| H-03 | Gouraud/Coons/tensor patch 逐像素插值、抗接缝、function/axial/radial 边界 |

## 文件边界与依赖

本模块维护 `masks.mbt`、`patterns.mbt`、`mesh.mbt` 及专用测试；
可新增后端合成适配、PDF group/mask/pattern 状态文件；通用 blend/raster-shading
算法仅在确认依赖缺口后新增。
`pdf-viewer.mbt` 的 group/paint state、`svg.mbt` 和新像素入口经集成 Agent接入。
调用 W3 的图像样本与采样、W4 的转换、W5 的 surface/clip/draw primitives。

W5 的 CTM 与像素后端是最终组级绘制的依赖。与 W5 先固定 buffer/alpha
和作用域接口，再实现真实画面合成。不能让 W5/W6 同时重写同一 renderer。

## 推荐切片

先用具有解析预期值的小 surface fixture 验证后端 blend/group 契约，
再接 PDF group/backdrop/mask 适配或补 pattern/shading 资源解析。
通用算法缺口单列，接入页面后才扩大真实对照。
六项工作量很大，一轮只分配 group/blend、soft mask 或 shading 中的一个切片。
需要更多并发时可再按这三组拆分，但 collector 与 compositor 仍只有一个写入者。

## 验证与交付

覆盖 isolated/non-isolated/knockout、nested group、mask matrix/BC/TR、
group colour space、premultiplied alpha、所有 blend modes；pattern 覆盖
PaintType 1/2、fill/stroke、负 step、复杂 cell、调用位置基础色与缩放/旋转。
mesh 检查颜色插值及共享边，function shading 不允许空占位通过。

保留 `tiling_patterns_variations.pdf` 的整页/P5 区域对照，扩大透明/mesh
真实 fixture。colour/geometry/image 修复一起影响像素时分开报告证据。
交付算法、数据接口、接入位置、真实差异和未支持分支，逐项验收六个 TODO。
