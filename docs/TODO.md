# PDF.js 对齐 TODO

更新日期：2026-10-10。范围是这个独立的 MoonBit PDF viewer 的只读预览，
不包含 Office viewer、OpenSeek 接入、编辑、保存表单或执行文档 JavaScript。

对照版本是本地 `reference/pdf.js` 的
`89b500f5e1d98ed89bb90211e45b28730b2d99ac`；PDF 读取依赖为 pdflite `0.2.2`。
这里的“对齐”包括可见输出、文本与选择、独立浏览器体验和稳定性，
不要求照抄 PDF.js 的内部实现或所有返回值结构。

## 还差多少

当前明确跟踪 **50 项，分为 14 个能力领域；完成 7 项，剩余 43 项**。
剩余项按优先级分为 P0 17 项、P1 24 项、P2 2 项；其中部分已有基础实现。
这些项大小不等，
有的只是一个语义修正，有的需要完整解码器或合成器，不能把条目数换算成完成百分比。
已完成 F-01（水平外部 CMap）、F-02（Adobe 预定义 CMap）、F-04（CID 纵排）
和 T-03（编码相关字距），以及 U-01（独立浏览器）、U-02（cursor 选择层）
和 U-03（跨页选择映射及重投影）。复杂外部 CMap 继承和 reader 丢弃的范围仍由 F-03 跟踪。

现在有可运行的 native CLI、页面模型、SVG 输出和独立的浏览器 viewer。
141 个测试在四个后端通过，浏览器有 19 项交互检查，真实 PDF 有转换检查和少量
Chromium/Poppler 视觉抽查，
**没有自动 PDF.js 像素对比，因而还不能给出可信的视觉兼容率**。
转换成功、没有占位、测试通过，都不能单独证明没有漏画或排版错误。
基线细节见 [validation.md](validation.md)。

| 领域 | 当前已有 | 主要缺口 | 剩余项数 | 对应项目 |
| --- | --- | --- | ---: | --- |
| 文档载入 | bytes 读取、页树、部分压缩对象恢复 | 密码入口、恢复覆盖、增量读取 | 3 | R-01 至 R-03 |
| 页面/API | 页面模型、viewport、旋转、显示列表 | 页面边界语义、宿主生命周期 | 2 | P-01 至 P-02 |
| 字体/编码 | TrueType、CFF、Type 1 轮廓；外部变长 CMap；168 份 Adobe CMap；CID 纵排 | 复杂继承、字体恢复、标准/系统字体回退 | 5 | F-01 至 F-08 |
| 文字 | glyph transform、字符级边界、矩形选择、文字裁剪、编码相关字距 | 阅读顺序、bidi、空格和来源映射、恢复诊断 | 3 | T-01 至 T-04 |
| 矢量 | 常见路径、虚线、显式 clip、SVG 输出 | 非均匀描边、精确 raster 输出 | 3 | G-01 至 G-03 |
| 图片 | JPEG、raw/inline 图片、常见 mask | JPX/JBIG2 解码、inline CCITT、完整样本语义 | 4 | I-01 至 I-04 |
| 色彩 | 常见设备色彩和近似转换 | ICC、校准色彩、专色与 overprint | 3 | C-01 至 C-03 |
| 透明合成 | alpha、部分 blend、组标记、常见 soft mask | backdrop、knockout、精确 mask/blend | 3 | M-01 至 M-03 |
| pattern/shading | 彩色路径 tiling、shading 1–7 的部分输出 | uncolored/复杂 tiling、逐像素插值 | 3 | H-01 至 H-03 |
| 批注/只读表单 | AP 外观、基本几何、字段元数据、简单 widget | 无 AP 的完整排版、交互层和子类型覆盖 | 4 | A-01 至 A-04 |
| 导航/图层 | outline、labels、attachments、OCG、metadata 读取 | destination 导航、图层实际过滤、浏览器展示 | 3 | D-01 至 D-03 |
| 浏览器体验 | 独立应用、文件载入、多页滚动、缩放/旋转、cursor 选择及复制、跨页来源映射 | 全文搜索、缩略图、打印与更完整的导航 | 2 | U-01 至 U-05 |
| 可访问性/XFA | structure tree 读取 | 可访问的 DOM、只读 XFA 页面 | 2 | X-01 至 X-02 |
| 验证/性能 | 四后端测试、多页 CLI corpus、Chromium 交互测试、页面缓存 | 像素基线、Worker/取消/缓存上限、大文件与 CI | 3 | V-01 至 V-03 |

“当前已有”只描述实现基础。除非待办满足验收条件并有证据，不把整个领域标为完成。

## 优先级与验收规则

- P0：直接造成缺字、错位、漏图、明显颜色/合成错误，或阻碍实际预览与验证。
- P1：扩大真实文档覆盖，完善只读工作流和可靠性。
- P2：较晚处理的大文件能力或特殊文档类型。
- 勾选要求：代码进入主路径、存在有意义的回归测试，并记录验证结果与剩余限制。
  涉及渲染的项目还需要对应真实样本；若只有合成测试，明确标注，不能声称像素一致。

## 文档载入与页面

- [ ] R-01 / P1：提供密码/加密文档载入入口，验证不同安全处理器、错误密码和只读预览行为。
- [ ] R-02 / P1：扩大 xref stream、object stream、损坏 xref/页树和资源继承恢复的真实样本覆盖；失败可定位。
- [ ] R-03 / P2：支持分段/增量数据来源和网络 range，使大文件不必完整下载后才能打开第一页。
- [ ] P-01 / P1：对齐 CropBox/MediaBox 交集、UserUnit、非零页面原点、viewport offset 与设备像素尺寸语义。
- [ ] P-02 / P1：补宿主可用的任务生命周期、错误分类、资源释放和 API 行为测试；记录与 PDF.js 公开模型的差异。

## 字体与编码

- [x] F-01 / P0：贯通 reader 已解析的水平外部 CMap 的 1–4 字节 codespace 切分、原始字符串、CID 宽度、ToUnicode、Tj/TJ/引号及裁剪；覆盖混合长度、四字节高位和损坏输入。9 个新增测试及真实 `issue18117.pdf` 的绘制抽查通过，见 [validation.md](validation.md#variable-length-horizontal-external-cmaps)。纵排、内置 CMap 与 reader 丢弃的范围由 F-02 至 F-04 跟踪。
- [x] F-02 / P0：支持常用 Adobe 预定义 CMap 到 CID 的准确映射及相关字体绘制。嵌入固定版本的 168 份 binary CMap，按需解码并缓存；贯通继承 codespace/WMode、CID 宽度、CIDToGIDMap 解压和 Adobe CID→Unicode。8 个 CMap 测试和真实 `90ms_rksj_h_sample.pdf` 的绘制抽查通过；资产来源与许可见 `assets/cmaps/`，验证见 [validation.md](validation.md#adobe-predefined-cmaps-vertical-layout-and-word-spacing)。外部 stream 的复杂继承由 F-03 跟踪。
- [ ] F-03 / P0：补齐复杂 UseCMap 继承、缺失 codespace、映射优先级与未定义字符的恢复；遵守 reader 已解析的继承关系。pdflite `0.2.2` 的 signed Int 范围校验还会丢弃部分跨高位边界的四字节范围（如 `<00000000> <FFFFFFFF>`），viewer 解码器尚不能恢复这类缺失的 codespace。
- [x] F-04 / P0：统一纵排的 W2/DW2、垂直原点、带符号推进、TJ 调整与 character/word spacing；绘制、裁剪和选择共用同一 glyph placement。8 个纵排测试通过，覆盖 Identity/外部/预定义 CMap、连续操作、q/Q、引号、rise、剪切、负字号和选择/裁剪；真实 `vertical.pdf` 三页完成转换及 Chromium/Poppler 抽查，见 [validation.md](validation.md#adobe-predefined-cmaps-vertical-layout-and-word-spacing)。
- [ ] F-05 / P1：扩大 TrueType cmap/encoding、symbol 字体、composite 与损坏字体恢复覆盖；明确轮廓模式和浏览器字体模式的差异。
- [ ] F-06 / P1：扩大 Type 1/CFF 的 FontMatrix、缺字、损坏 charstring 和特殊字体程序覆盖；失败不造成整页空白。
- [ ] F-07 / P0：提供可复现且许可明确的标准 14 字体替代与 metrics；字形、advance 和粗斜体匹配。
- [ ] F-08 / P1：提供宿主字体解析/注入入口及系统字体回退策略；浏览器和 native 分开实现，记录替代字体。

## 文字与选择模型

- [ ] T-01 / P0：补阅读顺序、bidi、ligature、组合字符、空格和换行归并；保持文本与 glyph 对应关系。
- [ ] T-02 / P1：补字符码/CID/GID、原始 byte span、文本 run/段落与 selection source 的稳定映射；长文本可定位回源。
- [x] T-03 / P0：全面对齐 Tw 的编码语义：只有原始单字节 0x20 应用 word spacing。所有 CID 字体共用按 byte length 判定的主路径；4 个独立字距测试及外部 CMap/纵排测试覆盖 standard、simple、Type 3、Identity 与预定义 UTF8/UTF16/UTF32。ToUnicode 把别的字符映射为空格也不会触发 Tw，见 [validation.md](validation.md#adobe-predefined-cmaps-vertical-layout-and-word-spacing)。
- [ ] T-04 / P1：统一损坏字符串、未知字符、缺失 ToUnicode/metrics 的回退和诊断；绘制与提取失败不能静默丢失全部文字。

## 绘制、图片与色彩

- [ ] G-01 / P0：保留绘制时的完整 CTM，正确处理非均匀缩放/剪切下的描边、文字描边、虚线和椭圆笔画。
- [ ] G-02 / P1：扩大 hairline、miter、退化路径、填充规则、clip 生效时机和多层 Form scope 的精确覆盖。
- [ ] G-03 / P0：实现可控的像素绘制后端，处理 SVG 无法精确表达的绘制语义；Canvas/WebGL 选型以可验证结果决定。
- [ ] I-01 / P0：实现或接入 MoonBit 可用的 JPEG2000/JPX 解码，使浏览器不依赖原始 image/jp2 支持。
- [ ] I-02 / P0：实现或接入 MoonBit 可用的 JBIG2 解码，覆盖 globals、常见 segment 和 mask。
- [ ] I-03 / P0：补 inline CCITT/mask、filter chain、predictor、bit depth 和 Decode 的端到端覆盖。
- [ ] I-04 / P1：在原始样本空间正确处理 color-key mask、Matte、插值、缩放和大图；不要把已转 RGB 的值当作原始样本。
- [ ] C-01 / P0：实现 ICCBased 和准确的 CMYK 到输出空间转换，验证真实印刷类 PDF。
- [ ] C-02 / P1：对齐 CalGray、CalRGB、Lab、白点/黑点和 rendering intent。
- [ ] C-03 / P1：补 Separation/DeviceN、tint function 和 overprint 可见结果。

## 透明组、mask 与 pattern

- [ ] M-01 / P0：实现 non-isolated transparency group 的 backdrop 和 knockout 合成，包含嵌套组。
- [ ] M-02 / P0：补 soft mask 的完整 Alpha/Luminosity、BC 色彩空间、TR、组边界与作用域语义。
- [ ] M-03 / P0：补完整 blend mode 与 unsupported SVG blend 的确定性回退，使用像素对照验证。
- [ ] H-01 / P0：支持 uncolored tiling pattern，并正确应用调用位置的基础色彩。
- [ ] H-02 / P1：支持包含文字、图片、Form、透明组和独立资源的复杂 tiling pattern；验证矩阵与重复边界。
- [ ] H-03 / P0：实现 mesh Gouraud/patch 的逐像素插值、抗接缝，并扩大函数/轴向/径向 shading 的边界与 Extend 覆盖。

## 批注、只读表单与文档功能

- [ ] A-01 / P1：扩大 annotation 子类型、缺失 AP 的外观、line ending、图标、边框和 markup 的真实样本覆盖。
- [ ] A-02 / P0：按 DA/DR 和字段 metrics 排版无 AP 的 FreeText/文本 widget，覆盖多行、对齐、comb 和 password 外观。
- [ ] A-03 / P1：补 choice 的 export/display 值、列表选中、按钮/radio 状态与只读显示；无需提供编辑能力。
- [ ] A-04 / P1：实现批注命中、popup、链接层与屏幕/打印外观切换；图层坐标须与页面旋转一致。
- [ ] D-01 / P1：实现 named/explicit destination、XYZ/Fit 等文档内导航，并明确远程 destination 的宿主行为。
- [ ] D-02 / P0：解析并执行 optional-content 可见性，实际过滤页面与 Form 内容；目前只有配置读取。
- [ ] D-03 / P1：贯通 outline、page labels、附件、metadata 的浏览器展示和只读下载。

## 独立浏览器体验、可访问性与验证

- [x] U-01 / P0：独立静态浏览器 viewer 和 MoonBit JS 入口已贯通，本地文件/拖放、错误恢复、页码、缩放/旋转和下载可用。`moon run tools/dev.mbtx 4312` 可独立调试；`tools/build_web.mbtx` 生成可部署的 `web/`。真实文件输入与错误恢复经过 Chromium 验证，见 [validation.md](validation.md#standalone-browser-and-native-cursor-selection)。
- [x] U-02 / P0：`PdfPageModel::text_layer()` 把 glyph 四边形转换为 DOM 几何，覆盖轮廓和字体绘制；原生鼠标拖选、复制、Shift＋方向键和文档全选经过 Chromium 检查，包括旋转和纵排。浏览器层使用正常字号与归一化 affine，避免 1px 字体放大时拖选失效；批注/表单的 DOM 交互层继续由 A-04 跟踪。
- [x] U-03 / P1：`select_text()` 用 item index 和 UTF-16 offset 返回文字、源 glyph 索引和 PDF-space quads；支持反向端点及部分 ligature，拒绝拆开 surrogate pair。跨行/跨页选区包含文件信息，缩放/旋转后按相同来源端点恢复原生高亮；19 项 Chromium 检查包含 14 页文档全选。原始 PDF byte span 仍由 T-02 跟踪，阅读顺序/bidi 由 T-01 跟踪。
- [ ] U-04 / P1：实现全文搜索、大小写/整词/变音符号选项、结果定位和高亮。
- [ ] U-05 / P1：在已有多页滚动、页码、缩放/旋转与下载基础上，补缩略图、打印、滚动/分页模式和浏览器历史；避免每次操作重建全文件。
- [ ] X-01 / P1：把 tagged structure tree 和阅读顺序落实到可访问的 DOM/ARIA，而不仅是 JSON。
- [ ] X-02 / P2：支持 XFA 文档的只读页面布局与文本展示，编辑与脚本不在范围内。
- [ ] V-01 / P0：建立固定 PDF.js 版本的自动像素对比、几何/文本比较和差异图；覆盖全部选定页面，区分抗锯齿差异与缺画/错位。
- [ ] V-02 / P1：补 Worker、取消、页模型/字体/图片缓存、内存上限与大文件压力基线；报出耗时和峰值内存。
- [ ] V-03 / P1：把四后端测试、corpus、视觉基线和差距表纳入 CI；固定对照/依赖版本，记录样本来源和资产许可。

## 推荐推进顺序

1. V-01、V-02：在独立浏览器和 cursor 选择的基础上，建立可重复的 PDF.js 对照及 Worker/页面调度。
2. F-03、F-07、F-08：补复杂 CMap 与字体回退，稳定文字绘制。
3. I-01、I-02、C-01：补图像和颜色覆盖缺口。
4. G-01、G-03、M-01 至 M-03、H-01/H-03：补 SVG 近似无法解决的精确绘制与合成。
5. A、D、U 的剩余条目，再扩大 reader、性能、可访问性和 XFA 覆盖。

## 扩展项与维护

多 FD CID-keyed Type 1 可作为扩展，但当前对照版本的
`src/core/type1_parser.js` 也明确只支持单 FD，因此不计入上述 PDF.js 对齐欠账。
不同的 FDArray 声明形式仍需按真实样本评估，属于 F-06 的字体程序覆盖。

每次继续实现后更新本文件：勾选对应 ID，记录验证文件和命令，列出仍未覆盖的分支。
避免把“转成 SVG”或“增加了测试数”直接写成整项对齐完成。
最新结果保存在 [validation.md](validation.md)，分层说明在
[architecture.md](architecture.md)。
