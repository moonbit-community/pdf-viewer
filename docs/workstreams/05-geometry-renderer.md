# W5 路径几何与绘制后端

TODO：G-01、G-02、G-03

状态：待分配实现切片。共同规则见 [PARALLEL.md](../PARALLEL.md)。

## 复用策略

先比较浏览器 Canvas 2D、`mizchi/svg`/`bobzhang/vg` 基础绘制，native 可评估
Skia 绑定；候选限制见 [绘制与合成](../codec-candidates.md#绘制与合成)。
通用路径 raster、曲线/渐变和 clip primitive 优先复用；本模块保留 PDF CTM/path
状态与后端适配。现成库可能同样采用描边近似，必须用真实 fixture 决定，
不把换库直接记成 G-01/G-03 完成。

## 负责范围

处理完整 CTM 下的路径/文字描边、dash、clip/hairline 和确定性的像素绘制基础。
当前 SVG 的非均匀描边使用平均 basis scale，是待修复近似。
页面模型与 PDF-space 坐标保持兼容，viewport 是唯一页面投影来源。

| TODO | 子任务与验收重点 |
| --- | --- |
| G-01 | 完整 affine 的椭圆笔画、非均匀缩放/剪切、文字 stroke、dash 的路径语义 |
| G-02 | hairline/miter/退化路径、填充规则、clip 时机和多层 Form 的边界 |
| G-03 | 验证/适配现成像素绘制后端，覆盖 SVG 表达不足的语义；以实测决定，不默认新写 rasterizer |

## 文件边界与依赖

优先新增后端适配、结构化 CTM/path 状态与专用测试；几何算法只补核查后的缺口。
公共 `PdfPathItem`、collector、
`text_clipping.mbt` 和 `svg.mbt` 修改经集成 Agent接入。
坐标计算与 glyph transform 可复用 `text_geometry.mbt`，需要修改该文件时
先在本轮文件负责人表登记，避免和 W1 的字体几何修复交叉。

W6 使用本模块的 surface、clip 和 group 绘制基础；
两模块先共同确定 buffer/stride、alpha 是否预乘、paint command 的
坐标与 CTM、clip/group 栈、输出倍率，再分别实现。
W4 负责颜色语义，W3 负责图像像素与采样；本模块不另建解码/色彩栈。
现有 path 已序列化为页面坐标字符串，pattern/mask/AP 也常提前降为 SVG/data URI。
新后端不能只消费这些字符串就宣称完整重放；需要与集成 Agent/W6 一起保留
足够的结构化路径、源颜色与作用域信息，再做后端适配。

## 推荐切片

先与 W6 用实际 PDF fixture 比较候选的 CTM/clip/blend 输出和目标成本，
保留绘制时完整 CTM 后接可复用 primitive，再修复不支持的非均匀/剪切 stroke。
路径创建过程中 CTM 可改变，不能简单给整个路径套上最后一次 transform。
`vector-effect` 或平均 stroke-width 也不能替代完整 PDF 笔画语义。
像素后端先适配现成 primitive，主路径接入和 W6 接口需协调。

## 验证与交付

覆盖旋转/非均匀/剪切/反射、path 中途改变 CTM、dash 相位、miter 限制、
hairline、零面积路径、nonzero/evenodd、多重显式/文字裁剪。
保留 `text_clip_cff_cid.pdf`、`vertical.pdf` 的现有基线，新增真实描边样本。
比较同一 scale/rotation 的 viewport 和像素，不能靠重采样隐藏边界错位。

交付 CTM/path 数据约定、后端 primitive、基准/差异以及 collector/renderer
接入补丁。只完成 stroke 算法不代表 G-03 的整页像素后端已完成。
