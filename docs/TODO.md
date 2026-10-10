# PDF.js 对齐 TODO

更新日期：2026-10-11。最终产品目标是完整阅读器，包括批注编辑、表单填写和签名。
本文件的 **50 项是只读渲染与浏览基线**；编辑、保存和签名在后面的扩展路线单列，
尚未纳入这 50 项统计。Office viewer、OpenSeek 接入和文档 JavaScript 执行不在当前任务内。

对照版本是本地 `reference/pdf.js` 的
`89b500f5e1d98ed89bb90211e45b28730b2d99ac`；PDF 读取依赖为 pdflite `0.2.2`。
这里的“对齐”包括可见输出、文本与选择、独立浏览器体验和稳定性，
不要求照抄 PDF.js 的内部实现或所有返回值结构。

当前内核按字体/文字、图形/图像两条主线推进，文件边界见 [两条工作线](PARALLEL.md)。
浏览器与后续阅读器功能另行推进。主线拆分不改变完成状态；
本文件仍是 50 项 TODO 的唯一验收/统计清单。

## 还差多少

当前明确跟踪 **50 项，分为 14 个能力领域；完成 25 项，剩余 25 项**。
按条目数量看是 **25/50（50%）**，但这只是清单进度，不是 PDF.js 的视觉兼容率。
剩余项按优先级分为 P0 11 项、P1 12 项、P2 2 项；其中部分已有基础实现。
这些项大小不等，
有的只是一个语义修正，有的需要接入解码器或合成器并补 PDF 适配，所以不能把
50% 当成实际兼容率，也不能按 25 项全部从零开发估算工作量。

按阶段看，P0 一共有 23 项，已经完成 12 项，仍有 11 项会直接影响通用文档的图像、描边、颜色、合成或图层可见性；P1 一共有 25 项，已经完成 13 项，仍有 12 项主要影响完整的只读工作流和真实文档覆盖；P2 的 2 项都未开始，分别是网络 range/增量读取和 XFA。完成剩余 P0 并重新跑扩大的 PDF.js 样本后，才能判断核心渲染是否达到可发布的高保真门槛；完成 P1 后，才接近完整的独立只读 viewer；P2 是大文件和特殊文档覆盖，不计入核心静态 PDF 门槛。

按交付门槛展开，剩余功能可以这样看：

| 交付门槛 | 必须完成的剩余项目 | 结论 |
| --- | --- | --- |
| 核心高保真渲染 | P0：G-01、G-03、I-01、I-02、C-01、M-01 至 M-03、H-01、H-03、A-02 | 完成前不能称为 PDF.js 级通用渲染器；这些项目会造成错位、漏图或明显颜色/合成错误 |
| 可发布的独立只读 viewer | 上述 P0 + P1：P-02、G-02、I-04、C-03、H-02、A-01、A-03 至 A-04、U-05、X-01、V-02 至 V-03 | 完成后才覆盖主要真实文档和完整的浏览器只读工作流 |
| 大文件与特殊格式 | P2：R-03、X-02 | 解决 range/增量读取和 XFA；不影响当前静态 PDF 核心门槛 |

计数边界：这 50 项统计的是当前核心对齐主路径。OCG 的 usage、RBGroups、Locked
控制的 UI 语义和浏览器图层面板尚未完成，也没有单独的 UI 条目；它们属于
浏览器产品扩展，因此暂不计入 25 项剩余。如果把图层面板也
定义为必须的 PDF.js UI，需要另加一个 P1 条目，剩余数会变为 26 项。

已完成 F-01（水平外部 CMap）、F-02（Adobe 预定义 CMap）、F-04（CID 纵排）和 I-03（inline image 解码路径）
和 T-03（编码相关字距），以及 U-01（独立浏览器）、U-02（cursor 选择层）
和 U-03（跨页选择映射及重投影）、V-01（自动对照工具与首批像素基线）。
R-01（密码文档载入）和 P-01（页面边界及 UserUnit）也已完成主路径和回归验证。
已完成 D-01 的库/API 主路径：named/explicit destination、XYZ/Fit 族、当前文档页解析和
远程 destination 标记均有结构化 API 与回归测试；浏览器目录点击和滚动定位已在 D-03 主路径接通，annotation link layer 仍由 A-04 跟踪。
已完成 D-03 的浏览器文档导航/信息主路径：outline、page labels、Info、XMP metadata
和附件清单/下载均接入独立 viewer，并由真实 Chromium fixture 回归覆盖。
本轮完成 A1 的全部 8 个主路径项目：R-02、F-03、F-05、F-06、F-07、T-01、T-02、T-04。
最后补齐的 5 项包括真实 Adobe CMap 继承、字体格式与损坏程序覆盖、统一文字恢复诊断，
以及有界页树恢复。`tracemonkey.pdf` 第一页的 1,549 个缺失嵌入轮廓已恢复。
验收、真实差异和保留回退见 [A1 收尾验证](validation.md#a1-completion-validation)。

这轮完成 C-02 的校准色彩转换主路径：CalGray、CalRGB、Lab 进入路径、文字、图片、
渐变、pattern 路径和 Form mask 路径的共享转换。真实 CalGray/CalRGB/Lab 的 21 页中，
1,432 个色块内部各抽样 16×16 像素，RGB 全部与固定 PDF.js 对照一致；整页仍有文字、
阅读顺序、图像插值和边缘差异。新增了独立填充/描边 tiling paint 和原始样本 color-key
mask 处理；它们扩大 H-01/I-04 的覆盖，但这两项仍未完成。合法 stream 注释引起的
空白页在 viewer 恢复层修正，依赖源码未修改。证据见
[validation.md](validation.md#calibrated-colours-and-original-image-samples)。

现在有可运行的 native CLI、页面模型、SVG 输出和独立的浏览器 viewer。
当前 374 个测试在四个后端通过，浏览器有 39 项交互检查。原自动 PDF.js 对照已经测量
20 份 PDF 的 57 个页面/旋转组合：全部得到报告，55 个组合存在像素或文本差异。
这些是按特性挑选的样本，**仍不能给出可信的视觉兼容率**。
转换成功、没有占位、测试通过，都不能单独证明没有漏画或排版错误。
基线细节见 [validation.md](validation.md)。

A1 收尾另测量了 10 个字体、16 个标准字体和 5 个 reader 页面组合，均无测量失败，
也均保留像素或文本差异。989 份本地 PDF 的 reader 扫描有 952 份成功、37 份失败；
10 份字体与 5 份 reader 样本的来源/词法/run/段落/诊断连接检查通过。
这些检查证明接入和恢复主路径，不把载入成功或测试数量当成视觉一致。

最新图片/字体定向对照另外测量了 10 个页面/旋转组合，0 个测量失败，7 个仍有差异，
3 个在记录容差内。`issue10339_reduced.pdf` 的 0/90° 和 `issue4246.pdf` 的图片输出
均为 0 个超容差像素；这验证了 Lab 图片采样与高分辨率 raw 遮罩路径。
JPEG + SMask + Matte、color-key 边缘和复杂合成仍待完成，不能据此勾选 I-04。

按实际风险看，当前离“高保真只读预览”最近的阻塞项主要集中在三组：

- **文字可靠性**：A1 主路径已验收；罕见字体格式仍使用有诊断的回退，未标记的歧义阅读结构由 X-01 跟踪，整页描边/栅格化和复制差异继续测量。
- **像素渲染**：完整 CTM 描边、可验证的像素后端、JPX/JBIG2、ICC 色彩、透明组和 mesh shading（G-01、G-03、I-01 至 I-02、C-01、M-01 至 M-03、H-03）。
- **可用工作流**：Worker、虚拟化、内存控制和批注/链接交互（U-05、A-04）；搜索主路径已经完成，复杂几何阅读顺序已由 T-01 验证，歧义结构仍需 PDF tags。

因此目前可以稳定演示基础页面浏览、缩放、旋转和 cursor 文字选择，但还不能把结果描述为 PDF.js 级别的通用渲染器。完成 P0 后，才适合重新评估真实的视觉兼容率；P1/P2 则决定文档覆盖面和产品完整度。

| 领域 | 当前已有 | 主要缺口 | 剩余项数 | 对应项目 |
| --- | --- | --- | ---: | --- |
| 文档载入 | bytes 读取、密码入口、压缩对象恢复、有界页树恢复和定位诊断 | 增量读取；不可恢复坏流/xref 保留错误 | 1 | R-03 |
| 页面/API | 页面模型、viewport、旋转、边界和 UserUnit、显示列表 | 宿主生命周期、错误分类和资源释放 | 1 | P-02 |
| 字体/编码 | TrueType、CFF、Type 1 轮廓与恢复；复杂外部 CMap；168 份 Adobe CMap；CID 纵排；Standard 14 固定程序、AFM、编码与裁剪 | 罕见 cmap/厂商 post、多 FD Type 1 等保留有诊断的回退；像素差异仍测量 | 0（主路径） | - |
| 文字 | glyph transform、逻辑阅读顺序、选择/裁剪、编码字距、字节/词法与 run/段落来源、统一恢复诊断 | 无 tags 的歧义结构、未编码的 Unicode 无法自动恢复 | 0（主路径） | - |
| 矢量 | 常见路径、虚线、显式 clip、SVG 输出 | 非均匀描边、精确 raster 输出 | 3 | G-01 至 G-03 |
| 图片 | JPEG、raw/inline 图片、inline CCITT、ImageMask、原始 1/2/4/8/16-bit 样本和 Decode、raw color-key/SMask/Matte、affine 图片采样 | JPX/JBIG2 解码、encoded-image mask/Matte、color-key 边缘和大图 | 3 | I-01、I-02、I-04 |
| 色彩 | 设备色彩、SWOP 拟合、CalGray/CalRGB/Lab、Indexed、Separation/DeviceN tint | ICC、专色特殊分支与 overprint | 2 | C-01、C-03 |
| 透明合成 | alpha、部分 blend、组标记、常见 soft mask | backdrop、knockout、精确 mask/blend | 3 | M-01 至 M-03 |
| pattern/shading | 彩色路径 tiling、路径型 uncolored pattern 的基础色、shading 1–7 的部分输出 | pattern 的视觉精确度、复杂 tiling、逐像素插值 | 3 | H-01 至 H-03 |
| 批注/只读表单 | AP 外观、基本几何、字段元数据、简单 widget | 无 AP 的完整排版、交互层和子类型覆盖 | 4 | A-01 至 A-04 |
| 导航/图层 | outline、labels、attachments、metadata 读取；destination 结构化解析；OCG 实际过滤；浏览器目录/信息/附件面板 | OCG usage/RBGroups/Locked 面板语义另计扩展；批注链接由 A-04 跟踪 | 0（核心） | - |
| 浏览器体验 | 独立应用、文件载入、多页滚动、缩放/旋转、cursor 选择及复制、跨页来源映射、全文搜索与结果高亮、目录/缩略图/Info、打印入口、分页模式、页码历史 | Worker/虚拟化、避免每次操作重建全文件、批注/链接 DOM | 1 | U-05 |
| 可访问性/XFA | structure tree 读取 | 可访问的 DOM、只读 XFA 页面 | 2 | X-01、X-02 |
| 验证/性能 | 四后端测试、多页 CLI corpus、Chromium 交互测试、PDF.js 像素/viewport/文本对照及差异图、页面缓存 | 扩大基线覆盖、Worker/取消/缓存上限、大文件与 CI | 2 | V-02、V-03 |

“当前已有”只描述实现基础。除非待办满足验收条件并有证据，不把整个领域标为完成。

## 先复用，再补 PDF 适配

每项先检查已有依赖、Mooncakes 和成熟底层库，做最小接入验证，再安排实现。
候选版本、源码/API 核查、已知限制见 [生态复用候选](codec-candidates.md)。
以下覆盖全部 25 个剩余 ID，并保留已完成 A1 的复用记录；“有候选”不代表已经接入或满足验收。

| TODO 范围（含复用记录） | 优先复用的能力 | 本项目保留的工作 |
| --- | --- | --- |
| R-02、F-03、T-04（已完成） | pdflite reader、lexer/CMap、现有 Adobe CMap 资产及同版本 Flate | PDF 继承、严格 reader 前的展开/循环边界、局部恢复和可定位诊断；不另造 reader 或流解码器 |
| R-03 | 浏览器 Fetch/Streams/Range；可选 `mizchi/js_web` 绑定 | 先确认 pdflite 可消费分段数据，再接数据源、xref/对象按需加载；网络 API 本身不完成增量 PDF 读取 |
| P-02、U-05、V-02 | Web Worker、MessageChannel、AbortController、IntersectionObserver；已用 async 或可选 `mizchi/js_web` | 文档代次、任务取消、可见页调度、缓存预算与释放；先用宿主 API，不重造线程/网络库 |
| F-05、F-06（已完成） | 已接入 `mizchi/font` 0.7.4 的 cmap/post；已有 TrueType/CFF/Type 1 轮廓路径 | PDF 选表/编码、少量旧格式转换、Widths/FontMatrix 和损坏程序恢复；缺 cmap 子集与库尚不支持的复合轮廓保留现有路径 |
| F-07 | pdflite 已有 Standard 14 AFM；现有字体回退入口与可用的字体资产 | 确定字体来源/许可、缺字策略和像素门槛；不重新制作字体或 AFM 数据 |
| T-01、T-02 | `moonbit-community/bidi`；相关 normalization 扩展复用 `moonbit-community/normalization` | 字符索引→UTF-16→源 glyph/bytes 映射、PDF 已定位文字的逻辑顺序、多栏/表格；不能直接把视觉重排字符串当作复制结果 |
| G-01、G-02、G-03 | 浏览器 Canvas 2D；评估 `mizchi/svg`/`bobzhang/vg` 基础绘制；native 可选 Skia 绑定 | 保留结构化路径、完整 CTM、PDF clip/描边状态，验证后端差异；不默认自建通用 rasterizer |
| I-01 | `trkbt10/jpeg2000` 候选，优先验证或扩展其现有解码能力 | 公共多组件 API、JP2 色彩/alpha、PDF JPX 语义与真实像素；当前入口的 component0 输出不足以直接完成彩色 JPX |
| I-02 | 继续检索 MoonBit JBIG2；评估成熟解码器的适配/绑定或移植 | globals/segment/Mask 接口、目标与资源限额；尚未确认可直接用的 MoonBit 包，不因此默认从零写 codec |
| I-04 | `mizchi/image` / `walkzzz/image` JPEG 解码；现有 raw mask、Matte 和采样代码 | 原始组件与 RGB 输出边界、PDF ColorTransform/Decode、encoded-image alpha/Matte；先复用，再补具体编码缺口 |
| C-01 | 评估 LittleCMS 等 ICC 转换引擎；`enanandesu/icc` 只可辅助元数据/诊断 | ICCBased 的组件/Range/alternate、输出空间与各后端适配；元数据解析不等于颜色转换 |
| C-03 | A2 的共享色彩转换与合成后端 | PDF tint/domain/colorant 与 overprint 色版语义；不另建第二套颜色引擎 |
| M-01、M-02、M-03、H-01、H-02、H-03 | A2 选定后端的 surface、clip、blend、渐变/网格绘制能力 | PDF group/backdrop/knockout、BC/TR、pattern 资源/矩阵与 patch 插值适配；通用混合/光栅算法优先复用，确认缺口才补 |
| A-01、A-02、A-03、A-04 | pdflite 批注/字段模型、字体 metrics；原生 DOM/表单控件与 Pointer Events | AP/DA/DR、字段继承/状态、屏幕/打印外观、旋转命中和 popup/link；通用输入控件不从零实现 |
| X-01 | pdflite structure tree 与浏览器 DOM/ARIA | tagged PDF 来源与阅读顺序关联、辅助技术验收；不另写通用可访问性框架 |
| X-02 | `moonbit-community/XMLParser` | XFA 的模板/数据关联、分页布局和字体适配；XML parser 只覆盖解析子任务 |
| V-03 | 既有 MoonBit/Chromium/视觉 runner 与 CI 平台 | 固定依赖/样本、区分已知差异和新回归、保存报告；不重建测试框架 |

接入验证至少记录公共 API/数据约定、所需目标的编译结果、真实 fixture 的差异
和耗时/内存。纯 MoonBit 候选先验证本项目四后端；native FFI 或额外 Wasm 模块
要明确交付目标和构建成本，不能记成四后端通用能力。
只有候选确实缺少所需能力且扩展/绑定不合适，才开具体自研子任务并记录原因。
已有字体/图像实现逐步替换，在候选通过回归前保留可用路径。

## 优先级与验收规则

- P0：直接造成缺字、错位、漏图、明显颜色/合成错误，或阻碍实际预览与验证。
- P1：扩大真实文档覆盖，完善只读工作流和可靠性。
- P2：较晚处理的大文件能力或特殊文档类型。
- 勾选要求：代码进入主路径、存在有意义的回归测试，并记录验证结果与剩余限制。
  涉及渲染的项目还需要对应真实样本；若只有合成测试，明确标注，不能声称像素一致。

## 文档载入与页面

- [x] R-01 / P1：`open_document_with_passwords` 和浏览器密码重试入口已接入；40-bit ARC4、128-bit ARC4 和 AESV2 覆盖正确/错误用户密码、所有者密码与页面文字读取，四后端验证通过。空密码重试也不会回到未认证路径。浏览器弹窗仍需要带真实加密文件的专门 Chromium 对话框回归。
- [x] R-02 / P1：复用 pdflite 的严格 xref/重建/继承入口，补循环引用、页树深度与节点限额；独立对象表保留有效页面及原内容/字体引用，`reader_diagnostics()` 定位跳过分支。已有 active xref/free entry/ObjStm、合法 stream 注释和有界字体 Flate 恢复继续通过，filter/predictor 的严格解码不被恢复缓存绕过。新增 5 项页树回归；989 份真实 PDF 扫描有 952 份成功、37 份失败，成功输入含 266 份 ObjStm 和 6 份 XRef stream 文档。5 个真实 reader 页完成对照和来源核对；`Pages-tree-refs.pdf` 保留 1 个可读页，与 PDF.js 报 2 页后延迟拒绝坏页的 API 不同。不可恢复坏流/xref 和密码/认证失败仍保留错误，见 [A1 收尾验证](validation.md#a1-completion-validation)。
- [ ] R-03 / P2：复用 Fetch/Streams/Range 数据源，先验证或扩展 pdflite 的分段读取接口，使大文件不必完整下载后才能打开第一页；不另建 PDF reader。
- [x] P-01 / P1：页面模型现在验证有效 CropBox/MediaBox 交集、非法/相离回退、非零原点和正值 UserUnit；viewport 保留请求的 `scale` 并用 `scale * user_unit` 计算矩阵与尺寸，SVG 绘制共用该有效缩放。合成边界回归和真实 `issue19176.pdf`（`/UserUnit 72`）的 PDF.js 对照均通过，见 [validation.md](validation.md#page-boundaries-and-userunit)。宿主额外 devicePixelRatio 仍由浏览器层决定。
- [ ] P-02 / P1：补宿主可用的任务生命周期、错误分类、资源释放和 API 行为测试；记录与 PDF.js 公开模型的差异。

## 字体与编码

- [x] F-01 / P0：贯通 reader 已解析的水平外部 CMap 的 1–4 字节 codespace 切分、原始字符串、CID 宽度、ToUnicode、Tj/TJ/引号及裁剪；覆盖混合长度、四字节高位和损坏输入。9 个新增测试及真实 `issue18117.pdf` 的绘制抽查通过，见 [validation.md](validation.md#variable-length-horizontal-external-cmaps)。纵排、内置 CMap 与 reader 丢弃的范围由 F-02 至 F-04 跟踪。
- [x] F-02 / P0：支持常用 Adobe 预定义 CMap 到 CID 的准确映射及相关字体绘制。嵌入固定版本的 168 份 binary CMap，按需解码并缓存；贯通继承 codespace/WMode、CID 宽度、CIDToGIDMap 解压和 Adobe CID→Unicode。8 个 CMap 测试和真实 `90ms_rksj_h_sample.pdf` 的绘制抽查通过；资产来源与许可见 `assets/cmaps/`，验证见 [validation.md](validation.md#adobe-predefined-cmaps-vertical-layout-and-word-spacing)。外部 stream 的复杂继承由 F-03 跟踪。
- [x] F-03 / P0：复杂命名/间接 `UseCMap`、缺 codespace、WMode、本地映射优先、notdef、1–4 字节无符号范围与 ToUnicode 共用现有惰性 CMap 恢复；严格 reader 前检查展开量和继承深度，源流不可用时保留 reader fallback，并定位环、坏 token 与资源对象。新增 4 项测试使用固定版本的四份原始 Adobe Japan1 文本 CMap，覆盖 UTF32/surrogate 来源、纵排及 64 层边界；PDF 包装是自建 fixture，明确保留此证据边界。根模块固定 pdflite 的 989 份自然 PDF 扫描有 14 个解析到的外部字体 CMap，没有自然文本/字典 UseCMap 或 reader 丢弃样本。合法 PostScript 字典头和 literal 元数据不误报为坏 hex；现有真实页对照和来源检查通过，见 [A1 收尾验证](validation.md#a1-completion-validation)。
- [x] F-04 / P0：统一纵排的 W2/DW2、垂直原点、带符号推进、TJ 调整与 character/word spacing；绘制、裁剪和选择共用同一 glyph placement。8 个纵排测试通过，覆盖 Identity/外部/预定义 CMap、连续操作、q/Q、引号、rise、剪切、负字号和选择/裁剪；真实 `vertical.pdf` 三页完成转换及 Chromium/Poppler 抽查，见 [validation.md](validation.md#adobe-predefined-cmaps-vertical-layout-and-word-spacing)。
- [x] F-05 / P1：接入 `mizchi/font` 0.7.4 的 cmap 0/4/6/12 与 post 1/2；增加 cmap 2 subheader/别名/相对 offset 和 post 2.5 signed index 的有界格式转换，post 3 合法无名称。Encoding/Differences、Symbol/MacRoman/非 BMP 选表、复合点对齐/scaled offset 与损坏表回退均有覆盖，复制文本独立于选 GID。新增 4 项旧格式/损坏 sfnt 回归，真实字体对照、来源和 Chromium FontFace 检查通过；缺 cmap 子集的 FontFace 拒绝不妨碍路径绘制与选择。罕见 cmap 8/10/13、厂商 post 和字体库未支持的缺表/复合轮廓保留既有恢复路径，见 [A1 收尾验证](validation.md#a1-completion-validation)。
- [x] F-06 / P1：Type 1/CFF 非默认 FontMatrix、缺字、截断 charstring、坏子程序和整个损坏程序保留复制文本、PDF advance 与后续页面，无法使用的轮廓有诊断回退。Type 1 hint replacement 保留 OtherSubr 参数，flex 从当前点使用相对坐标；CFF 显式名称缺失选择 `.notdef`，不冒用其它字形。新增 6 项程序恢复回归；真实 `tracemonkey.pdf` 第一页的 1,549 个缺失嵌入轮廓/宿主回退降为 0，`issue14462_reduced.pdf`、`issue17147.pdf` 继续可测量。整页栅格化差异仍保留，多 FD CID Type 1 等罕见分支继续回退，见 [A1 收尾验证](validation.md#a1-completion-validation)。
- [x] F-07 / P0：携带固定 PDF.js 版本的 10 个 Foxit CFF 和 4 个 Liberation Sans TrueType 程序，来源、许可和 SHA-256 保存在 `assets/standard14/`。复用现有轮廓读取器完成标准 14 的绘制和裁剪，AFM/PDF Widths 保持定位；subset 名称、Symbol/Zapf、WinAnsi bullet 默认槽、Differences、ToUnicode 独立复制、嵌入程序优先与显式宿主 override 均有回归。11 项新测试及四后端 322/322 通过；强制 PDF.js 使用同一套固定字体程序的 16/16 真实页对照无测量失败，另复跑 10 份字体样本。标准字体页仍有 116,689–128,412 个超容差像素，包含表格描边和字形栅格化差异；本项完成确定性字体路径，不表示 A2 整页像素已对齐。证据见 [validation.md](validation.md#standard-14-fonts-and-host-fallback)。
- [x] F-08 / P1：提供宿主字体解析/注入入口及系统字体回退策略；`PdfFontFallback` 和 `PdfViewerDocument::with_font_fallbacks` 接受资源名或 `/BaseFont` 到 CSS 字体族的映射，嵌入 TrueType/OpenType 仍优先使用文档字节；JS bridge 的 `set_font_fallbacks(json)` 清空页面缓存后重新使用该策略。宿主只提供本机/已许可字体，不把字体文件放入 viewer；库层回归和 Chromium bridge 检查见 [validation.md](validation.md#host-font-fallback-policy)。

## 文字与选择模型

- [x] T-01 / P0：提取、复制/框选、搜索和 DOM text layer 共用页面逻辑顺序，paint-order 与原始 quad 保持不变。复用 bidi UAX #9 核对方向和多 scalar glyph；基线投影覆盖旋转/剪切、通栏标题与双栏，短表格逐行、长栏逐栏，控制符/显式换行及跨方向空隙共享分隔符。新增 8 项回归，345 项四后端和 10 份真实字体来源检查通过。无 tags 的短表格/段落是几何启发式；无法核对的 bidi 仍保留内容顺序，见 [A1 验证](validation.md#a1-fonts-unicode-and-reading-order)。
- [x] T-02 / P1：`text_sources()`、`text_provenance(n)`、`text_lexical_sources(n)` 和 `text_structure()` 连接 UTF-16、稳定 item、charcode bytes、CID/GID/名称、字体/程序、内容流、Form 调用、词法拼写和 run/几何段落。复用 pdflite lexer/parser 与既有选字逻辑，支持转义/hex/TJ、变长 CMap、字体继承、ExtGState、q/Q、解密、bidi、连字和 surrogate pair；空复制字形保留词法来源。只有 backing bytes 与原输入一致的未压缩/未加密流才有文件字符范围；压缩/加密流返回解码位置及完整原流范围，未知或超限位置显式缺失。来源与搜索/选择共用逻辑顺序，推断分隔符不编造字节 owner；段落是几何推断。15 项新回归、四后端 337/337 及 10 份真实样本的 5,409 个 glyph 来源检查通过，见 [A1 验证](validation.md#file-spelling-empty-glyph-origins-and-text-structure)。
- [x] T-03 / P0：全面对齐 Tw 的编码语义：只有原始单字节 0x20 应用 word spacing。所有 CID 字体共用按 byte length 判定的主路径；4 个独立字距测试及外部 CMap/纵排测试覆盖 standard、simple、Type 3、Identity 与预定义 UTF8/UTF16/UTF32。ToUnicode 把别的字符映射为空格也不会触发 Tw，见 [validation.md](validation.md#adobe-predefined-cmaps-vertical-layout-and-word-spacing)。
- [x] T-04 / P1：字体字典、Encoding/Differences、缺失/损坏 metrics、非法 ToUnicode 和字符码共用恢复入口；保留有效 PDF widths，Unicode 目标非法时回到正常 Encoding，空串与字面 U+FFFD 不判为损坏。`text_recovery_diagnostics(n)` 连接实际字体绑定、page/item/charcode、原字符串 bytes、资源路径和对象号；空复制字形也有来源，旧文档诊断只投影有逻辑范围的记录。新增 10 项回归，含循环字体/descriptor/stream、巨大 CID widths、缺 Tf 和合法间接 Encoding/真实 CMap 头的误报检查；四后端与真实来源/诊断连接全部通过。恢复观察不证明作者原意或 bytes 未损坏，见 [A1 收尾验证](validation.md#a1-completion-validation)。

## 绘制、图片与色彩

- [ ] G-01 / P0：保留绘制时的完整 CTM，正确处理非均匀缩放/剪切下的描边、文字描边、虚线和椭圆笔画。
- [ ] G-02 / P1：扩大 hairline、miter、退化路径、填充规则、clip 生效时机和多层 Form scope 的精确覆盖。已修复 clip 不跟随输出缩放的问题：`text_clip_cff_cid.pdf` 在 2x 下的差异像素从 71,920 降到 346；正文、图片和 shading 共用缩放后的裁剪。`vertical.pdf` 的页面边缘线等仍有差异，本项尚未完成。
- [ ] G-03 / P0：优先适配 Canvas 2D 或现有 MoonBit 绘图库，native 可评估 Skia；用真实样本确定可控的像素后端，处理 SVG 无法精确表达的 PDF 语义。通用 rasterizer 不作为默认自研任务。
- [ ] I-01 / P0：优先验证/扩展 `trkbt10/jpeg2000` 的公共多组件解码接口并接入 PDF JPX colour/alpha，使浏览器不依赖原始 image/jp2 支持；具体缺口见候选表。
- [ ] I-02 / P0：先核查现成 JBIG2 解码器的 MoonBit 适配/绑定或移植路径，覆盖 globals、常见 segment 和 mask；确认目标、许可和能力缺口后才安排局部自研。
- [x] I-03 / P0：viewer 在自己的 image resource 适配层保留 `Op_InlineImage` 的 `DecodeParms`，并把它合并到临时 image stream；真实页面模型回归覆盖 CCITT Group 4（`K=-1`）、Group 3 1D（`K=0`）、1-bit `/Decode [1 0]`、序列化后的 ImageMask，以及 Flate + PNG Predictor 12。每个 fixture 都重新写入/读取 PDF，最终浏览器 PNG 的 IHDR、压缩 IDAT 解压结果和关键像素均有断言；此前丢弃 `DecodeParms` 会使 CCITT 的 `/Columns`、`/Rows`、`/K` 无法进入解码器。当前仍依赖 pdflite 已支持的 filter/CCITT/predictor 解码，真实外部 image corpus、JPX/JBIG2 和原始样本空间的 color-key/Matte 语义分别由 I-01、I-02、I-04 跟踪，验证见 [validation.md](validation.md#inline-image-decode-path)。
- [ ] I-04 / P1：raw 图片现在按原始 1/2/4/8/16-bit 样本、逐行 padding、16-bit 大端和 `/Decode` 转换；color-key mask 在原始整数样本中比较，覆盖 CMYK、反向 Decode 和 packed rows。raw SMask/explicit ImageMask 按最大尺寸、floor nearest-neighbor resize 合成 RGBA，SMask 优先，raw `/Matte` 在父图色彩空间中转换后解除预混合，透明像素设为白色；覆盖不同/损坏尺寸和避免重复 alpha。`/Interpolate`/inline `/I` 与完整 affine 的 Float32 采样阈值已接入正文、mask 和 pattern image，并对轴对齐图片边界取整。最新真实对照中 `issue10339_reduced.pdf` 的 0/90° 和 `issue4246.pdf` 均为 0 个超容差像素；`colorkeymask.pdf` 四个旋转仍有约 2,690–3,499 个，`smaskdim.pdf` 有约 5,130 个且包含 annotation 外观差异，JPEG + SMask + Matte 的 `issue13931.pdf` 有约 38,378 个。encoded-image mask/Matte、color-key 边缘、复杂 bitmap 合成和大图内存策略仍未完成，保持未勾选。证据见 [validation.md](validation.md#image-interpolation-raw-alpha-masks-and-malformed-simple-font-recovery)。
- [ ] C-01 / P0：优先评估 LittleCMS 等已有 ICC 转换引擎的适配，接入 ICCBased 和准确的 CMYK 到输出空间转换，验证真实印刷类 PDF。`enanandesu/icc` 只读元数据，不能替代转换引擎。当前 CMYK 使用固定 PDF.js 的 SWOP 多项式拟合，ICCBased 使用 alternate；这不是 ICC profile 解析或 LUT 色彩管理。
- [x] C-02 / P1：CalGray gamma/tone curve、CalRGB gamma/Matrix 列序、白点 normalization/黑点补偿、Lab D50/D65 输出和 component Range 已进入共享转换主路径；named `CS/cs`、默认样本、q/Q 和嵌套 Form scope 均有 reader 回归。固定 PDF.js 本身忽略 CalGray 非默认 BlackPoint、Lab BlackPoint 和 `/ri`，viewer 采用同样行为。真实 `calgray.pdf` 3 页、`calrgb.pdf` 17 页和 `issue10339_reduced.pdf` 的 1,432 个色块抽样 RGB 全部一致；整页字体、阅读顺序、图像插值和边缘差异继续由 F/T/G/I 项跟踪，不把此勾选解释为整页像素一致。验证见 [validation.md](validation.md#calibrated-colours-and-original-image-samples)。
- [ ] C-03 / P1：Separation/DeviceN tint function 已接入正文、raw 图片、pattern 和 mesh，并在重复样本转换前预解析；合成测试覆盖单输入及多输入 calculator。真实 `devicen.pdf` 仍有 946 个差异像素，`devicen-none-zero-domain.pdf` 有 25,600 个差异像素；特殊 colorant/domain、精确 alternate 色彩与 overprint 的可见结果尚未对齐。

## 透明组、mask 与 pattern

- [ ] M-01 / P0：实现 non-isolated transparency group 的 backdrop 和 knockout 合成，包含嵌套组。
- [ ] M-02 / P0：补 soft mask 的完整 Alpha/Luminosity、BC 色彩空间、TR、组边界与作用域语义。
- [ ] M-03 / P0：先验证选定绘制库/Canvas 的 blend mode，再适配 PDF 混合语义与 unsupported SVG blend 的确定性回退，使用像素对照验证；只补确认不支持的模式。
- [ ] H-01 / P0：支持 uncolored tiling pattern，并正确应用调用位置的基础色彩。路径型单元现会把调用处基础色应用到 fill/stroke；另修正输出倍率在 patternTransform 和页面绘制中重复应用的问题。合成回归覆盖 DeviceGray/RGB/CMYK，彩色 `PaintType 1` 不变。PDF.js 的 `tiling_patterns_variations.pdf` 在 2x 下整页超阈值差异由 169,803 降至 27,076；P5 区域由 61,094 降至 4,176（含边缘，容差 8）。剩余差异仍分布在图案矩阵、裁剪和边缘，故尚不能确认所有 pattern 的位置、重复边界及像素输出已对齐。测量见 [validation.md](validation.md#uncolored-tiling-pattern-base-colour)。
- [ ] H-02 / P1：支持包含文字、图片、Form、透明组和独立资源的复杂 tiling pattern；验证矩阵与重复边界。当前 pattern collector 已使用 viewer 的 named colour/嵌套 Form scope；`pattern` 与 `stroke_pattern` 独立保留并支持 tiling 填充/描边。复杂单元文字、透明组、裁剪以及 shading pattern 描边仍未完成。
- [ ] H-03 / P0：先验证后端的网格/渐变/插值能力，适配 PDF Gouraud/patch 和抗接缝，缺失的 patch 分支单列实现；扩大函数/轴向/径向 shading 的边界与 Extend 覆盖。

## 批注、只读表单与文档功能

- [ ] A-01 / P1：扩大 annotation 子类型、缺失 AP 的外观、line ending、图标、边框和 markup 的真实样本覆盖。
- [ ] A-02 / P0：按 DA/DR 和字段 metrics 排版无 AP 的 FreeText/文本 widget，覆盖多行、对齐、comb 和 password 外观。
- [ ] A-03 / P1：补 choice 的 export/display 值、列表选中、按钮/radio 状态与只读显示；无需提供编辑能力。
- [ ] A-04 / P1：实现批注命中、popup、链接层与屏幕/打印外观切换；图层坐标须与页面旋转一致。
- [x] D-01 / P1：viewer API 已解析旧式 `/Dests` 字典和 `/Names` `/Dests` name tree，覆盖 named/explicit destination、`XYZ`、`Fit`、`FitH`、`FitV`、`FitR`、`FitB`、`FitBH`、`FitBV`；`destination_for_page`、`named_destination`、`named_destinations_json` 和 `outline_navigation_json` 提供一基页码及结构化视图。当前文档页会标记为 `resolved`，远程页保留 `remote_page` 并不会误跳到本地；本地目录点击和滚动定位已由 D-03 接入，annotation link layer 仍由 A-04 跟踪。destination 回归见 [validation.md](validation.md#destinations-and-document-navigation)。
- [x] D-02 / P0：viewer 读取 pdflite 的 `/OCProperties`、默认/备用配置和 `/ON`/`/OFF`，在 display-list 收集阶段过滤文字、路径、图片、inline image、shading 及带 `/OC` 的嵌套 Form；`PdfOptionalContentState` 按 OCG 对象号选择配置并覆盖状态，隐藏文字不会进入 text clipping、text content、operator list 或 selection。回归 fixture 覆盖默认关闭、显式打开和选择结果，当前四后端 209/209 通过，见 [validation.md](validation.md#optional-content-visibility)。OCMD 的常见 `/P` 与 `/VE` 表达式已支持；usage、RBGroups、Locked 的 UI 语义和浏览器图层面板仍是后续图层工作。
- [x] D-03 / P1：独立浏览器已接入 outline 目录树、page label 状态、Info/XMP 面板和附件清单；本地 destination 点击可滚动到目标页，远程或未解析目标保持禁用；附件和 XMP 通过 bridge 按需下载，不把字节放进打开文档的状态 JSON。`nested_outline.pdf`、`labelled_pages.pdf` 和 `attachment.pdf` 的 Chromium 回归覆盖目录、缩略图/信息入口、页标签、metadata 和附件字节，仍不声称已实现 OCG usage/RBGroups/Locked 的图层 UI 或批注链接层。

## 独立浏览器体验、可访问性与验证

- [x] U-01 / P0：独立静态浏览器 viewer 和 MoonBit JS 入口已贯通，本地文件/拖放、错误恢复、页码、缩放/旋转和下载可用。`moon run tools/dev.mbtx 4312` 可独立调试；`tools/build_web.mbtx` 生成可部署的 `web/`。真实文件输入与错误恢复经过 Chromium 验证，见 [validation.md](validation.md#standalone-browser-and-native-cursor-selection)。
- [x] U-02 / P0：`PdfPageModel::text_layer()` 把 glyph 四边形转换为 DOM 几何，覆盖轮廓和字体绘制；原生鼠标拖选、复制、Shift＋方向键和文档全选经过 Chromium 检查，包括旋转和纵排。浏览器层使用正常字号与归一化 affine，避免 1px 字体放大时拖选失效；批注/表单的 DOM 交互层继续由 A-04 跟踪。
- [x] U-03 / P1：`select_text()` 用 item index 和 UTF-16 offset 返回文字、源 glyph 索引和 PDF-space quads；支持反向端点及部分 ligature，拒绝拆开 surrogate pair。跨行/跨页选区包含文件信息，缩放/旋转后按相同来源端点恢复原生高亮；浏览器回归覆盖旋转、纵排和 14 页文档全选。原始 PDF byte span 仍由 T-02 跟踪，阅读顺序/bidi 由 T-01 跟踪。
- [x] U-04 / P1：库层 `PdfViewerDocument::search()` 返回页码、源 UTF-16 offset/length、原文、bounds 和 item indices；支持大小写、Unicode 分类的整词与 NFKD 归一化/变音符号折叠，并以源字符区间映射展开折叠后的长度。浏览器桥接暴露 `search_pdf`，搜索栏支持选项、结果计数、上下结果、滚动定位和 item 级高亮；空查询、重新打开文件和缩放/旋转后的重绘都会清理或重投影状态。209 个四后端测试和 33 项 Chromium 检查通过，变音符号映射回归见 [validation.md](validation.md#text-search)。A1 已接入 Unicode 16 NFKD，7 项新增搜索回归覆盖连字、兼容字符、canonical mark 重排、supplementary offset 和独立组合符号；复杂阅读顺序/bidi 主路径由 T-01 验证。完整 locale/case-fold 策略、跨 item 的精确字符高亮和 Worker 搜索仍未完成。
- [ ] U-05 / P1：已补缩略图、打印入口、连续/单页模式和 `#page=N` 浏览器历史；页码跳转与目录/缩略图点击都会更新历史，分页模式只显示当前页。当前仍然每次缩放/旋转重建所有已挂载页面，未实现 Worker、取消、虚拟化和内存上限；annotation/link DOM 交互也仍待 A-04。
- [ ] X-01 / P1：把 tagged structure tree 和阅读顺序落实到可访问的 DOM/ARIA，而不仅是 JSON。
- [ ] X-02 / P2：支持 XFA 文档的只读页面布局与文本展示，编辑与脚本不在范围内。
- [x] V-01 / P0：`tools/visual_test.mbtx` 使用固定 PDF.js 版本和同一 Chromium，测量清单内全部页面/旋转；最新基线在 `_build/visual-test-1791598324155/` 完成 57/57 个组合测量，0 个失败，55 个存在像素或文本差异，2 个在记录的容差内；包含 `/UserUnit 72` 的 `issue19176.pdf` 与 PDF.js 得到 0 像素差异。`standard_fonts.pdf` 14 页以及 CalGray/CalRGB/Lab、DeviceN 和 color-key mask 均已测量；色块的定向抽样保留为额外诊断，整页差异照常计数。`--strict` 会拒绝差异，输入或渲染失败计入失败数。7 个分类器测试和独立 runner 合约检查覆盖正确匹配、明显错位、漏画及缺失输入。具体结果和限制见 [validation.md](validation.md#automated-pdfjs-visual-baseline)。后续每个渲染功能都要扩大这份基线。
- [ ] V-02 / P1：补 Worker、取消、页模型/字体/图片缓存、内存上限与大文件压力基线；报出耗时和峰值内存。
- [ ] V-03 / P1：把四后端测试、corpus、视觉基线和差距表纳入 CI；固定对照/依赖版本，记录样本来源和资产许可。

## 推荐推进顺序

1. 做三组最小复用验证：`bidi` 的来源映射、`mizchi/font` 的按 GID 轮廓、现成 JPEG 解码的 SMask/Matte；保留 fixture 和候选结论，再接主路径。
2. A2 用 Canvas 2D 与现有 MoonBit 绘图库验证完整 CTM/clip/blend 的代表样本，确定绘制/合成共用后端；宿主调度留到后续，用原生 Worker/观察器。
3. 验证/扩展 JPX 的多组件 API；检索 JBIG2 和 ICC 引擎的目标适配，记录不能直接复用的具体原因。
4. PDF group/mask/pattern/shading：依赖复用结论补 PDF 语义，沿用 V-01 做真实对照；A1 字体/CMap 样本保留为回归基线。
5. A-01 至 A-04、reader、可访问性和 CI；后期 range/XFA 先复用传输/XML 解析，再补 PDF 读取/布局。

## 完整阅读器的后续接入

这些能力是产品目标的一部分，尚未拆入上述 50 项，也未计为完成：

| 能力 | 优先复用 | 需要实现与验收 |
| --- | --- | --- |
| 批注编辑与保存 | pdflite 批注/对象模型、`pdf_write_document` / `pdf_write_document_incremental_update`；DOM/Pointer Events | 编辑状态、撤销/重做、AP 外观、资源/对象更新；保存后重新打开并验证内容与外观 |
| 表单填写与保存 | 原生 input/select 等控件、pdflite 字段/对象模型与 writer | 字段继承、export/display、radio 状态、值与 AP 同步、保存重开；只读 A-03 不代表已完成填写 |
| 手写/图片签名 | Canvas/Pointer Events、已有图像/路径及批注 AP 写入路径 | 笔迹/图片采集、放置/缩放、持久化与重开；数字证书签名若纳入目标，另评估密码/CMS 库和 PDF 签名适配 |

pdflite 的 writer API 已在当前依赖中，viewer 尚未接编辑/保存主路径；
现有浏览器下载仍返回载入的原始文件。writer 和增量写入不能单独证明表单或签名完成，
但也没有理由先从零写 PDF serializer。

## 扩展项与维护

多 FD CID-keyed Type 1 可作为扩展，但当前对照版本的
`src/core/type1_parser.js` 也明确只支持单 FD，因此不计入上述 PDF.js 对齐欠账。
不同的 FDArray 声明形式属于 F-06 验收记录中保留的扩展分支，仍需按真实样本评估。

每次继续实现后更新本文件：勾选对应 ID，记录验证文件和命令，列出仍未覆盖的分支。
避免把“转成 SVG”或“增加了测试数”直接写成整项对齐完成。
最新结果保存在 [validation.md](validation.md)，分层说明在
[architecture.md](architecture.md)。
