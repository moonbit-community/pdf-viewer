# PDF.js 对齐 TODO

更新日期：2026-10-11。最终产品目标是完整阅读器，包括批注编辑、表单填写和签名。
本轮 6 个剩余只读功能与 review 回归的验收见 [收尾记录](readonly-completion.md)。
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

当前明确跟踪 **50 项，分为 14 个能力领域；完成 50 项，剩余 0 项**。
按条目数量是 **50/50（100%）**，不是 PDF.js 的视觉兼容率，也不是工程量百分比。
P0 共 23 项、P1 共 25 项、P2 共 2 项，均已完成主路径验收。条目大小不同，已实现路径和开放分支以逐项记录为准。

A1 的全部 8 个主路径项目已验收：R-02、F-03、F-05、F-06、F-07、T-01、T-02、T-04。
包括真实 Adobe CMap 继承、字体格式与损坏程序覆盖、固定 Standard 14 字体程序、
逻辑阅读顺序、字节/词法来源、统一文字恢复诊断和有界页树恢复。
`tracemonkey.pdf` 第一页的 1,549 个缺失嵌入轮廓已恢复。
验收、真实差异和保留回退见 [A1 收尾验证](validation.md#a1-completion-validation)。

A2 的 14 项均已有主路径验收：JPX/JBIG2、encoded alpha、Canvas 像素后端、
路径裁剪、透明组、soft mask、16 种混合模式、pattern、shading 和印刷色彩均已接入公开入口。
G-01 已接入 A1 固定 Standard 14 轮廓：默认网页的 621-byte 复现在 24 个
fill/stroke/旋转/缩放组合与相同字体的嵌入控制逐像素一致，无 native 轮廓适配器。
显式宿主 override 或非标准字体没有轮廓时仍明确诊断；未把原生宿主验证说成浏览器 DOM 通过。
C-01 的真实印刷色彩路径已通过分阶段验收；原始整页残差保留，并逐项定位到
色版/intent 策略、字形、覆盖和采样，不把它们称为整页视觉通过。
14 项的实际目标支持、真实样本、已知差异与资源限制见
[A2 验收记录](a2-acceptance.md)。合并 review 确认的 6 项 P2 回归已修复并加入定向检查，见
[本轮收尾验收](readonly-completion.md)；这些问题不计为新增能力条目。SVG 兼容输出不等同于 Canvas 像素实现。

| 交付门槛 | 必须完成的剩余项目 | 结论 |
| --- | --- | --- |
| 核心渲染 | 无 | 缺失 AP 字段排版已补齐；仍保留真实视觉差异 |
| 独立只读 viewer | 无 | 批注、只读表单与固定版本 CI 已接入 |
| 大文件与特殊格式 | 无 | 按需 Range 与动态只读 XFA 已实现，资源边界见验收 |

OCG 的 usage、RBGroups、Locked 控制及图层面板仍属于浏览器扩展，未计入这
50 项；增加为独立 P1 条目时总数与剩余数须一起更新。

已有主路径还包括 CMap、CID 纵排、编码字距、宿主字体策略、密码入口、页面边界、
目的地与导航、文字选择和搜索。其真实验收与开放边界继续保留在下面对应条目；
A1/A2 与宿主的独立验收不替代合并后验证，也不代表编辑、保存或签名已经完成。

浏览器宿主主路径完成 P-02、U-05、V-02：复用原生 Worker、AbortController 和
IntersectionObserver，接入异步解码、文档代次/取消、可见页与缩略图调度、两级缓存预算
以及全页打印。上游独立验收记录为四后端各 376 项测试、53 项 Chromium 交互与压力检查，
包括 200 页和 12 MiB 原始图片文档的耗时、主线程/Worker 堆与缓存驱逐。
这些记录不是 A2 合并后的 DOM/压力复跑；缓存预算也不等于进程内存上限。
完整证据与取消/打印边界见
[浏览器宿主验证](validation.md#browser-host-lifecycle-scheduling-and-pressure)。

A-04 的只读交互主路径完成：批注 popup、URI/本地/named-action 链接、独立打印外观
与页面卸载清理已接入。原生控件和 viewport 矩阵继续复用，markup 不妨碍正文拖选。
上游 `1f9db19` 的独立验收记录为四后端各 379 项测试和 78 项 Chromium 检查，
包含真实 PDF、四旋转和缩放；这些不是 A2 合并后的 DOM 复跑。特殊图标/AP 的
NoZoom/NoRotate 图标/AP 外观与命中现已由 A-01 补齐。证据见
[批注验收](validation.md#readonly-annotation-interaction-and-print-intent)。

X-01 的可访问 DOM 主路径完成：复用 pdflite 对象、content ops 和 A1 glyph 来源，
把页级 MCID、Form stream/调用实例、ParentTree、RoleMap 和批注 OBJR 接到原生 DOM/ARIA。
tagged 页按结构树提供标题、段落、列表、表格、语言和替代文本，未关联文字保留几何段落；
装饰内容和重复 glyph 旁白不会进入辅助技术树。Chromium AX 检查覆盖真实文件、
键盘分页、重绘和复制来源。辅助技术逐页读取已挂载页面；VoiceOver/NVDA 的人工使用
验收、PDF/UA 合规及 PDF 2.0 namespace/MathML 等扩展尚未完成。见
[可访问性验收](validation.md#tagged-page-accessibility-and-source-association)。

历史 Chromium 基线测量了 20 份 PDF 的 57 个页面/旋转组合：全部得到报告，
55 个组合存在像素或文本差异。这是 A2 大规模接入前的历史基线，**57 次测量不是
57 个视觉通过**。A2 使用实际发布的 Moon JS 入口和 native Canvas 宿主，另有
原始样本、CMM、alpha、色版及最终像素回归；其记录中的环境因 socket EPERM
无法启动 Chromium。A2 首次合并后的历史验收通过 93/93 项 Chromium 检查，
覆盖 Canvas、批注、可访问性、选择恢复、200 页打印与 raw 图片压力；JS 643 项、
Wasm/Wasm-GC 各 644 项及 native 可访问性 8 项通过。当时 macOS native 的可选宿主
失败现已修复；本轮四后端全量测试通过，并通过 104/104 项 Chromium 检查，覆盖新增
XFA、Range、200 页打印与缓存压力。历史证据见
[合并验收](a2-acceptance.md#latest-master-integration-2026-10-11)，当前证据见
[本轮收尾验收](readonly-completion.md#continuous-checks)。

A1 独立收尾记录为四后端 374 个测试通过及 39 项浏览器交互检查，另测量了
10 个字体、16 个标准字体和 5 个 reader 页面组合，均无测量失败，也均保留像素或文本差异。
989 份本地 PDF 的 reader 扫描有 952 份成功、37 份失败；10 份字体与 5 份 reader
样本的来源/词法/run/段落/诊断连接检查通过。以上是各自验收记录，不替代合并后验证。
转换成功、没有占位、测试通过，都不能单独证明没有漏画或排版错误，
也不能据此给出可信的视觉兼容率。基线细节见 [validation.md](validation.md)。

| 领域 | 已有主路径 | 主要剩余范围 | 剩余项数 | 对应项目 |
| --- | --- | --- | ---: | --- |
| 文档载入 | bytes、密码、对象恢复、有界页树、按需 HTTP Range | 坏流/xref、加密和不支持 Range 的服务器有明确失败/全量回退 | 0 | — |
| 页面/API | 页面模型、viewport、旋转、边界/UserUnit、显示列表、宿主生命周期、错误分类和释放 | 与 PDF.js 的公开对象结构不同；取消以宿主任务/页面为边界 | 0 | — |
| 字体/编码 | 复杂/Adobe CMap、CID 纵排、TrueType/CFF/Type1 轮廓与恢复、Standard 14 固定程序、AFM、编码/裁剪、宿主 fallback | 罕见 cmap/厂商 post、多 FD Type 1 等保留有诊断的回退；像素差异仍测量 | 0 | — |
| 文字 | glyph placement、逻辑阅读顺序、选择/裁剪、编码字距、字节/词法/run/段落来源、恢复诊断 | 无 tags 的歧义结构、未编码的 Unicode 无法自动恢复 | 0 | — |
| 矢量 | affine pen、clip、hairline、Canvas、A1 嵌入及 Standard 14 轮廓 | 显式宿主 override/非标准字体无轮廓时保留可见诊断 | 0 | — |
| 图片 | JPEG/JPX/JBIG2、raw/inline、encoded mask/Matte | 目标与资源限制见验收记录 | 0 | — |
| 色彩 | 校准色、ICC、tint、显示 alternate、过程色 overprint | 非整页像素一致，分层差异已归因 | 0 | — |
| 透明合成 | group、backdrop、knockout、soft mask、16 blend | 参考实现分歧见逐项证据 | 0 | — |
| pattern/shading | 完整单元、文字/stencil paint、源分量逐像素插值 | 有界采样与资源限制见记录 | 0 | — |
| 批注/只读表单 | AP/DA/DR、字体排版、几何/图标、choice/radio、popup/链接和屏幕/打印 | vendor/rich-text 外观继续扩大样本；编辑另计 | 0 | — |
| 导航/图层 | 导航、metadata、附件、OCG 核心过滤和批注链接 | 图层 UI 另计扩展 | 0 | — |
| 浏览器体验 | 独立应用、Worker/取消、可见页与缩略图调度、来源选择/搜索、导航、popup/链接 DOM 及全页打印 | 打印使用工具栏或 Ctrl/Cmd+P；特殊外观与编辑另行跟踪 | 0 | — |
| 可访问性/XFA | structure tree、DOM/ARIA、Chromium AX、动态 XFA 绑定/分页/只读控件 | 人工辅助技术、特殊标签/XFA 模板继续验证 | 0 | — |
| 验证/性能 | 四后端 CI、corpus/视觉门槛、Chromium 调度/打印/压力、缓存预算 | 扩大自然样本；缓存预算不限制解码峰值 | 0 | — |

“已有主路径”保留逐项验收的范围和限制，不表示整个领域或任意真实文档视觉完全一致。

## 先复用，再补 PDF 适配

每项先检查已有依赖、Mooncakes 和成熟底层库，做最小接入验证，再安排实现。
候选版本、源码/API 核查、已知限制见 [生态复用候选](codec-candidates.md)。
下表保留本轮完成的 6 个 ID，并保留已完成 A1/A2 与宿主的复用决策。
已接入项的实际方案与限制以对应验收记录为准；“有候选”不代表已经接入或满足验收。

| TODO 范围（含复用记录） | 优先复用的能力 | 本项目保留的工作 |
| --- | --- | --- |
| R-02、F-03、T-04（已完成） | pdflite reader、lexer/CMap、现有 Adobe CMap 资产及同版本 Flate | PDF 继承、严格 reader 前的展开/循环边界、局部恢复和可定位诊断；不另造 reader 或流解码器 |
| R-03（已完成） | 原生 Fetch/ReadableStream/Range；pdflite 对象/xref/流 API | 64 KiB 数据源、对象按需加载、版本一致性和双层 LRU；加密/不支持 Range 回退 |
| P-02、U-05、V-02（已完成） | 原生 Web Worker、AbortController、IntersectionObserver | 文档代次、优先队列、来源选区、可见页/缩略图、缓存预算与释放；不重造线程/网络库 |
| F-05、F-06（已完成） | 已接入 `mizchi/font` 0.7.4 的 cmap/post；已有 TrueType/CFF/Type 1 轮廓路径 | PDF 选表/编码、少量旧格式转换、Widths/FontMatrix 和损坏程序恢复；缺 cmap 子集与库尚不支持的复合轮廓保留现有路径 |
| F-07（已完成） | pdflite Standard 14 AFM；固定 PDF.js 版本的 Foxit CFF 与 Liberation Sans TrueType | 复用既有字体解析器和许可资产；AFM/PDF Widths 定位、编码、裁剪与显式宿主 override，保留整页差异 |
| T-01、T-02（已完成） | `moonbit-community/bidi`、`moonbit-community/normalization` 与 pdflite lexer/parser | UTF-16 与源 glyph/bytes/词法映射、PDF 已定位文字的逻辑顺序和几何段落；无 tags 的歧义结构保留限制 |
| G-01 至 G-03（已完成） | 共享 Canvas 2D 后端；A1 嵌入/Standard 14 轮廓；可选 native 宿主轮廓 | 保留结构化路径、完整 CTM、PDF clip/描边状态；无轮廓的显式宿主 override 保留诊断 |
| I-01（已完成） | 固定并扩展 `trkbt10/jpeg2000` 多组件解码入口 | JP2 色彩/alpha、PDF JPX 语义、原始组件与最终像素验证，保留明确的资源预算 |
| I-02（已完成） | PDFium native 与 Mozilla/PDFium JS extraWasm | globals/segment/Mask、许可资产与资源限额；native Linux/JS 之外的目标限制见验收记录 |
| I-04（已完成） | 现有 JPEG/JPX/JBIG2 解码与 raw mask、Matte、采样路径 | 原始组件、Decode、encoded-image alpha/Matte、有界解码/减采样；保留 annotation 与旋转 stencil 边缘残差 |
| C-01（已完成） | LittleCMS ICC 转换引擎 | ICCBased/Range/intent、OutputIntent、Default 色彩资源与目标适配；独立 Moon Wasm 保留合法 Alternate，整页残差单列 |
| C-03（已完成） | A2 的共享色彩转换与合成后端 | PDF tint/domain/colorant 与 overprint 色版语义；任意实际墨水联合校样仍需匹配 profile |
| M-01 至 M-03、H-01 至 H-03（已完成） | A2 共用 Canvas coverage、surface 与软件合成层 | PDF group/backdrop/knockout、BC/TR、pattern 资源/矩阵与源分量插值；保留参考分歧、采样和资源限制 |
| A-01 至 A-04（已完成） | pdflite 批注/字段模型、字体 metrics；原生 DOM/表单控件与 Pointer Events | AP/DA/DR、字段继承/状态和特殊外观；保留已接入的屏幕/打印切换、旋转命中和 popup/link，通用输入控件不从零实现 |
| X-01（已完成主路径） | pdflite 对象/content ops、A1 字符串/Form 来源与原生 DOM/ARIA | tagged PDF 来源与阅读顺序关联、AX 角色/所有权及原生分页；人工辅助技术和特殊标签覆盖继续验证 |
| X-02（已完成） | 固定 PDF.js 的纯 XFA parser/binder/paginator/XfaLayer | 复用完整布局组件；接入自己的 pdflite 数据/字体、只读交互/打印，不复用 PDF.js PDF reader |
| V-03（已完成） | 既有 MoonBit/Chromium/视觉 runner 与 CI 平台 | 固定依赖/样本、区分已知差异和新回归、保存报告；不重建测试框架 |

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
- [x] R-03 / P2：复用 Fetch/Streams/Range 和 pdflite xref/对象/流解析，按需读取首页、保留字节来源、64 MiB 双层缓存及回收重载；加密/不支持 Range 服务器全量回退，来源变化明确失败。8.39 MB 样本首页读取 132 KB。见 [收尾验收](readonly-completion.md#http-range)。
- [x] P-01 / P1：页面模型现在验证有效 CropBox/MediaBox 交集、非法/相离回退、非零原点和正值 UserUnit；viewport 保留请求的 `scale` 并用 `scale * user_unit` 计算矩阵与尺寸，SVG 绘制共用该有效缩放。合成边界回归和真实 `issue19176.pdf`（`/UserUnit 72`）的 PDF.js 对照均通过，见 [validation.md](validation.md#page-boundaries-and-userunit)。宿主额外 devicePixelRatio 仍由浏览器层决定。
- [x] P-02 / P1：宿主接入 Worker 启动/失败、优先队列、AbortSignal、文档代次和 close/reopen；替换或关闭文档终止旧 Worker、拒绝待完成任务并清空 DOM/缓存。错误区分文档关闭、非法缩放/旋转、缺页和 Worker 失败；坏新文档不保留旧预览。页面 RPC 已取消时丢弃结果，正在同步解码的页可先完成；不像 PDF.js 提供同构的 loading/render task 对象。回归与差异见 [浏览器宿主验证](validation.md#browser-host-lifecycle-scheduling-and-pressure)。

## 字体与编码

- [x] F-01 / P0：贯通 reader 已解析的水平外部 CMap 的 1–4 字节 codespace 切分、原始字符串、CID 宽度、ToUnicode、Tj/TJ/引号及裁剪；覆盖混合长度、四字节高位和损坏输入。9 个新增测试及真实 `issue18117.pdf` 的绘制抽查通过，见 [validation.md](validation.md#variable-length-horizontal-external-cmaps)。纵排、内置 CMap 与 reader 丢弃的范围由 F-02 至 F-04 跟踪。
- [x] F-02 / P0：支持常用 Adobe 预定义 CMap 到 CID 的准确映射及相关字体绘制。嵌入固定版本的 168 份 binary CMap，按需解码并缓存；贯通继承 codespace/WMode、CID 宽度、CIDToGIDMap 解压和 Adobe CID→Unicode。8 个 CMap 测试和真实 `90ms_rksj_h_sample.pdf` 的绘制抽查通过；资产来源与许可见 `assets/cmaps/`，验证见 [validation.md](validation.md#adobe-predefined-cmaps-vertical-layout-and-word-spacing)。外部 stream 的复杂继承由 F-03 跟踪。
- [x] F-03 / P0：复杂命名/间接 `UseCMap`、缺 codespace、WMode、本地映射优先、notdef、1–4 字节无符号范围与 ToUnicode 共用现有惰性 CMap 恢复；严格 reader 前检查展开量和继承深度，源流不可用时保留 reader fallback，并定位环、坏 token 与资源对象。新增 4 项测试使用固定版本的四份原始 Adobe Japan1 文本 CMap，覆盖 UTF32/surrogate 来源、纵排及 64 层边界；PDF 包装是自建 fixture，明确保留此证据边界。根模块固定 pdflite 的 989 份自然 PDF 扫描有 14 个解析到的外部字体 CMap，没有自然文本/字典 UseCMap 或 reader 丢弃样本。合法 PostScript 字典头和 literal 元数据不误报为坏 hex；现有真实页对照和来源检查通过，见 [A1 收尾验证](validation.md#a1-completion-validation)。
- [x] F-04 / P0：统一纵排的 W2/DW2、垂直原点、带符号推进、TJ 调整与 character/word spacing；绘制、裁剪和选择共用同一 glyph placement。8 个纵排测试通过，覆盖 Identity/外部/预定义 CMap、连续操作、q/Q、引号、rise、剪切、负字号和选择/裁剪；真实 `vertical.pdf` 三页完成转换及 Chromium/Poppler 抽查，见 [validation.md](validation.md#adobe-predefined-cmaps-vertical-layout-and-word-spacing)。
- [x] F-05 / P1：接入 `mizchi/font` 0.7.4 的 cmap 0/4/6/12 与 post 1/2；增加 cmap 2 subheader/别名/相对 offset 和 post 2.5 signed index 的有界格式转换，post 3 合法无名称。Encoding/Differences、Symbol/MacRoman/非 BMP 选表、复合点对齐/scaled offset 与损坏表回退均有覆盖，复制文本独立于选 GID。新增 4 项旧格式/损坏 sfnt 回归，真实字体对照、来源和 Chromium FontFace 检查通过；缺 cmap 子集的 FontFace 拒绝不妨碍路径绘制与选择。罕见 cmap 8/10/13、厂商 post 和字体库未支持的缺表/复合轮廓保留既有恢复路径，见 [A1 收尾验证](validation.md#a1-completion-validation)。
- [x] F-06 / P1：Type 1/CFF 非默认 FontMatrix、缺字、截断 charstring、坏子程序和整个损坏程序保留复制文本、PDF advance 与后续页面，无法使用的轮廓有诊断回退。Type 1 hint replacement 保留 OtherSubr 参数，flex 从当前点使用相对坐标；CFF 显式名称缺失选择 `.notdef`，不冒用其它字形。新增 6 项程序恢复回归；真实 `tracemonkey.pdf` 第一页的 1,549 个缺失嵌入轮廓/宿主回退降为 0，`issue14462_reduced.pdf`、`issue17147.pdf` 继续可测量。整页栅格化差异仍保留，多 FD CID Type 1 等罕见分支继续回退，见 [A1 收尾验证](validation.md#a1-completion-validation)。
- [x] F-07 / P0：携带固定 PDF.js 版本的 10 个 Foxit CFF 和 4 个 Liberation Sans TrueType 程序，来源、许可和 SHA-256 保存在 `assets/standard14/`。复用现有轮廓读取器完成标准 14 的绘制和裁剪，AFM/PDF Widths 保持定位；subset 名称、Symbol/Zapf、WinAnsi bullet 默认槽、Differences、ToUnicode 独立复制、嵌入程序优先与显式宿主 override 均有回归。11 项新测试及四后端 322/322 通过；强制 PDF.js 使用同一套固定字体程序的 16/16 真实页对照无测量失败，另复跑 10 份字体样本。标准字体页仍有 116,689–128,412 个超容差像素，包含表格描边和字形栅格化差异；本项完成确定性字体路径，不表示 A2 整页像素已对齐。证据见 [validation.md](validation.md#standard-14-fonts-and-host-fallback)。
- [x] F-08 / P1：提供宿主字体解析/注入入口及系统字体回退策略；`PdfFontFallback` 和 `PdfViewerDocument::with_font_fallbacks` 接受资源名或 `/BaseFont` 到 CSS 字体族的映射，嵌入 TrueType/OpenType 仍优先使用文档字节；JS bridge 的 `set_font_fallbacks(json)` 清空页面缓存后重新使用该策略。该宿主 override 接口只指定本机/已许可字体族，不传入字体文件；F-07 的随包 Standard 14 程序另行提供。库层回归和 Chromium bridge 检查见 [validation.md](validation.md#host-font-fallback-policy)。

## 文字与选择模型

- [x] T-01 / P0：提取、复制/框选、搜索和 DOM text layer 共用页面逻辑顺序，paint-order 与原始 quad 保持不变。复用 bidi UAX #9 核对方向和多 scalar glyph；基线投影覆盖旋转/剪切、通栏标题与双栏，短表格逐行、长栏逐栏，控制符/显式换行及跨方向空隙共享分隔符。新增 8 项回归，345 项四后端和 10 份真实字体来源检查通过。无 tags 的短表格/段落是几何启发式；无法核对的 bidi 仍保留内容顺序，见 [A1 验证](validation.md#a1-fonts-unicode-and-reading-order)。
- [x] T-02 / P1：`text_sources()`、`text_provenance(n)`、`text_lexical_sources(n)` 和 `text_structure()` 连接 UTF-16、稳定 item、charcode bytes、CID/GID/名称、字体/程序、内容流、Form 调用、词法拼写和 run/几何段落。复用 pdflite lexer/parser 与既有选字逻辑，支持转义/hex/TJ、变长 CMap、字体继承、ExtGState、q/Q、解密、bidi、连字和 surrogate pair；空复制字形保留词法来源。只有 backing bytes 与原输入一致的未压缩/未加密流才有文件字符范围；压缩/加密流返回解码位置及完整原流范围，未知或超限位置显式缺失。来源与搜索/选择共用逻辑顺序，推断分隔符不编造字节 owner；段落是几何推断。15 项新回归、四后端 337/337 及 10 份真实样本的 5,409 个 glyph 来源检查通过，见 [A1 验证](validation.md#file-spelling-empty-glyph-origins-and-text-structure)。
- [x] T-03 / P0：全面对齐 Tw 的编码语义：只有原始单字节 0x20 应用 word spacing。所有 CID 字体共用按 byte length 判定的主路径；4 个独立字距测试及外部 CMap/纵排测试覆盖 standard、simple、Type 3、Identity 与预定义 UTF8/UTF16/UTF32。ToUnicode 把别的字符映射为空格也不会触发 Tw，见 [validation.md](validation.md#adobe-predefined-cmaps-vertical-layout-and-word-spacing)。
- [x] T-04 / P1：字体字典、Encoding/Differences、缺失/损坏 metrics、非法 ToUnicode 和字符码共用恢复入口；保留有效 PDF widths，Unicode 目标非法时回到正常 Encoding，空串与字面 U+FFFD 不判为损坏。`text_recovery_diagnostics(n)` 连接实际字体绑定、page/item/charcode、原字符串 bytes、资源路径和对象号；空复制字形也有来源，旧文档诊断只投影有逻辑范围的记录。新增 10 项回归，含循环字体/descriptor/stream、巨大 CID widths、缺 Tf 和合法间接 Encoding/真实 CMap 头的误报检查；四后端与真实来源/诊断连接全部通过。恢复观察不证明作者原意或 bytes 未损坏，见 [A1 收尾验证](validation.md#a1-completion-validation)。

## 绘制、图片与色彩

- [x] G-01 / P0：完整 CTM、独立 pen、dash/caps/joins 与 A1 嵌入及固定 Standard 14 轮廓已接入；默认发布的网页 bridge/runtime 无需宿主轮廓回调，621-byte 非均匀/剪切文字复现的 24 个绘制模式/旋转/缩放组合与相同字体的嵌入控制像素完全一致。14 字体和 8 种 Tr 状态另有模型回归，native CLI 默认轮廓输出也与网页逐字节一致。显式宿主 override 或非标准 fallback 缺轮廓时仍报 `PDF_TEXT_STROKE_GEOMETRY`，strict 拒绝、网页可见警告；capable native 宿主可用可选回调。未声称浏览器 DOM 或任意宿主字体精确。见 [Standard 14 pen](validation/standard14-pen.md)和[宿主边界](validation/host-text-pen.md)。
- [x] G-02 / P1：独立填充/裁剪 winding、延迟 W/W*、空裁剪、多层 Form 交集、hairline dash、miter 和退化 cap 进入 Canvas 主路径；模型测试、真实 CFF/affine fixture 与像素回归通过。非 hairline 的亚像素覆盖遵守几何，不用强制一像素掩盖不同参考 rasterizer 策略。见 [A2 验收](a2-acceptance.md)。
- [x] G-03 / P0：公开 `PdfPageModel.canvas_plan()` 和共享 Canvas2D 后端处理 RGBA surface、clip、独立 shape/alpha 及 PDF group 语义；网页主页面/缩略图和 native CLI→plan→PNG 均已接入。真实发布入口在 native Canvas 宿主验证；当前环境未重跑 Chromium DOM。SVG 保留兼容 API 和明确降级诊断。见 [native 入口](validation/native-canvas-setup.md)。
- [x] I-01 / P0：固定并扩展成熟 MoonBit JPEG2000 解码器的多组件入口，接入 JP2 palette/sYCC/ICC、1–16-bit 分量、Decode、嵌入 alpha 与外部 mask。四个 Moon 目标验证原始组件，真实 JPX/SMask fixture 验证样本和最终图像。异常编码和资源预算明确失败；大图耗时未伪称交互性能。见 [JPX 目标与限制](../codecs/jpx/README.md)。
- [x] I-02 / P0：复用 PDFium 原生解码与 Mozilla/PDFium JS extraWasm，覆盖 globals、常见 segments 和 mask；公开图片管线输出普通 PNG。真实大幅 `JBIG2Globals.pdf` 的 packed samples 在 native/JS 一致，实际发布入口最终像素最大差 1。交付许可证、来源、native Linux 构建与 JS 资产；其他 native 平台/独立 Moon Wasm 无此适配并明确失败。见 [JBIG2](../codecs/jbig2/README.md)。
- [x] I-03 / P0：viewer 在自己的 image resource 适配层保留 `Op_InlineImage` 的 `DecodeParms`，并把它合并到临时 image stream；真实页面模型回归覆盖 CCITT Group 4（`K=-1`）、Group 3 1D（`K=0`）、1-bit `/Decode [1 0]`、序列化后的 ImageMask，以及 Flate + PNG Predictor 12。每个 fixture 都重新写入/读取 PDF，最终浏览器 PNG 的 IHDR、压缩 IDAT 解压结果和关键像素均有断言；此前丢弃 `DecodeParms` 会使 CCITT 的 `/Columns`、`/Rows`、`/K` 无法进入解码器。当前仍依赖 pdflite 已支持的 filter/CCITT/predictor 解码，真实外部 image corpus、JPX/JBIG2 和原始样本空间的 color-key/Matte 语义分别由 I-01、I-02、I-04 跟踪，验证见 [validation.md](validation.md#inline-image-decode-path)。
- [x] I-04 / P1：JPEG/JPX/JBIG2 保留原始样本后处理 Decode、color-key、SMask/explicit mask 和 Matte，避免重复 alpha；加入有界解码及大图减采样。真实 `issue13931` 的 12,750,976 个 alpha 样本完全一致，发布 Canvas 整页与 PDF.js 最大差 7、零像素超过 8；七个 Lab/color-key/raw mask 页面完全一致。annotation 与旋转 stencil 边缘残差另列。见 [图像采样](validation/image-sampling.md)、[JPEG](jpeg-decoder.md)。
- [x] C-01 / P0：真实 LittleCMS ICCBased/输出 profile、Range、intent、PDF/X OutputIntent、Default 色彩资源及有界生命周期已接入；JS extraWasm/native Linux 实测，独立 Moon Wasm 保留合法 Alternate 能力。原始 Altona 的 ICC/CalRGB 色块和过程色 overprint 与独立同 profile CMM 精确一致；4,707 个参考平坦区残差按源 paint、色版可用性、intent、字形、coverage 与图像采样全部归因。动态无效 ICC Alternate 和 raw ICC/CalRGB mesh 也走真实样本。整页仍有差异，不能把色彩验收叫作整页通过。见 [色彩记录](a2-colour-validation.md)和[采样复核](validation/print-bitmap-sampling.md)。
- [x] C-02 / P1：CalGray gamma/tone curve、CalRGB gamma/Matrix 列序、白点 normalization/黑点补偿、Lab D50/D65 输出和 component Range 已进入共享转换主路径；named `CS/cs`、默认样本、q/Q 和嵌套 Form scope 均有 reader 回归。固定 PDF.js 本身忽略 CalGray 非默认 BlackPoint、Lab BlackPoint 和 `/ri`，viewer 采用同样行为。真实 `calgray.pdf` 3 页、`calrgb.pdf` 17 页和 `issue10339_reduced.pdf` 的 1,432 个色块抽样 RGB 全部一致；整页字体、阅读顺序、图像插值和边缘差异继续由 F/T/G/I 项跟踪，不把此勾选解释为整页像素一致。验证见 [validation.md](validation.md#calibrated-colours-and-original-image-samples)。
- [x] C-03 / P1：完整 tint/domain、None/All、原始分量、OP/OPM 及组边界进入像素主路径；16 个 CMYK blend/色版及真实 DeviceN 页面分层验证。additive display 的 Separation/DeviceN 按 ISO 使用 alternate；任意实际墨水联合校样须有匹配 profile，不能由 RGB 倒推。见 [色彩](a2-colour-validation.md)与[合成](a2-compositing-validation.md)。

## 透明组、mask 与 pattern

- [x] M-01 / P0：实现 isolated/non-isolated backdrop、knockout、嵌套组、原始过程色/ICC/校准 blending space 和文字 TK；实际 PDF 与真实 regression 页面经独立参考和逐像素检查。脏矩形 replay 与全 surface replay 在 64 个组合及真实 Altona 上逐字节等价。见 [合成](a2-compositing-validation.md)、[文字 knockout](validation/text-knockout.md)。
- [x] M-02 / P0：结构化 replay 保留 Alpha/Luminosity、安装时 CTM、组空间 BC、TR、边界与作用域，图像局部 mask 优先级独立。真实 soft-mask 页面与 authored 嵌套组/文字回归验证，ICC mask 缺失能力显式报错。不同参考对嵌套 knockout 的分歧保留在 [合成记录](a2-compositing-validation.md)。
- [x] M-03 / P0：16 种 PDF blend、偏好数组、CompatibleOverprint 与独立 shape/opacity 进入软件合成层，Canvas 提供几何 coverage。RGB 完整 PDF 对照最大差 2、零像素超过 8；16 个 CMYK 模式与 Ghostscript 色版每通道相差不超过 1/255。见 [合成记录](a2-compositing-validation.md)。
- [x] H-01 / P0：uncolored base paint 在现有字形 lowering 前应用，fill/stroke 独立资源，保留 stream-base matrix 与正负 lattice。路径、文字、inline/external ImageMask 均进入同一图案入口。真实 tiling corpus 与 21 页 stencil 回归保留透明单元边缘过滤策略残差，不宣称整页完全一致。见 [pattern stencil](validation/image-patterns.md)。
- [x] H-02 / P1：完整 cell plan 保留文字、图片、Form、透明组、clip 和局部资源；每 tile 使用实际 backdrop，缓存有界且按生命周期释放。负 step、复杂单元、Multiply 与 knockout 的 PDF 对照分别完全一致或每通道差不超过 1；嵌套 Type3/文字场景沿用 A1 解析结果。见 [合成记录](a2-compositing-validation.md)、[Type3 场景](validation/type3-scenes.md)。
- [x] H-03 / P0：保留 Gouraud/Coons/tensor 原始分量，先插值再求 Function/色彩；补二维 Type1、axial/radial Extend、Type7 Matrix、受检验的 adaptive lookup 与设备空间细分。分析像素及真实 Coons/tensor 验证，PatternType2 ExtGState 的规范/参考分歧完整保留。超预算明确报错，无黑色静默回退。见 [shading](a2-shading-validation.md)与[shading pattern](a2-shading-pattern-validation.md)。

## 批注、只读表单与文档功能

- [x] A-01 / P1：补齐缺失 AP 的命名图标、caret/stamp、line ending、IC/CA、虚线/边框和 squiggly；NoZoom/NoRotate 的外观及命中与打印分别处理，实际 AP 优先且不重复施加透明度。真实上游批注与 Chromium 回归覆盖，视觉差异保留。见 [收尾验收](readonly-completion.md#annotations-and-readonly-fields)。
- [x] A-02 / P0：无 AP 的 FreeText/Tx 复用 DA/DR 继承、字体编码/CID widths/metrics 和内容绘制管线，覆盖多行/CRLF/换行、Q、auto size、comb/MaxLen 和 password；SVG 元数据也屏蔽密码。typed ops 与实际浏览器通过，rich-text 编辑另计。见 [收尾验收](readonly-completion.md#annotations-and-readonly-fields)。
- [x] A-03 / P1：choice 保留 export/display、重复值的 I 选中索引、TI、列表选中色和 combo 标签；button/radio 保留继承 V/DV、Kids/Opt 身份和 MK caption。只读外观与字段模型通过测试，填写/保存另计。见 [收尾验收](readonly-completion.md#annotations-and-readonly-fields)。
- [x] A-04 / P1：轻量交互数据保留原 `/Annots` 索引、PDF-space bounds/quads、内容与 URI/本地/远程/named-action 目标；不解码 AP，循环名字有界解析且保持未解析状态。原生 DOM 链接与 popup 支持鼠标/键盘、Escape 返回焦点、XYZ/Fit 和页码/历史；markup 拖选仍进入来源映射，未知/远程/action 保持禁用。打印按 Print 标志选择 AP，与显示缓存分开，NoView/Print 可仅打印，Hidden 同时抑制。上游 `1f9db19` 的真实批注/隐藏 widget、四旋转/缩放、重绘/关闭回归通过，尚未代表 A2 合并后的 DOM 复跑；NoZoom/NoRotate 等特殊图标/AP 外观已由 A-01 补齐，编辑与保存仍在扩展路线。见 [批注验收](validation.md#readonly-annotation-interaction-and-print-intent)。
- [x] D-01 / P1：viewer API 已解析旧式 `/Dests` 字典和 `/Names` `/Dests` name tree，覆盖 named/explicit destination、`XYZ`、`Fit`、`FitH`、`FitV`、`FitR`、`FitB`、`FitBH`、`FitBV`；`destination_for_page`、`named_destination`、`named_destinations_json` 和 `outline_navigation_json` 提供一基页码及结构化视图。当前文档页会标记为 `resolved`，远程页保留 `remote_page` 并不会误跳到本地；本地目录点击和滚动定位已由 D-03 接入，批注链接已由 A-04 接入。destination 回归见 [validation.md](validation.md#destinations-and-document-navigation)。
- [x] D-02 / P0：viewer 读取 pdflite 的 `/OCProperties`、默认/备用配置和 `/ON`/`/OFF`，在 display-list 收集阶段过滤文字、路径、图片、inline image、shading 及带 `/OC` 的嵌套 Form；`PdfOptionalContentState` 按 OCG 对象号选择配置并覆盖状态，隐藏文字不会进入 text clipping、text content、operator list 或 selection。回归 fixture 覆盖默认关闭、显式打开和选择结果，当前四后端 209/209 通过，见 [validation.md](validation.md#optional-content-visibility)。OCMD 的常见 `/P` 与 `/VE` 表达式已支持；usage、RBGroups、Locked 的 UI 语义和浏览器图层面板仍是后续图层工作。
- [x] D-03 / P1：独立浏览器已接入 outline 目录树、page label 状态、Info/XMP 面板和附件清单；本地 destination 点击可滚动到目标页，远程或未解析目标保持禁用；附件和 XMP 通过 bridge 按需下载，不把字节放进打开文档的状态 JSON。`nested_outline.pdf`、`labelled_pages.pdf` 和 `attachment.pdf` 的 Chromium 回归覆盖目录、缩略图/信息入口、页标签、metadata 和附件字节；批注链接由 A-04 接入，OCG usage/RBGroups/Locked 的图层 UI 仍待完成。

## 独立浏览器体验、可访问性与验证

- [x] U-01 / P0：独立静态浏览器 viewer 和 MoonBit JS 入口已贯通，本地文件/拖放、错误恢复、页码、缩放/旋转和下载可用。`moon run tools/dev.mbtx 4312` 可独立调试；`tools/build_web.mbtx` 生成可部署的 `web/`。真实文件输入与错误恢复经过 Chromium 验证，见 [validation.md](validation.md#standalone-browser-and-native-cursor-selection)。
- [x] U-02 / P0：`PdfPageModel::text_layer()` 把 glyph 四边形转换为 DOM 几何，覆盖轮廓和字体绘制；原生鼠标拖选、复制、Shift＋方向键和文档全选经过 Chromium 检查，包括旋转和纵排。浏览器层使用正常字号与归一化 affine，避免 1px 字体放大时拖选失效；批注/链接交互由 A-04 接入，特殊批注外观及只读字段布局已由 A-01 至 A-03 补齐。
- [x] U-03 / P1：`select_text()` 用 item index 和 UTF-16 offset 返回文字、源 glyph 索引和 PDF-space quads；支持反向端点及部分 ligature，拒绝拆开 surrogate pair。跨行/跨页选区包含文件信息，缩放/旋转后按相同来源端点恢复原生高亮；浏览器回归覆盖旋转、纵排和 14 页文档全选。原始 PDF byte span 的可用边界见已完成的 T-02，阅读顺序/bidi 的实现与限制见 T-01。
- [x] U-04 / P1：库层 `PdfViewerDocument::search()` 返回页码、源 UTF-16 offset/length、原文、bounds 和 item indices；支持大小写、Unicode 分类的整词与 NFKD 归一化/变音符号折叠，并以源字符区间映射展开折叠后的长度。浏览器桥接暴露 `search_pdf`，搜索栏支持选项、结果计数、上下结果、滚动定位和 item 级高亮；空查询、重新打开文件和缩放/旋转后的重绘都会清理或重投影状态。209 个四后端测试和 33 项 Chromium 检查通过，变音符号映射回归见 [validation.md](validation.md#text-search)。A1 已接入 Unicode 16 NFKD，7 项新增搜索回归覆盖连字、兼容字符、canonical mark 重排、supplementary offset 和独立组合符号；复杂阅读顺序/bidi 主路径由 T-01 验证。宿主搜索现在异步运行于 Worker；完整 locale/case-fold 策略和跨 item 的精确字符高亮仍未完成。
- [x] U-05 / P1：缩略图、连续/单页模式和 `#page=N` 历史保留；轻量页面尺寸不解释内容，正文与缩略图只挂载可见邻近项，缩放/旋转取消旧任务。跨页/全选复制通过来源 API 读取未挂载页，仅保留选区端点附近 DOM。工具栏和 Ctrl/Cmd+P 按原始尺寸准备全部页面、等待字体/图片并在 afterprint 释放；真实导出验证 200 页及 Rotate/UserUnit，重复打印与文档替换无旧结果覆盖。浏览器菜单的直接打印需先走该入口；批注/链接 DOM 和屏幕/打印切换已由 A-04 接通。见 [浏览器宿主验证](validation.md#browser-host-lifecycle-scheduling-and-pressure)。
- [x] X-01 / P1：`accessibility_page_json(n)` 关联页级 MCID、stream/Form 调用、ParentTree、RoleMap、语言/Alt/ActualText 和批注 OBJR；几何段落保留未关联的可见文字。独立 DOM/ARIA 层按结构树顺序暴露标题、段落、列表、表格及原生批注控件，装饰内容和 glyph 重复旁白被排除，source indices 不重编号。真实 `structure_simple.pdf`、`issue6782.pdf`、Unicode fallback 和自建两页 fixture 的 Chromium AX、键盘分页、复制、重绘/替换检查通过；循环/深度和跨页/重复 Form 隔离有四后端回归。逐页旁白随虚拟化挂载，复制/搜索仍使用 A1 来源顺序；PDF/UA、人工 VoiceOver/NVDA 验收及 namespace/MathML 扩展不在本次主路径结论内。见 [可访问性验收](validation.md#tagged-page-accessibility-and-source-association)。
- [x] X-02 / P2：复用固定 PDF.js 纯 XFA 组件，支持模板/数据绑定、字体适配、分页、只读原生控件、来源选择/搜索和全页打印；static XFA 保留 PDF 外观。真实 7 页文档通过，脚本/编辑和外部图像引用不执行。见 [收尾验收](readonly-completion.md#dynamic-xfa)。
- [x] V-01 / P0：`tools/visual_test.mbtx` 使用固定 PDF.js 版本和同一 Chromium，测量清单内全部页面/旋转；历史基线在 `_build/visual-test-1791598324155/` 完成 57/57 个组合测量，0 个失败，55 个存在像素或文本差异，2 个在记录的容差内；包含 `/UserUnit 72` 的 `issue19176.pdf` 与 PDF.js 得到 0 像素差异。`standard_fonts.pdf` 14 页以及 CalGray/CalRGB/Lab、DeviceN 和 color-key mask 均已测量；色块的定向抽样保留为额外诊断，整页差异照常计数。`--strict` 会拒绝差异，输入或渲染失败计入失败数。7 个分类器测试和独立 runner 合约检查覆盖正确匹配、明显错位、漏画及缺失输入。具体结果和限制见 [validation.md](validation.md#automated-pdfjs-visual-baseline)。后续每个渲染功能都要扩大这份基线。
- [x] V-02 / P1：Worker 页面模型 LRU 限 8 页/估算 32 MiB，字体/图片随模型驱逐；Canvas plan/SVG/text-layer 序列化缓存限 12 项/24 MiB，宿主字体宽度缓存限 4,096 项。`runtimeDiagnostics()` 暴露队列、取消、缓存及挂载页。上游独立验收的 53 项 Chromium 检查含 200 页与 12 MiB raw 图片压力、冷热渲染、搜索响应、驱逐、快速重绘和关闭/替换；记录耗时、CDP 主线程/Worker 堆采样峰值及 GC 后保留量。预算限制缓存，原始文档、临时解码、浏览器字体/图片与全页打印不计入其中，不承诺进程 RSS 上限；上述压力数据尚未在 A2 合并后复跑，自然大文件覆盖继续扩充。见 [浏览器宿主验证](validation.md#browser-host-lifecycle-scheduling-and-pressure)。
- [x] V-03 / P1：四 Moon 后端（含 Linux 必需 native 引擎与 macOS fallback）、26 份固定 SHA corpus、12 个 Canvas 视觉组合、104 项浏览器及差距表检查已接入 CI；锁定工具链/依赖/对照源码，保留许可与输出 artifacts，已知视觉差异有显式门槛。见 [收尾验收](readonly-completion.md#continuous-checks)。

## 推荐推进顺序

1. 保持合并后的 A1 字体/来源和 A2 Canvas/合成主路径回归；Default Standard 14 独立 pen 已验收，显式宿主 override 的能力诊断与嵌套资源策略须持续覆盖。
2. 保持 [6 项已修复回归](readonly-completion.md#continuous-checks) 的定向检查及合并后 Canvas/DOM、可访问性、调度与压力基线。现有缓存/工作集限制不是总进程 RSS 保证。
3. 只读 50 项完成后，保留固定 CI/视觉差异记录；下一阶段推进下方编辑、填写/保存和签名路线。
4. 扩大真实 PDF 的同策略对照，保留原始整页差异；不要用覆盖率、导出成功数或目标测试数代替视觉兼容率。

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
