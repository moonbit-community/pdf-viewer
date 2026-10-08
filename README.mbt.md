# moonbit-community/pdf-viewer

这是一个独立的 MoonBit PDF viewer 工程，目标是逐步对齐 pdf.js 的
`document → page → viewport → text/display list → renderer` 工作流，最终为
浏览器和 OpenSeek 一类宿主提供只读、高保真、可框选的 PDF 预览能力。

当前第一个可运行里程碑已经具备：

- 使用 `moonbitlang/pdflite` 从 PDF bytes 建立文档和页面模型；
- 以一基页码访问页面，暴露 `PdfPageModel`、`PdfTextContent` 和 paint-order
  display list；
- 计算带缩放和旋转的 `PdfViewport`，旋转语义与 pdf.js 的顺时针页面旋转一致；
- 将文字、矢量路径、图片和渐变输出为自包含 SVG；JPEG、原始像素图片和 inline image
  会转成浏览器可用的 data URL。JPEG2000、JBIG2 会保留原始媒体类型和 bytes，是否能
  在浏览器中显示取决于宿主解码器；暂不支持的 mesh shading 会保留可见占位层；
- 保留文字原始四边形，遇到旋转文字时按 glyph 方向生成 SVG transform；路径 display
  list 保留线帽、连接方式和虚线参数；
- 保留 PDF text rendering mode、填充/描边颜色，并按 paint-site CTM 缩放路径线宽和虚线
  间距；文字 clipping mode 和非均匀 CTM 的椭圆笔画仍需要更底层的 glyph/path renderer；
- 按 PDF 用户空间矩形返回文本、边界和源 display-list item 索引，供上层做
  cursor/框选和 Agent 上下文压缩；
- 暴露基础 annotation layer（link、highlight、underline、strikeout、text、widget 等）
  以及 URI、颜色、边框和内容；
- 跟踪 ExtGState 的填充/描边透明度和 SVG 可表达的 blend mode；
- 对常见的彩色、路径型 tiling pattern 生成 SVG `<pattern>`，应用 pattern matrix，并把
  多段显式 clipping 以浏览器可工作的嵌套 clipPath 表达；uncolored pattern、复杂 Form
  资源和 soft mask 仍未覆盖；
- 支持 PDF ImageMask、普通 `/Mask` color-key、图片 `/SMask`，以及常见的 Form soft
  mask；mask 会在图片的局部坐标系中合成，再交给页面 affine transform。Form mask 已处理
  `/BBox`、`/S /Alpha`、`/S /Luminosity` 和常见 `/TR` transfer function，资源字典会随
  Form 继承。浏览器不支持的 inline CCITT mask、复杂 transparency group、backdrop
  色彩空间和部分 JPEG2000/JBIG2 mask 仍保留为占位或依赖宿主解码器；
- 提供 native CLI，方便用真实 PDF 调试，而不需要先接入浏览器。

渲染器会把相邻且共享同一个 soft mask 的 display-list item 放进一个 SVG mask
compositor group，再输出文字、路径和图片。这与 pdf.js 先合成 source group、再应用
soft mask 的顺序一致；更复杂的 isolated/non-isolated、knockout 和嵌套透明组仍需要
保留 Form XObject 的树形边界。

## 本地运行

先安装 MoonBit，然后在本目录执行：

```bash
moon test
moon check --target all
moon run --target native cmd/main -- input.pdf [output.svg]
```

例如，CLI 会把第一页写成一个可以直接在浏览器打开的 SVG：

```bash
moon run --target native cmd/main -- ./sample.pdf /tmp/page-1.svg
```

也可以指定页码：

```bash
moon run --target native cmd/main -- ./sample.pdf /tmp/page-3.svg 3
```

这个命令只负责调试输入文件和输出 SVG；浏览器宿主可以直接调用同一组
`open_document`、`page`、`render_svg` API。

`reference/pdf.js` 是本地对照 checkout，不会随项目提交；当前对照版本记录在
[`reference/README.md`](reference/README.md) 中。它的 `test/pdfs` corpus 用来驱动
后续逐特性兼容测试。

## API 对照

| pdf.js 概念 | 本项目当前 API |
| --- | --- |
| `getDocument(data)` | `open_document(bytes)` |
| `PDFDocumentProxy.numPages` | `PdfViewerDocument::page_count()` |
| `PDFDocumentProxy.getPage(n)` | `PdfViewerDocument::page(n)` |
| `PDFPageProxy.getViewport({ scale, rotation })` | `PdfPageModel::viewport(scale~, rotation~)` (`matrix` and SVG transform included) |
| `PDFPageProxy.getTextContent()` | `PdfViewerDocument::text_content(n)` / `PdfPageModel::text_content()` |
| `PDFPageProxy.getOperatorList()` | `PdfViewerDocument::operator_list(n)` |
| `PDFPageProxy.render(...)` | `PdfViewerDocument::render_svg(n, scale~)` / `render_svg_with_rotation(...)` |

这不是声称已经达到 pdf.js 的覆盖率。字体 metrics 和 fallback、soft mask 的完整组
合成语义、uncolored/复杂 tiling pattern、mesh shading、完整 annotation
appearance/form 行为仍是后续工作；当前 API 会先把这些内容的页面位置和类型留在
display list 中，避免宿主丢失结构化信息。现阶段 SVG 输出适合调试和建立回归基线，不能
当作 pdf.js 的像素级替代品。

旋转参数按 pdf.js 规则只接受 `0/90/180/270`（允许等价的负数和大于 360 的整数）；
SVG 渲染遇到其它角度会返回 `PageRotationExpected`，不会静默近似成另一个角度。

## 参考实现和测试策略

`pdflite` 负责 PDF 语法、资源解析和内容条目生成；viewer 层只做页面模型、viewport、
SVG 序列化和选择映射。后续每补一个 renderer 特性，就从 pdf.js 的 corpus 选一个最小
fixture，同时保留一个 MoonBit snapshot/断言测试，先验证结构化输出，再验证浏览器视觉
输出。这样可以把“解析正确”和“渲染接近 pdf.js”分开定位。

更详细的分层和后续阶段见 [`docs/architecture.md`](docs/architecture.md)。
