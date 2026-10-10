# W5 路径几何与绘制后端

TODO：G-01、G-02、G-03

状态：待分配实现切片。共同规则见 [PARALLEL.md](../PARALLEL.md)。

## 负责范围

处理完整 CTM 下的路径/文字描边、dash、clip/hairline 和确定性的像素绘制基础。
当前 SVG 的非均匀描边使用平均 basis scale，是待修复近似。
页面模型与 PDF-space 坐标保持兼容，viewport 是唯一页面投影来源。

| TODO | 子任务与验收重点 |
| --- | --- |
| G-01 | 完整 affine 的椭圆笔画、非均匀缩放/剪切、文字 stroke、dash 的路径语义 |
| G-02 | hairline/miter/退化路径、填充规则、clip 时机和多层 Form 的边界 |
| G-03 | 可验证像素绘制后端，覆盖 SVG 表达不足的语义；Canvas/WebGL 以实测决定 |

## 文件边界与依赖

优先新增几何/描边/像素实现与专用测试，公共 `PdfPathItem`、collector、
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

先保留绘制时完整 CTM，修复非均匀/剪切 stroke，新增实际 PDF fixture。
路径创建过程中 CTM 可改变，不能简单给整个路径套上最后一次 transform。
`vector-effect` 或平均 stroke-width 也不能替代完整 PDF 笔画语义。
像素后端可同时开发基础 primitive，但主路径接入和 W6 接口需协调。

## 验证与交付

覆盖旋转/非均匀/剪切/反射、path 中途改变 CTM、dash 相位、miter 限制、
hairline、零面积路径、nonzero/evenodd、多重显式/文字裁剪。
保留 `text_clip_cff_cid.pdf`、`vertical.pdf` 的现有基线，新增真实描边样本。
比较同一 scale/rotation 的 viewport 和像素，不能靠重采样隐藏边界错位。

交付 CTM/path 数据约定、后端 primitive、基准/差异以及 collector/renderer
接入补丁。只完成 stroke 算法不代表 G-03 的整页像素后端已完成。
