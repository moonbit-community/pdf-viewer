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
- `PdfPageModel.canvas_plan()` 输出结构化计划，由 `web/pdf-runtime.mjs` /
  `web/pdf-canvas.mjs` 进入 Canvas2D 像素主路径；网页正文、缩略图和 native CLI→plan→PNG
  共用该表示。`render_svg()` 保留自包含 SVG 兼容输出及近似分支诊断，不能替代像素合成；
  公开入口与目标矩阵见 [A2 验收](a2-acceptance.md)；
- JPEG、raw/inline、JPX 和 JBIG2 进入原始样本与 PNG 资源管线，不依赖浏览器原生
  image/jp2 或 image/jbig2 支持。[JPX](../codecs/jpx/README.md) 使用四目标 MoonBit
  解码器；[JBIG2](../codecs/jbig2/README.md) 使用 JS extraWasm / native Linux 适配，
  其它未接宿主的目标明确报不可用；
- DeviceGray/RGB/CMYK、CalGray、CalRGB、Lab、Indexed 和 Separation/DeviceN tint
  共用转换；原始样本保留 `/Decode`、color-key 和 Matte 的原色彩空间语义。
  ICCBased、输出 profile、Range、intent、OutputIntent 和 Default 色彩资源已接入
  LittleCMS，JS 使用随包 extraWasm，native Linux 动态加载 LittleCMS2；独立 Moon
  Wasm/Wasm-GC 保留合法 Alternate 并暴露能力。无 profile 的设备 CMYK 显示仍可用
  PDF.js SWOP 拟合。见 [色彩记录](a2-colour-validation.md)；
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
- 保留 PDF text rendering mode、填充/描边颜色、完整 graphics CTM 和独立 pen，
  Canvas 路径/文字描边保留非均匀缩放、剪切、线宽和虚线。文字 clipping mode 4–7
  在 `ET` 后按已有字形轮廓建立 clip，同一 text object 合并，后续求交并遵守 `q/Q` / Form。
  CFF、Type 1、嵌入 TrueType 和随包 Standard 14 复用 A1 轮廓；不能取得轮廓时不伪造空 clip。
  显式宿主 override / 非标准宿主 fallback 的独立非相似描边仍需轮廓能力，否则报告
  `PDF_TEXT_STROKE_GEOMETRY`。见 [Standard 14 pen](validation/standard14-pen.md)
  和 [宿主边界](validation/host-text-pen.md)；
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
- ExtGState 填充/描边透明度、16 种 PDF blend、独立 shape/alpha、isolated/non-isolated
  backdrop、knockout、嵌套组、组色彩空间及文字 TK 已进入共享 Canvas 合成路径；
  Alpha/Luminosity soft mask 保留安装 CTM、BC、TR、边界与作用域。SVG 只提供兼容降级，
  实际合成及参考分歧见 [透明合成记录](a2-compositing-validation.md)；
- 彩色/uncolored tiling pattern 保留独立 fill/stroke、调用基础色、base matrix 和正负
  lattice；完整单元计划包含文字、图片、Form、透明组、clip 和局部资源，逐 tile 使用实际
  backdrop。PatternType 2 的填充/描边及自身 ExtGState 通过共享 replay 处理，见
  [shading pattern](a2-shading-pattern-validation.md) 和 [pattern stencil](validation/image-patterns.md)；
- ShadingType 1–7 保留函数或原始样本分量，先插值再应用 Function/色彩转换；支持
  axial/radial Extend、Gouraud、Coons/tensor、受检验的 lookup 与设备空间细分。
  SVG 微三角仍是兼容近似；超预算或不支持的采样显式报错，见 [shading](a2-shading-validation.md)；
- ImageMask、原始域 color-key、JPEG/JPX/JBIG2 的 explicit/soft mask、嵌入 alpha 和
  Matte 共用有界图像管线；保留 SMask 优先级，避免重复 alpha，并提供减采样路径。
  真实样本和保留的采样/边缘差异见 [图像采样](validation/image-sampling.md)
  与 [JPEG](jpeg-decoder.md)；
- 提供 native CLI，方便用真实 PDF 调试，而不需要先接入浏览器。
- 提供独立浏览器 viewer，本地文件和拖放载入、多页滚动、缩放、旋转、下载可用。
  页面正文有透明 DOM text layer，原生 cursor 拖选、复制、Shift＋方向键和文档全选
  会映射回 MoonBit 的 glyph/item；跨页选区保留文件信息，缩放/旋转后恢复原生高亮。

Canvas 主路径从结构化计划 replay，保留组、mask、pattern 和 shading 的源顺序与资源，
不会先把整页 SVG 栅格化后冒充 PDF 合成。`initializePdfGraphics()` 在解析前安装
JS codec/CMM 宿主；`renderPdfPage()` 安装共享 pattern/shading painter 并调用
`renderPdfCanvas()`。strict replay 拒绝未解决的能力缺口；viewer 的 warning preview
保留诊断和可见警告。资源缓存/深度/工作面预算已有边界，但不代表全文档峰值 RSS 或硬取消。
详见 [A2 目标、资源限制与公开入口](a2-acceptance.md)。

A2 的 shipped web bridge/runtime 已在 native Canvas 宿主验证；当前记录中的 Chromium
因 socket EPERM 无法启动，不据此声称合并后的浏览器 DOM/交互测试通过。

## 本地运行

先安装 MoonBit 和 Node 22.13.0+ / npm，再安装锁定的浏览器资产依赖；独立浏览器入口：

```bash
npm ci --prefix tools/web-assets --ignore-scripts --omit=optional
moon run tools/dev.mbtx 4312
```

`tools/web-assets/package.json` 固定 `lcms-wasm@1.0.5` 和
`pdfjs-dist@6.4.299`，lockfile 固定依赖树与包完整性。构建调用
`node tools/prepare_web_assets.mjs`，验证版本和资产 SHA-256 后复制 LittleCMS
JS/Wasm 与独立 JBIG2 Wasm；这些生成资产不进入 Git。构建不会自动安装 npm
依赖，更新 lockfile 后应重新执行 `npm ci`。单独运行 JS codec/CMM 测试前也可
直接执行 prepare 命令。native JBIG2 C++ 源码和文本许可证继续随仓库维护。
这是固定发布资产的可重复获取，不代表已验证从 C 源码逐字节重建 Wasm。

打开 `http://127.0.0.1:4312/`，选择或拖入本地 PDF；文件读取和 PDF 解码在浏览器中进行。
解码、搜索和 Canvas 计划生成运行在 module Worker；主线程执行 Canvas replay，
正文与缩略图按可见范围挂载。Worker 与主线程分别初始化所需的图像/色彩宿主。
部署时提供完整 `web/` 目录，包括 `pdf-client.js`、`pdf-worker.js`、`page-scheduler.js`、
`annotation-layer.js`，以及 Canvas runtime、随包 codec/CMM 资产和生成的 `_generated/pdf.js`，
通过 HTTP 服务加载这些 ES modules。
宿主诊断可在浏览器控制台读取：

```js
const host = await import("./viewer.js");
await host.runtimeDiagnostics();
// 关闭文档并释放 Worker、任务队列和页面 DOM：
host.closeDocument();
```

页面模型缓存限 8 页/估算 32 MiB，序列化渲染缓存限 12 项/24 MiB；
这些是缓存预算，原始文档、临时解码及浏览器字体/图片仍占用额外内存。
工具栏打印和 Ctrl/Cmd+P 会按原始页面尺寸准备全文件，再打开打印对话框，
打印后释放临时 DOM。直接用浏览器菜单打印时，页面会提示使用该入口。
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

A1 字体、来源和 reader 恢复的复跑入口：

```bash
moon run tools/visual_test.mbtx tools/font_post_cases.json /path/to/chromium
moon run tools/visual_test.mbtx tools/standard14_cases.json /path/to/chromium
moon run tools/visual_test.mbtx tools/reader_cases.json /path/to/chromium
moon run tools/text_provenance_corpus.mbtx tools/font_post_cases.json
moon run tools/text_provenance_corpus.mbtx tools/reader_cases.json
moon run tools/reader_corpus.mbtx
moon run tools/cmap_corpus.mbtx
```

corpus 工具使用根模块固定的 pdflite，每份输入独立进程并有超时；失败文件和错误
留在报告中，不将载入扫描换算成视觉兼容率。验收记录见
[validation.md](validation.md#a1-completion-validation)。

每次生成新的 `_build/visual-test-*/index.html`，并排展示 PDF.js、MoonBit 与差异图，
JSON 包含原始像素差异、viewport/文本比较和样本 hash。普通模式成功表示完成测量；
末尾加 `--strict` 时，像素、viewport 或非空白文本差异都会让命令失败。
输入/渲染失败始终计入失败并返回非零，不会当作空白页匹配。

部署到静态服务器时，先执行 `moon run tools/build_web.mbtx`，然后发布 `web/`，
包含生成的 `_generated/pdf.js`、codec/CMM 资产和许可证。部署不需要 pdflite 的
native 程序；`pdfjs-dist` 仅提供独立 JBIG2 资产，不部署 PDF.js renderer。
Worker 和主线程通过原有同源 URL 加载这些资产，打开 PDF 时不会请求 npm/CDN。

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

这些 `.svg` 命令选择兼容输出。像素主路径先导出公开 Canvas 计划，再由宿主 replay：

```bash
moon run --target native cmd/main -- ./sample.pdf /tmp/page-1.canvas.json 1
PDF_CANVAS_PACKAGE=/absolute/path/to/canvas-host/package.json \
  node tools/render_canvas.mjs /tmp/page-1.canvas.json /tmp/page-1.png
```

首次使用须先构建 shared web bridge 并准备 Canvas 宿主，见
[native Canvas setup](validation/native-canvas-setup.md)。库宿主可继续使用
`open_document`、`page`、`render_svg`，或从 `page.canvas_plan()` 取得同一绘制计划。

CLI 成功写入输出返回 `0`；读取、渲染、页码越界或写文件失败返回 `1`；参数错误返回
`2`。SVG 批量验证可以直接运行 MoonBit 脚本：

```bash
moon run tools/corpus.mbtx
```

检查文字的字符码、串内字节范围和字体来源，可以输出独立 JSON：

```bash
moon run --target native cmd/text_provenance -- ./sample.pdf /tmp/page-1-text.json 1
moon run tools/text_provenance_corpus.mbtx tools/font_post_cases.json
```

检查器核对逻辑来源、byte range、字符码和调用位置；返回 `0` 表示这些关系通过，
不代表字形外观已与 PDF.js 一致。批量结果保存在 `_build/text-provenance-*/`。

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
| source glyphs → PDF strings and font IDs | `PdfViewerDocument::text_provenance(n)`；返回串内 bytes/range、Form 调用路径和可解析的 CID/GID/字形名 |
| PDF spelling → verified byte spans | `PdfViewerDocument::text_lexical_sources(n)`；空复制字形也保留来源，文件偏移只在可核对时返回 |
| text runs and paragraphs | `PdfPageModel::text_structure()`；共同 UTF-16 范围、几何和来源，段落由几何推断 |
| text/font recovery diagnostics | `PdfViewerDocument::text_recovery_diagnostics(n)`；包括空复制字形、原字符串 bytes 和实际字体/CMap 对象号；既有 `text_diagnostics` API 保留 |
| skipped damaged page-tree branches | `PdfViewerDocument::reader_diagnostics()`；资源路径、对象号和原因 |
| `PDFPageProxy.getOperatorList()` | `PdfViewerDocument::operator_list(n)` |
| `PDFPageProxy.render(...)` | `PdfPageModel::canvas_plan(scale~, rotation~)` → `renderPdfPage()` / `renderPdfCanvas()`；兼容 API 保留 `PdfViewerDocument::render_svg(n, scale~)` / `render_svg_with_rotation(...)` / `PdfPageModel::render_svg(...)` |
| graphics capability diagnostics | `PdfPageModel::graphics_diagnostics()`；Canvas plan 的 `diagnostics`、replay 结果和 SVG metadata 保留相关诊断 |
| `PDFFindController`-style text search | `PdfViewerDocument::search(query, options~)`; browser bridge `search_pdf` |
| named/explicit destination | `named_destinations()` / `named_destination(name)` / `destination_for_page(page_number)` |
| outline entries with navigation | `outline_navigation_json()` |
| document outline/info/attachments in browser | `document_info()` / `download_attachment(index)` / `download_metadata()` |
| readonly annotation interactions | `PdfViewerDocument::annotation_layer_json(n)`；PDF-space 坐标、原 `/Annots` 索引、popup 内容和链接目标 |
| annotation print intent | `PdfPageModel::with_print_annotations()`；bridge `render_print_page`，与屏幕缓存分开 |

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
surrogate pair 仍属于同一源 item。`text_provenance(n)` 按同一顺序返回每个非空复制
字形的来源：内容流引用序列、嵌套 Form 的对象号及调用位置、操作/字符串操作数索引、
解码后字符串内的 `[byte_start, byte_end)` 和原字符码 bytes。TJ 操作数索引包含数值
字距；引号操作分别使用 0/2。位置以串的 bytes 为单位，经过 PDF 转义、解压和解密，
不是文件中的词法偏移；串可能横跨多个拼接的内容流，因此保留整个流引用序列。
来源还保留实际活动字体和嵌入程序对象号，遵守 Form 字体继承、`q/Q` 和 ExtGState。
CID/GID 与 ToUnicode 独立；Type 1/Type 3 使用字形名，宿主字体 GID 和无法解析的映射
返回空值，非法/截断 CMap code 仍保留 bytes。空复制字形与推断分隔符不增加逻辑来源项。
该检查 API 显式调用时才采集 bytes 和解析字形来源，现有公开页面/文字 record 不变。
JSON 导出沿用 MoonBit 的 Bytes 格式：可打印 ASCII 保留，其余 byte 使用 `\xHH`；
`@json.from_json` 可以无损恢复，不能把这个字符串直接当作 UTF-8 原码。
页面诊断记录替换字符、宿主字体回退、缺轮廓/clip 等可观察情况；文档诊断还记录
CMap 坏 token、未闭合段、继承环和不可取得的 stream，并保留资源路径与直接对象号。
`text_recovery_diagnostics(n)` 还记录编码、metrics、字体字典、未知 Unicode 和非法 CMap
字符码的回退，以及不可解码字体流；绑定对象与绘制使用同一套 Tf/Form/ExtGState 状态。
它保留空复制字形的 item/charcode/string_source，此时逻辑 `source` 为 `None`，不编造 UTF-16
范围。既有文档 `text_diagnostics(n)` 只投影有逻辑来源的记录，现有 record 不变。
词法 sidecar 将字符串 bytes 对应到 literal/hex 的解码流拼写；压缩/加密流给解码位置及可取得的
完整原流范围，只有原始 backing bytes 可核对且没有变换时才提供字符的文件位置。
页树循环/深度超过上限时，读取器保留可取得的有效页面，`reader_diagnostics()` 报告跳过分支；
这与 PDF.js 延迟读取坏页的模式不同，恢复后的 `page_count()` 是保留的可读页数。
宿主回退或字面 U+FFFD 本身不证明文件损坏；浏览器字体实际加载成功与否不在诊断范围内。
文档诊断是显式调用，会重新构建页面与资源作用域，当前未接到浏览器 bridge/UI。

宿主可以用 `PdfFontFallback` 和 `with_font_fallbacks([...])` 为未嵌入字体指定本机 CSS
字体族；嵌入的 TrueType/OpenType 程序仍优先使用文档内字节。浏览器 bridge 还导出
`set_font_fallbacks(json)`，JSON 项形如 `{"pdf_name":"Helvetica","family":"Arial"}`，
显式匹配的 override 会抑制随包 Standard 14 程序/轮廓，选择宿主文字路径；可选
`weight`/`style` 参与宿主 SVG 文字与文字层的字体选择，不只是文字层元数据。
独立非相似文字描边若无宿主轮廓 callback，strict replay 会拒绝并保留几何诊断。
清空 override 会清除页面缓存并恢复默认 bundled 路径，见
[Standard 14 pen](validation/standard14-pen.md)。viewer 随包标准字体有单独的
[来源与许可](../assets/standard14/README.md)，不会把用户的宿主字体文件写入 PDF 或下载结果。

destination API 把 PDF 内部跳转转换为 viewer 自有的 `PdfDestination`。它保留
`XYZ`/`Fit` 族的视图参数、当前文档的一基页码和 `resolved` 状态；指向其他文件的
destination 保留 `remote_page` 并设置 `remote`，宿主可以据此决定是否打开外部文件。
独立浏览器已把本地目录和批注链接接到页码/历史；批注链接还会应用 XYZ/Fit 视图参数。
URI 使用原生锚点；远程、未解析或不支持的 action 保持禁用。

加密文档在没有密码或密码错误时不会进入页面树；调用
`open_document_with_passwords` 可传入用户密码或所有者密码。当前回归覆盖 40-bit
ARC4、128-bit ARC4 和 AESV2，浏览器 viewer 在本地弹出密码提示并在错误后重试；密码只在
浏览器内存中传递。

这不是声称已经达到 pdf.js 的覆盖率。字体、CMap 继承、来源和确定性 Standard 14 主路径已经接通；
罕见字体格式、无法恢复的损坏流、歧义几何布局与像素差异保留在验证报告中。
A2 的 ICC、组/mask、pattern、shading 与 affine pen 已进入 Canvas 主路径，
目标差异、资源限制和真实页面残差见 [A2 验收](a2-acceptance.md)。完整 annotation
appearance/form 行为、可访问性、CI 和更大的真实文档基线仍是后续工作。
宿主生命周期、Worker/取消、虚拟化与有界缓存已接入；其上游验收不替代 A2 合并后的
DOM/压力复跑，也不保证全文档峰值内存。SVG 输出保留调试/兼容用途及明确诊断，
不能当作 Canvas 主路径或 PDF.js 整页像素一致的替代证明。

四字节字符码的高位保留在 `PdfTextItem.charcode` 的 `Int` 位模式中，可能显示为负数；
MoonBit 宿主可用 `reinterpret_as_uint()` 取得无符号值。原始 byte span 通过来源 sidecar 暴露，
选择结果沿用稳定的 glyph index。`select_text()` 的 offsets 是 DOM 使用的 UTF-16 code-unit offsets；
部分 ligature 的选择保留完整源 glyph 的 quad，不能解释成原始 PDF byte offset。
自动 PDF.js 像素对照、viewport 与文本诊断已经实现；首批样本仍存在明确差异，
结果见 [`validation.md`](validation.md#automated-pdfjs-visual-baseline)。

浏览器在 `#viewer` 上发出 `pdf-selection-change`，`event.detail` 包含
`file: { name, path }`、归并的 `text` 和每页的 `ranges`；选区清空时为 `null`。
本地文件的 `path` 为浏览器能获得的文件名，URL 载入保留传入的 URL。
全选或跨页选区可以包含尚未挂载的页面；复制内容和该事件来自 Worker 的来源范围。
虚拟化后原生 `getSelection().toString()` 只覆盖当前挂载的 DOM，宿主应读取事件中的完整文字。
这只是独立 viewer 的来源信息，未接入 OpenSeek。搜索结果通过 `pdf-search-change` 事件提供
查询词和几何丰富的结果；当前浏览器按 source item 高亮并滚动到活动结果。
批注 popup 通过点击或键盘 Enter 打开，Escape/关闭会返回控件焦点；markup 的文字拖选继续保留。
`pdf-annotation-activate` 事件包含 `page`、原始 `index`、`subtype` 和 `link`，便于宿主定位来源。
页面卸载、重绘或关闭文档会清空 popup 内容。打印按独立 Print 标志选择外观，
NoView/Print 批注可以仅出现在打印里，Hidden 会同时抑制两种用途。
交互与剩余外观限制见 [批注验收](validation.md#readonly-annotation-interaction-and-print-intent)。
歧义布局/tagged PDF、完整 locale/case-fold 策略、批注外观和表单控件继续由 TODO 跟踪；
Worker/取消、虚拟化和缓存预算的边界与压力数据见
[浏览器宿主验证](validation.md#browser-host-lifecycle-scheduling-and-pressure)。

旋转参数按 pdf.js 规则只接受 `0/90/180/270`（允许等价的负数和大于 360 的整数）；
SVG 渲染遇到其它角度会返回 `PageRotationExpected`，不会静默近似成另一个角度。

## 参考实现和测试策略

`pdflite` 负责 PDF 语法、资源解析和内容条目生成；viewer 层负责页面模型、viewport、
glyph/图像补充解码、色彩/合成适配、批注外观、Canvas 计划、SVG 兼容输出和选择映射。
后续每补一个 renderer 特性，就从 pdf.js 的 corpus 选一个最小
fixture，同时保留一个 MoonBit snapshot/断言测试，先验证结构化输出，再验证浏览器视觉
输出。这样可以把“解析正确”和“渲染接近 pdf.js”分开定位。

更详细的分层和后续阶段见 [`architecture.md`](architecture.md)。
逐项能力差距、优先级和验收条件见 [`TODO.md`](TODO.md)。
