# Implementation and Development Notes

本文记录 PDF viewer 的实现细节、API 对照、兼容性边界和开发验证方式。
所有命令均在仓库根目录执行。项目介绍与快速开始见 [README](../README.md)。

实现能力与边界：

- 使用 `moonbitlang/pdflite` 从 PDF bytes 建立文档和页面模型；
- 以一基页码访问页面，暴露 `PdfPageModel`、`PdfTextContent` 和 paint-order
  display list；
- 按 PDF.js 语义求 CropBox/MediaBox 有效交集，保留非零页面原点和 `/UserUnit`；
  计算带缩放和旋转的 `PdfViewport`，旋转语义与 pdf.js 的顺时针页面旋转一致，
  实际矩阵和 SVG 尺寸使用 `scale * user_unit`；
- 将文字、矢量路径、图片和渐变输出为自包含 SVG；JPEG、原始像素图片和 inline image
  会转成浏览器可用的 data URL。JPEG2000、JBIG2 会保留原始媒体类型和 bytes，是否能
  在浏览器中显示取决于宿主解码器；
- 依据声明的颜色空间转换 DeviceGray/RGB/CMYK、CalGray、CalRGB、Lab、Indexed 和
  Separation/DeviceN tint。路径、文字、渐变和原始图片共用转换；原始图片按
  1/2/4/8/16-bit 样本、行 padding 和 `/Decode` 处理，color-key `/Mask` 在原始整数
  样本中比较。CMYK 使用 PDF.js 的 SWOP 拟合回退，ICCBased 目前仍只使用 alternate；
- 保留文字原始四边形，遇到旋转文字时按 glyph 方向生成 SVG transform；路径 display
  list 保留线帽、连接方式和虚线参数；
- 对嵌入 TrueType 的 `glyf/loca` 轮廓做 viewer 侧解析，支持简单字形和常见 composite
  字形，并按 `CIDToGIDMap` 把 Identity-V/Identity-H 字符绘制成 SVG path。这样即使嵌入
  字体缺少浏览器可用的 `cmap`，日文等 CID 字体也不会退化成错误的 Unicode 字符；
  同时解析 raw CFF 和 OpenType/CFF 字形，支持 CID 字体、局部/全局 subroutine、hint mask、
  flex/seac 和常见 Type 2 charstring 运算；对嵌入的单字节 Type 1 字体解析 eexec/PFB、
  charstring、subroutine、seac 和 flex，并使用同一轮廓绘制；CID-keyed Type 1 支持
  单 FD 的 Binary/Hex `StartData`、CIDMap、SubrMap 和 `lenIV`，多 FD 字体仍使用回退；
- 所有 CID 字体共用文字布局主路径。外部和预定义 CMap 按 codespace 最短匹配切分
  1–4 字节字符码，再按 CID 读取 `/W`、`/DW`、`/W2` 和 `/DW2`；纵排保留垂直原点
  和带符号的推进。连续 `Tj`、`TJ` 调整、引号及 `q/Q` 共享真实 text matrix，只有
  原始单字节 `0x20` 应用 `Tw`。绘制、选择边界和文字裁剪采用同一份 glyph placement；
- 内置固定 PDF.js 版本的 168 份 Adobe binary CMap，按名称延迟解码并缓存，支持
  CID 映射、UseCMap、codespace、WMode 和缺少 ToUnicode 时的 Adobe CID→Unicode。
  这些资产是映射数据，包含来源和再分发许可，不包含字体程序；
- 对未嵌入 CID 字体缺少 FontDescriptor 的情况，使用局部默认 descriptor 恢复文本
  与宽度，不改变源 PDF 对象。默认 metrics 属于回退，字形外观仍依赖宿主字体；
- 文字保留实际的 `glyph_transform`（CTM、text matrix、字号、水平缩放、rise 和基线）；
  TrueType 轮廓按 em 绘制，不再把字体总包围盒压进单字的 advance box。SVG 普通文字
  也使用同一矩阵和 alphabetic baseline，避免 FreeText 外观中的文字落到裁剪区域之外；
- 保留 PDF text rendering mode、填充/描边颜色，并按 paint-site CTM 缩放路径线宽和虚线
  间距；文字 clipping mode 4–7 会在 `ET` 后按字形轮廓建立 clip path，同一 text object
  中的字形合并，后续 text object 求交，并遵守 `q/Q` 和 Form 的作用域。裁剪轮廓目前来自
  CFF、Type 1（含单 FD 的 CID-keyed 字体）和嵌入 TrueType 字体；其它字体没有可解码
  轮廓时不会伪造空 clip；非均匀 CTM 的
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
  metadata 读取入口；独立浏览器已提供目录、信息、页标签和附件/XMP 下载面板；JSON
  保留 pdflite 的 schema，尚未适配为 pdf.js 的返回结构；
- 跟踪 ExtGState 的填充/描边透明度和 SVG 可表达的 blend mode；
- 读取 Form XObject 的 `/Group /Transparency` 边界，把 isolated/non-isolated、knockout
  标记和嵌套 `group_path` 带入 display list；SVG 对 isolated 组使用 `isolation:isolate`，
  并保留 data 属性供后续 Canvas/WebGL compositor 使用；
- 对路径型彩色和 uncolored tiling pattern 生成 SVG `<pattern>`，应用调用处的基础
  色彩和 pattern matrix；填充的 `pattern` 和描边的 `stroke_pattern` 独立保留，单元和
  嵌套 Form 按各自资源解析颜色。多段显式 clipping 以嵌套 clipPath 表达；复杂单元的
  文字、透明组和重复边界仍待补齐。PatternType 2 的填充会解析为 mesh 并裁剪到原始
  路径，shading pattern 的描边尚未实现；
- 解析 PDF ShadingType 4/5/6/7 的二进制 mesh stream，支持 Gouraud、Coons patch 和
  tensor patch 的三角化。`PdfMeshTriangle` 保留每个顶点的 PDF-space 坐标和颜色；SVG
  后端用 barycentric 微三角近似 Gouraud 插值，Canvas/WebGL 宿主可以直接使用原始顶点颜色做
  像素级插值；
- 支持 PDF ImageMask、普通 `/Mask` color-key、图片 `/SMask`，以及常见的 Form soft
  mask；mask 会在图片的局部坐标系中合成，再交给页面 affine transform。Form mask 已处理
  `/BBox`、`/S /Alpha`、`/S /Luminosity` 和常见 `/TR` transfer function，资源字典会随
  Form 继承，路径的填充和描边分别转换颜色。inline CCITT 已通过 pdflite 解码为 PNG；
  复杂 backdrop/knockout 合成、backdrop 色彩空间和 JPEG2000/JBIG2 mask 仍未补齐；
- 提供 native CLI，方便用真实 PDF 调试，而不需要先接入浏览器。
- 提供独立浏览器 viewer，本地文件和拖放载入、多页滚动、缩放、旋转、下载可用。
  页面正文有透明 DOM text layer，原生 cursor 拖选、复制、Shift＋方向键和文档全选
  会映射回 MoonBit 的 glyph/item；跨页选区保留文件信息，缩放/旋转后恢复原生高亮。

渲染器会把相邻且共享同一个 soft mask 的 display-list item 放进一个 SVG mask
compositor group，再输出文字、路径和图片。这与 pdf.js 先合成 source group、再应用
soft mask 的顺序一致。Form XObject 的透明组边界也会保留下来；isolated 组可以直接
映射到 SVG isolation，non-isolated 组和 knockout 组目前保留结构化标记，完整的
backdrop/knockout 像素合成仍需要 Canvas/WebGL compositor。

## 本地运行

独立浏览器入口：

```bash
moon run tools/dev.mbtx 4312
```

打开 `http://127.0.0.1:4312/`，选择或拖入本地 PDF；文件读取和 PDF 解码在浏览器中进行。
开发服务器也提供已下载的对照 fixture，例如
`http://127.0.0.1:4312/?file=/fixtures/90ms_rksj_h_sample.pdf`。
浏览器交互检查（需要 Chromium，可在第二个参数指定可执行文件）：

```bash
moon run tools/browser_test.mbtx http://127.0.0.1:4312 /path/to/chromium
```

固定 PDF.js 版本的自动对照（需要 `reference/pdf.js` 的 `npx gulp generic` 构建）：

```bash
moon run tools/visual_test.mbtx tools/visual_cases.json /path/to/chromium
moon run tools/visual_summary.mbtx _build/visual-test-<run>/report.json
moon run tools/visual_contract_test.mbtx /path/to/chromium
```

每次生成新的 `_build/visual-test-*/index.html`，并排展示 PDF.js、MoonBit 与差异图，
JSON 包含原始像素差异、viewport/文本比较和样本 hash。普通模式成功表示完成测量；
末尾加 `--strict` 时，像素、viewport 或非空白文本差异都会让命令失败。
输入/渲染失败始终计入失败并返回非零，不会当作空白页匹配。

部署到静态服务器时，先执行 `moon run tools/build_web.mbtx`，然后发布 `web/`，
包含生成的 `_generated/pdf.js`。部署不需要 pdflite 的 native 程序，也不需要 PDF.js。

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
moon run tools/corpus.mbtx reference/pdf.js/test/pdfs vertical 1,2,3
```

第四个参数可以用逗号指定要检查的页码；默认仍为第一页。
每次运行创建新的 `_build/corpus-*/`，保存 SVG 和逐页 `report.json`。验证同时检查
退出码和新输出，存在失败或超时就返回非零。`data-pdf-placeholder="true"` 仅标记明确的
渲染占位。没有占位不代表内容完整，也不代表像素一致；当前结果和失败文件见
[`validation.md`](validation.md)。

`reference/pdf.js` 是本地对照 checkout，不会随项目提交；当前对照版本记录在
[`reference/README.md`](../reference/README.md) 中。它的 `test/pdfs` corpus 用来驱动
后续逐特性兼容测试。

## API 对照

| pdf.js 概念 | 本项目当前 API |
| --- | --- |
| `getDocument(data)` | `open_document(bytes)` |
| password callback | `open_document_with_passwords(bytes, user_password~, owner_password~)`；错误密码抛出稳定的 `SoftError` |
| `PDFDocumentProxy.numPages` | `PdfViewerDocument::page_count()` |
| `PDFDocumentProxy.getPage(n)` | `PdfViewerDocument::page(n)` |
| `PDFPageProxy.getViewport({ scale, rotation })` | `PdfPageModel::viewport(scale~, rotation~)` (`matrix` and SVG transform included) |
| `PDFPageProxy.getTextContent()` | `PdfViewerDocument::text_content(n)` / `PdfPageModel::text_content()` |
| DOM text layer | `PdfPageModel::text_layer(scale~, rotation~)` |
| cursor selection → source glyphs | `PdfPageModel::select_text(start_item, start_offset, end_item, end_offset)` |
| logical UTF-16 offsets → source glyphs | `PdfPageModel::text_sources()`；保留 item index、charcode 和字体，推断分隔符不伪造来源 |
| text/font recovery diagnostics | `PdfPageModel::text_diagnostics()`；`PdfViewerDocument::text_diagnostics(n)` 另含 CMap stream 诊断 |
| `PDFPageProxy.getOperatorList()` | `PdfViewerDocument::operator_list(n)` |
| `PDFPageProxy.render(...)` | `PdfViewerDocument::render_svg(n, scale~)` / `render_svg_with_rotation(...)` / cached `PdfPageModel::render_svg(...)` |
| `PDFFindController`-style text search | `PdfViewerDocument::search(query, options~)`; browser bridge `search_pdf` |
| named/explicit destination | `named_destinations()` / `named_destination(name)` / `destination_for_page(page_number)` |
| outline entries with navigation | `outline_navigation_json()` |
| document outline/info/attachments in browser | `document_info()` / `download_attachment(index)` / `download_metadata()` |

文档读取补充 API：`outline_json()`、`page_labels_json()`、`page_labels()`、
`attachments_json()`、`optional_content_json()`、`struct_tree_json()`、`info_json()`、
`attachment_manifest_json()`、`attachment_bytes(index)`、`metadata_bytes()`、
`named_destinations()`、`named_destination(name)`、
`destination_for_page(page_number)` 和 `outline_navigation_json()`。其中 `page_labels()` 始终返回每页的显示标签，没有标签树时使用一基
十进制页码；这与 pdf.js 返回 `null` 的约定不同。optional-content API 读取配置并参与
display-list 过滤；使用 `with_optional_content_state(pdf_optional_content_state(on=[...], off=[...]))`
可以按 pdflite 的 OCG 对象号切换显示，隐藏内容不会进入文本、选择或 SVG。浏览器图层面板和
usage/RBGroups 等交互语义仍是后续图层工作。

文字 API 共用逻辑阅读顺序，绘制列表的原始 index 不变。搜索复用 Unicode NFKD
和字符分类，兼容展开与组合符号重排后的结果返回原文 UTF-16 范围。
`text_sources()` 的 `[start, end)` 与 `text_content().text` 对应；一个连字或
surrogate pair 仍属于同一源 item，没有原始 PDF byte offset 或完整 CID/GID 信息。
页面诊断记录替换字符、宿主字体回退、缺轮廓/clip 等可观察情况；文档诊断还记录
CMap 坏 token、未闭合段、继承环和不可取得的 stream，并保留资源路径与直接对象号。
宿主回退或字面 U+FFFD 本身不证明文件损坏；浏览器字体实际加载成功与否不在诊断范围内。
文档诊断是显式调用，会重新构建页面与资源作用域，当前未接到浏览器 bridge/UI。

宿主可以用 `PdfFontFallback` 和 `with_font_fallbacks([...])` 为未嵌入字体指定本机 CSS
字体族；嵌入的 TrueType/OpenType 程序仍优先使用文档内字节。浏览器 bridge 还导出
`set_font_fallbacks(json)`，JSON 项形如 `{"pdf_name":"Helvetica","family":"Arial"}`，
可选 `weight`/`style` 只影响文字层的 CSS 元数据。viewer 不携带宿主字体文件，也不把字体
文件写入文档或下载结果。

destination API 把 PDF 内部跳转转换为 viewer 自有的 `PdfDestination`。它保留
`XYZ`/`Fit` 族的视图参数、当前文档的一基页码和 `resolved` 状态；指向其他文件的
destination 保留 `remote_page` 并设置 `remote`，宿主可以据此决定是否打开外部文件。
这些 API 目前提供解析和结构化数据，独立浏览器已把本地目录目标接到滚动定位；annotation
link layer 和远程 destination 的宿主策略仍待后续工作。

加密文档在没有密码或密码错误时不会进入页面树；调用
`open_document_with_passwords` 可传入用户密码或所有者密码。当前回归覆盖 40-bit
ARC4、128-bit ARC4 和 AESV2，浏览器 viewer 在本地弹出密码提示并在错误后重试；密码只在
浏览器内存中传递。

这不是声称已经达到 pdf.js 的覆盖率。复杂外部 CMap 继承及
reader 未保留的 codespace、完整字体 metrics 和标准 14 字体替代、
ICC 色彩管理、soft mask 的完整组合成语义、透明组的完整 backdrop/knockout 合成、
tiling pattern 的精确矩阵/裁剪和复杂单元、mesh 的最终像素级 Gouraud 合成、完整
annotation appearance/form 行为仍是后续工作；
当前 API 会先把可解析内容的页面位置和类型留在
display list 中，避免宿主丢失结构化信息。现阶段 SVG 输出适合调试和建立回归基线，不能
当作 pdf.js 的像素级替代品。

四字节字符码的高位保留在 `PdfTextItem.charcode` 的 `Int` 位模式中，可能显示为负数；
MoonBit 宿主可用 `reinterpret_as_uint()` 取得无符号值。原始 byte span 尚未暴露为公开
选择元数据。`select_text()` 的 offsets 是 DOM 使用的 UTF-16 code-unit offsets；
部分 ligature 的选择保留完整源 glyph 的 quad，不能解释成原始 PDF byte offset。
自动 PDF.js 像素对照、viewport 与文本诊断已经实现；首批样本仍存在明确差异，
结果见 [`validation.md`](validation.md#automated-pdfjs-visual-baseline)。

浏览器在 `#viewer` 上发出 `pdf-selection-change`，`event.detail` 包含
`file: { name, path }`、归并的 `text` 和每页的 `ranges`；选区清空时为 `null`。
本地文件的 `path` 为浏览器能获得的文件名，URL 载入保留传入的 URL。
这只是独立 viewer 的来源信息，未接入 OpenSeek。搜索结果通过 `pdf-search-change` 事件提供
查询词和几何丰富的结果；当前浏览器按 source item 高亮并滚动到活动结果。阅读顺序/bidi、
完整 Unicode normalization、批注与表单的 DOM 层、Worker/取消和大文件内存上限继续由
TODO 跟踪；缩略图和基础打印入口已经提供。

旋转参数按 pdf.js 规则只接受 `0/90/180/270`（允许等价的负数和大于 360 的整数）；
SVG 渲染遇到其它角度会返回 `PageRotationExpected`，不会静默近似成另一个角度。

## 参考实现和测试策略

`pdflite` 负责 PDF 语法、资源解析和内容条目生成；viewer 层负责页面模型、viewport、
glyph/mesh 补充解码、批注外观、SVG 序列化和选择映射。后续每补一个 renderer 特性，就从 pdf.js 的 corpus 选一个最小
fixture，同时保留一个 MoonBit snapshot/断言测试，先验证结构化输出，再验证浏览器视觉
输出。这样可以把“解析正确”和“渲染接近 pdf.js”分开定位。

更详细的分层和后续阶段见 [`architecture.md`](architecture.md)。
逐项能力差距、优先级和验收条件见 [`TODO.md`](TODO.md)。
