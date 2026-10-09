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
  在浏览器中显示取决于宿主解码器；
- 保留文字原始四边形，遇到旋转文字时按 glyph 方向生成 SVG transform；路径 display
  list 保留线帽、连接方式和虚线参数；
- 对嵌入 TrueType 的 `glyf/loca` 轮廓做 viewer 侧解析，支持简单字形和常见 composite
  字形，并按 `CIDToGIDMap` 把 Identity-V/Identity-H 字符绘制成 SVG path。这样即使嵌入
  字体缺少浏览器可用的 `cmap`，日文等 CID 字体也不会退化成错误的 Unicode 字符；
  同时解析 raw CFF 和 OpenType/CFF 字形，支持 CID 字体、局部/全局 subroutine、hint mask、
  flex/seac 和常见 Type 2 charstring 运算；对嵌入的单字节 Type 1 字体解析 eexec/PFB、
  charstring、subroutine、seac 和 flex，并使用同一轮廓绘制；CID-keyed Type 1 支持
  单 FD 的 Binary/Hex `StartData`、CIDMap、SubrMap 和 `lenIV`，多 FD 字体仍使用回退；
- 文字保留实际的 `glyph_transform`（CTM、text matrix、字号、水平缩放、rise 和基线）；
  TrueType 轮廓按 em 绘制，不再把字体总包围盒压进单字的 advance box。SVG 普通文字
  也使用同一矩阵和 alphabetic baseline，避免 FreeText 外观中的文字落到裁剪区域之外；
- 保留 PDF text rendering mode、填充/描边颜色，并按 paint-site CTM 缩放路径线宽和虚线
  间距；文字 clipping mode 4–7 会在 `ET` 后按字形轮廓建立 clip path，同一 text object
  中的字形合并，后续 text object 求交，并遵守 `q/Q` 和 Form 的作用域。裁剪轮廓目前来自
  CFF、单字节 Type 1 和嵌入 TrueType 字体；其它字体没有可解码轮廓时不会伪造空 clip；非均匀 CTM 的
  椭圆文字笔画仍需更底层的 glyph/path renderer；
- 按 PDF 用户空间矩形返回文本、边界和源 display-list item 索引，供上层做
  cursor/框选和 Agent 上下文压缩；
- 暴露 annotation 几何、原始 `/Annots` 索引、屏幕/打印标记、URI 和 PDF 编码的文本。
  优先绘制 `/AP /N` 指定的外观，按 `/AS` 选择状态，处理 `/BBox`、`/Matrix`、裁剪和
  独立资源；批注及其嵌套 Form 中的同名字体、多个外观的 clip/mask/pattern ID 不互相覆盖。
  合法的空外观保持空白；没有可用外观时使用基础几何回退；
- 暴露继承的 AcroForm 字段名、类型、值、flags 和选项，支持基础只读 widget 回退。
  单选按钮的 `button_value` / `button_checked` 与共享的父字段值分开表示；完整表单
  排版、`/DA`、多行、comb、choice export/display 映射仍待实现；
- 提供 outline、page labels、attachments、optional content、structure tree、info 和
  metadata 读取入口；JSON 保留 pdflite 的 schema，尚未适配为 pdf.js 的返回结构；
- 跟踪 ExtGState 的填充/描边透明度和 SVG 可表达的 blend mode；
- 读取 Form XObject 的 `/Group /Transparency` 边界，把 isolated/non-isolated、knockout
  标记和嵌套 `group_path` 带入 display list；SVG 对 isolated 组使用 `isolation:isolate`，
  并保留 data 属性供后续 Canvas/WebGL compositor 使用；
- 对常见的彩色、路径型 tiling pattern 生成 SVG `<pattern>`，应用 pattern matrix，并把
  多段显式 clipping 以浏览器可工作的嵌套 clipPath 表达；uncolored pattern、复杂 Form
  资源和 soft mask 仍未覆盖；PatternType 2 shading pattern 会解析为 mesh 并裁剪到原始路径；
- 解析 PDF ShadingType 4/5/6/7 的二进制 mesh stream，支持 Gouraud、Coons patch 和
  tensor patch 的三角化。`PdfMeshTriangle` 保留每个顶点的 PDF-space 坐标和颜色；SVG
  后端用 barycentric 微三角近似 Gouraud 插值，Canvas/WebGL 宿主可以直接使用原始顶点颜色做
  像素级插值；
- 支持 PDF ImageMask、普通 `/Mask` color-key、图片 `/SMask`，以及常见的 Form soft
  mask；mask 会在图片的局部坐标系中合成，再交给页面 affine transform。Form mask 已处理
  `/BBox`、`/S /Alpha`、`/S /Luminosity` 和常见 `/TR` transfer function，资源字典会随
  Form 继承。浏览器不支持的 inline CCITT mask、复杂 backdrop/knockout 合成、backdrop
  色彩空间和部分 JPEG2000/JBIG2 mask 仍保留为占位或依赖宿主解码器；
- 提供 native CLI，方便用真实 PDF 调试，而不需要先接入浏览器。

渲染器会把相邻且共享同一个 soft mask 的 display-list item 放进一个 SVG mask
compositor group，再输出文字、路径和图片。这与 pdf.js 先合成 source group、再应用
soft mask 的顺序一致。Form XObject 的透明组边界也会保留下来；isolated 组可以直接
映射到 SVG isolation，non-isolated 组和 knockout 组目前保留结构化标记，完整的
backdrop/knockout 像素合成仍需要 Canvas/WebGL compositor。

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

CLI 成功写入 SVG 返回 `0`；读取、渲染、页码越界或写文件失败返回 `1`；参数错误返回
`2`。批量验证可以直接运行 MoonBit 脚本：

```bash
moon run tools/corpus.mbtx
```

默认扫描 pdf.js corpus 中以 `annotation` 开头的 `.pdf`，每个文件只检查第一页，单文件
超时 15 秒。也可以指定 corpus 目录和文件名前缀：

```bash
moon run tools/corpus.mbtx reference/pdf.js/test/pdfs annotation-highlight
```

每次运行创建新的 `_build/corpus-*/`，保存 SVG 和逐文件 `report.json`。验证同时检查
退出码和新输出，存在失败或超时就返回非零。`data-pdf-placeholder="true"` 仅标记明确的
渲染占位。没有占位不代表内容完整，也不代表像素一致；当前结果和失败文件见
[`docs/validation.md`](docs/validation.md)。

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

文档读取补充 API：`outline_json()`、`page_labels_json()`、`page_labels()`、
`attachments_json()`、`optional_content_json()`、`struct_tree_json()`、`info_json()`、
`metadata_bytes()`。其中 `page_labels()` 始终返回每页的显示标签，没有标签树时使用一基
十进制页码；这与 pdf.js 返回 `null` 的约定不同。optional-content API 目前读取配置，
还不能通过切换图层改变渲染结果。

这不是声称已经达到 pdf.js 的覆盖率。多 FD/复杂 CMap 的 CID-keyed Type 1、完整字体 metrics 和系统字体 fallback、
soft mask 的完整组合成语义、透明组的完整 backdrop/knockout 合成、uncolored/复杂 tiling
pattern、mesh 的最终像素级 Gouraud 合成、完整 annotation appearance/form 行为仍是后续工作；
当前 API 会先把可解析内容的页面位置和类型留在
display list 中，避免宿主丢失结构化信息。现阶段 SVG 输出适合调试和建立回归基线，不能
当作 pdf.js 的像素级替代品。

旋转参数按 pdf.js 规则只接受 `0/90/180/270`（允许等价的负数和大于 360 的整数）；
SVG 渲染遇到其它角度会返回 `PageRotationExpected`，不会静默近似成另一个角度。

## 参考实现和测试策略

`pdflite` 负责 PDF 语法、资源解析和内容条目生成；viewer 层负责页面模型、viewport、
glyph/mesh 补充解码、批注外观、SVG 序列化和选择映射。后续每补一个 renderer 特性，就从 pdf.js 的 corpus 选一个最小
fixture，同时保留一个 MoonBit snapshot/断言测试，先验证结构化输出，再验证浏览器视觉
输出。这样可以把“解析正确”和“渲染接近 pdf.js”分开定位。

更详细的分层和后续阶段见 [`docs/architecture.md`](docs/architecture.md)。
