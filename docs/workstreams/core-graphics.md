# A2 图形与图像

目标：把 PDF 图片和图形正确绘制出来，包括颜色、裁剪和透明效果。
图片解码与绘制/合成属于同一条主线，避免它们互相等待不同的实现者。

TODO 范围：I-01、I-02、I-04、C-01、C-03、G-01、G-02、G-03、
M-01、M-02、M-03、H-01、H-02、H-03。
共同边界见 [PARALLEL.md](../PARALLEL.md)。

## 工作顺序

1. 先适配现成 JPEG 解码的原始样本，打通 encoded image 的 SMask/Matte，
   复跑 `issue13931.pdf`；同时修完整 CTM 下的描边和裁剪，为后续合成保留正确几何。
2. 验证 JPX 多组件、JBIG2 和 ICC 方案，再补 group/soft mask/blend、
   pattern/shading。用现成绘制后端验证 surface、clip、blend，再接入 PDF 状态，
   不默认从零写 codec、ICC 引擎或 rasterizer。

候选版本与限制见 [生态候选](../codec-candidates.md)。
JPEG 候选并未覆盖所有 PDF 编码；`trkbt10/jpeg2000` 当前公开接口有
component0 输出限制，先验证/扩展多组件 API。`enanandesu/icc` 只是元数据读取，
实际 profile 转换另需色彩引擎。记录 native/Wasm/JS 等实际支持的目标。

## 可修改的文件

以下实现文件均位于 `internal/engine/`。根 `api.mbt` 只负责公开导出。

- `images.mbt`、`image_colour.mbt`、`image_alpha.mbt`、`image_sampling.mbt`、
  `colour.mbt`、`masks.mbt`、`patterns.mbt`、`mesh.mbt`。
- `model.mbt` / `collector.mbt`、`svg.mbt`、`page_model.mbt`，新增 codec/色彩/绘制适配文件，
  以及对应专用测试和新增图像工具。

字体和文字输出使用 A1 的函数，不重写另一套。
A1 需要公共模型/collector 接入时，由你修改上述入口，两人同步接口即可。
根依赖配置和公共工具需要修改时顺序交接，不占用 A1 的专用文件。

## 验收

区分原始样本、颜色转换、alpha/Matte 和最终绘制，验证遮罩没有重复应用。
真实 fixture 覆盖 encoded mask、剪切/非均匀 CTM、group/soft mask 和 pattern；
分别记录像素差异、目标支持和大图资源开销。现有 raw mask/resize/Matte
已接入，不重复实现。

相关回归通过后运行共同检查。导出成功不等于像素对齐，不能靠扩大容差、
跳过文件或空白输出隐藏差异；交付已接入的路径和剩余限制。

当前实现、各目标能力、真实样本与开放依赖见 [A2 验收记录](../a2-acceptance.md)；
勾选和总数仍以 [TODO](../TODO.md) 为准。
