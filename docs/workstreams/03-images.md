# W3 图片解码与图像遮罩

TODO：I-01、I-02、I-04

状态：待分配实现切片。共同规则见 [PARALLEL.md](../PARALLEL.md)。

## 负责范围

解码 PDF image/inline image 到库可处理的原始像素，并负责 image-local
Decode、colour-key、SMask/explicit ImageMask、Matte、重采样和大图限制。
ExtGState/Form soft mask、transparency group 和 blend 属于 W6。

raw mask 1/2/4/8/16-bit、最大尺寸 resize、Matte 和 affine sampling 已有主路径。
不要重新实现它们；最新结果在 [validation.md](../validation.md#image-interpolation-raw-alpha-masks-and-malformed-simple-font-recovery)。

| TODO | 子任务与验收重点 |
| --- | --- |
| I-01 | MoonBit 可用 JPX/JPEG2000 像素解码、PDF colour/mask 数据；不依赖浏览器 image/jp2 |
| I-02 | JBIG2 globals、segments、常用压缩和 mask；有界失败与真实扫描 PDF |
| I-04 | encoded JPEG/JPX/JBIG2 mask/Matte、colour-key 边缘、完整图像合成、大图策略 |

## 文件边界

本模块维护 `images.mbt`、`image_colour.mbt`、`image_alpha.mbt`、
`image_sampling.mbt` 及图像专用测试；新 codec 使用专用文件或具备 `moon.pkg`
的实现 package。色彩转换调用 W4 的实现，group/compositor 调用 W6。
`PdfImageResource` 等公共类型和 `svg.mbt`/新后端入口由集成 Agent接入。
pattern 的图像采样由 W3 提供算法，`patterns.mbt`/`mesh.mbt` 接入归 W6。

## 推荐首轮切片

先按 [生态解码候选](../codec-candidates.md) 核查/验证现成库，
再修 JPEG + SMask + Matte 的 `issue13931.pdf`，然后处理 colour-key 边缘。
已确认 `mizchi/image` 与 `walkzzz/image` 有纯 MoonBit baseline JPEG 解码；
JPX 的 `trkbt10/jpeg2000@0.2.0` 已核查源码/API，但当前公开 `decode` 有
component0 输出路径，all-components 位于 internal，不能直接当 RGB/RGBA 使用。
先验证灰度/彩色 fixture，优先扩展该库的公共多组件/布局 API，再做 PDF JPX 适配。
JBIG2 继续查现有库及绑定/移植方案，不默认从零写 decoder。
先跑真实 fixture 和目标/性能核查，
能复用的解码器直接适配，只有确认的缺口才安排扩展或自研。
普通 JPEG 的压缩字节预览已存在，新增的像素路径需要真正在 alpha/Matte
合成中使用；不能只增加 decoder 文件或用浏览器保留原图就宣称完成。

[`jpeg-parser.mbt.txt`](../drafts/jpeg-parser.mbt.txt) 是被暂停的未完成草稿。
缺少 scan decoder、IDCT、YCbCr/YCCK 像素展开和 tests，未接入任何主路径。
可作备用参考，但它不再是默认路线，不当作可运行起点。

## 验证与交付

codec 使用成熟实现/测试作为 oracle，覆盖 baseline/progressive、restart、
子采样、Gray/RGB/CMYK、ColorTransform、损坏/截断输入与 allocation limits。
JPX/JBIG2 分别扩展自己的真实 corpus；不能因 JPEG 完成就勾选 I-01/I-02。

复跑 `image_colour_wbtest.mbt`、`image_alpha_wbtest.mbt`、
`image_sampling_wbtest.mbt`，运行 `tools/image_cases.json` 的 PDF.js 对照。
记录 `issue13931` 前后差异，明确 `smaskdim` 含批注影响，不把所有差异归于 mask。
大图内存指标交给 W8 统一测量；解码/缓存限额由 W3/W8 协同落实。

交付 samples/colour/alpha 约定、实际支持的编码分支、差异和资源限制。
