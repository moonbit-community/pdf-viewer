# A1 字体与文字

目标：让 PDF 文字能正确显示、按合理顺序提取，并且搜索/选择仍能定位原字符。
这是一条完整的文字处理主线，当前不承担浏览器 UI。

TODO 范围：R-02、F-03、F-05、F-06、F-07、T-01、T-02、T-04。
共同边界见 [PARALLEL.md](../PARALLEL.md)。

## 工作顺序

1. 验证 `mizchi/font` 按 GID 的轮廓/metrics 接入，改进 TrueType、CFF、Type 1、
   Standard 14 和缺字恢复。保留已有缺表子集/损坏字体路径；裸 CFF、Type 1
   不能直接等同于 OpenType-CFF。扩大 UseCMap 和 reader 恢复的真实覆盖。
2. 验证 `moonbit-community/bidi`，补混合方向与多栏阅读顺序，再完善搜索、
   选择和归一化的字符来源映射及恢复诊断。视觉字形顺序与逻辑提取顺序分开；
   bidi 的 code point index 需要映射到现有 UTF-16 范围。

候选的版本/API 限制见 [生态候选](../codec-candidates.md#字体与-unicode)。
先适配通用库，PDF charcode/CID/GID、Widths、FontMatrix 和恢复语义由本项目处理。

## 已推进

- 接入 `bidi`、`normalization` 和 `ucd` 0.5.2。搜索使用 Unicode NFKD、
  字符分类和大小写数据，保留分解、连字展开、组合符号重排后的原文 UTF-16 范围。
- 混合 RTL/LTR 行使用 UAX #9 置换核对来源顺序和几何，数字串不被整体反转；
  通栏标题下面的多行双栏按栏读取。提取、搜索、选择和 text layer 共用顺序。
- TrueType 绘制按 Encoding/Differences 或 symbol cmap 选 GID，ToUnicode 只决定
  提取文本；复合字形支持点对齐和 scaled offset，并检查 glyph 边界、递归和点数。
- 已单独接入 `mizchi/font` 0.7.4 的 cmap 0/4/6/12 解码，补 Windows Unicode/
  Symbol、MacRoman 与非 BMP 选表，验证读取边界和展开量，使用有上限的 cmap
  缓存。MacRoman 反向映射仍复用 pdflite；有效表的缺字不再冒用原 charcode。
- 继续复用其 post 接口，支持 version 1/2 字形名、Differences 自定义名称和
  Unicode 平台 cmap 的名称优先级；未知名称且无可用 post 时允许显式 ToUnicode
  恢复。检查 post/loca/glyf 边界、空字形和重复名称，缓存限制源数据和解码数量。
- 复用 pdflite 同版本的 `moonbit-community/flate` 0.8.1，恢复完整字体/CMap
  Flate 流的 Adler-32 不匹配；有输入、输出和缓存上限，源对象保持不变。
  覆盖 TrueType、Type 1、CFF、CIDToGIDMap 与继承 CMap 的绘制/裁剪/提取。
  真实 `issue13316_reduced.pdf` 已恢复「开 票 通 知 单」，仍保留像素差异记录。
- 新增 `text_sources()`、页面/文档 `text_diagnostics()`。来源保留 item、charcode、
  字体和 UTF-16 范围；CMap 诊断保留资源路径和直接 stream 对象号。
  ToUnicode 目标串允许多 scalar、内部空白和空串，源字符码仍限制为 1–4 字节，
  避免将合法长目标串误报为坏 token。
  文档诊断新增 `FontStreamChecksumRecovered`，能定位字体程序/CMap 及父流的
  实际资源路径和对象号；观察不表示已证明恢复 bytes 与原始 bytes 一致。
- 新增文档 `text_provenance(n)` sidecar，串联逻辑 UTF-16 范围、字符串操作数中的
  原字符码 bytes/range、内容流引用序列、嵌套/重复 Form 调用和活动字体对象号。
  复用现有 1–4 字节 CMap 解码和 TrueType/CFF/Type 1 选字逻辑，返回可解析的
  CID/GID/字形名；字体继承、`q/Q`、ExtGState、加密字符串、TJ、bidi 和连字均有回归。
  来源采集显式开启，既有公开 record 不变；串内范围不冒充文件词法偏移，宿主 GID
  和未知映射不编造。`tools/text_provenance_corpus.mbtx` 可复跑真实字体清单。
- 活动字体对象现在同时供 TrueType/Type 3 绘制、文字裁剪和 CID ToUnicode 恢复使用，
  不再在 Form 的资源表中按旧名字重查。页面字体资源从实际绑定注册，同名且不同对象
  使用稳定的局部别名；ExtGState 使用与 Tf 相同的 metrics/校验和恢复。
  常规绘制跟踪字体绑定，字符串 bytes 来源仍按需采集；6 项专用回归通过。
- Standard 14 使用固定 PDF.js 版本的 10 个 Foxit CFF 和 4 个 Liberation Sans
  TrueType 程序，来源、许可和 SHA-256 见 `assets/standard14/`。复用现有轮廓读取器，
  AFM/PDF Widths 仍负责定位；嵌入程序和显式宿主 override 保留优先级。
  绘制/裁剪/复制共享 WinAnsi bullet 默认值，Differences 和 ToUnicode 各司其职。
  11 项回归和 16 个真实页面通过；整页描边/栅格化差异仍在视觉报告中保留。
- `text_lexical_sources(n)` 复用 pdflite lexer/parser，将原字符码连接到 literal/hex
  词法拼写、内容流和 Form 调用；空复制字形也有来源。未压缩/未加密且 backing
  bytes 与原输入一致时才给文件偏移；压缩/加密流保留解码位置和完整原流范围。
  `text_structure()` 按共同的逻辑顺序提供 run/几何段落及其 UTF-16/source ranges。
  15 项新回归、四后端 337/337 和 10 份真实字体样本的来源检查通过。
- 用独立 `.mbtx` probe 验证 `mizchi/font`：缺 cmap 的 PDF 子集和裸 Type 1
  程序仍不可用，复合字形剪切/点对齐/缩放偏移与 fixture 预期不符，因此未替换
  当前字体恢复路径。真实对照和回归记录见 [validation.md](../validation.md#a1-fonts-unicode-and-reading-order)。

- 按文字基线投影处理 90°/180°、剪切和旋转双栏，返回原始 glyph/quad；
  三行以上对齐的短单元格按表格逐行读取，长文本仍逐栏。bidi embedding/isolate、
  零宽控制符、显式换行与跨方向 run 空隙共享 separator 和 UTF-16 来源。
  8 项专用回归、四后端 345/345 和 10 份真实字体样本的来源检查通过。

- cmap format 2 的双字节 subheader/别名/相对 offset 和 post 2.5 的 signed index
  转为现有库可读的格式；截断目录、错误 offset、空表、symbol/复合轮廓保留边界检查。
  Type 1 非默认 FontMatrix 与损坏 charstring、CFF 名称缺失与坏子程序保持原复制文本、
  PDF advance 和后续页面绘制；无法使用的程序进入有诊断的宿主回退。
  Type 1 hint replacement 保留 OtherSubr 参数，flex 使用相对坐标；真实
  `tracemonkey.pdf` 第一页的 1,549 个缺失嵌入轮廓已全部恢复。
- 字体字典、Encoding/Differences、metrics 和 Unicode 缺失/损坏使用共同恢复入口。
  正常编码优先，非法 ToUnicode 目标回到 Encoding，空串/字面 U+FFFD 不误报为损坏。
  CID 宽度/CMap 的展开量在 reader 前检查，过大 CMap 留在现有惰性表示中。
  `text_recovery_diagnostics(n)` 记录活动字体、原字节和资源对象，空复制字形也可定位。
- 四份固定版本的真实 Adobe Japan1 文本 CMap 验证命名/间接父映射、缺 codespace、
  本地覆盖、WMode 和 UTF32 来源；PDF 包装是自建 fixture，来源及许可见
  `assets/cmaps/test-sources/`，不冒充自然出现的 PDF.js corpus 文件。
- reader 继续复用 pdflite；循环/过深页树先限额检查，在独立对象表内保留有效分支，
  原内容流/字体引用和文件来源不变。`reader_diagnostics()` 定位跳过节点。
  优先使用其严格 xref 入口，再做有限页树检查，避免 JS 在依赖的提前探测中栈溢出。
  989 份真实 PDF 载入扫描有 952 份成功、37 份失败；报告保留密码/认证、坏流/xref
  和不可恢复页树的文件及错误。载入成功不代表渲染或像素一致。

本主线的 8 个 TODO 主路径已全部验收：四后端各 374/374、Chromium 39/39，
10 份字体及 5 份 reader 来源检查通过，10/16/5 个字体/标准字体/reader 页组合
均完成 PDF.js 对照测量。证据和真实差异见 [A1 收尾验证](../validation.md#a1-completion-validation)。
保留的限制包括罕见 cmap 8/10/13、厂商 post、字体库尚不支持的缺表子集/复合轮廓，
多 FD 的 CID Type 1、不可恢复损坏流，以及无 tags 的歧义几何段落/短表格。
这些分支保留回退和诊断；无法核对的 bidi 保留内容顺序，不承诺恢复作者未编码的结构。
整页描边、图像/合成和栅格化差异仍由 A2 与视觉基线跟踪。

## 可修改的文件

以下实现文件均位于 `internal/engine/`。根 `api.mbt` 只负责公开导出。

- `font_resources.mbt`、`type3_outline.mbt`、`svg_text.mbt`、`text_selection.mbt`。
- `truetype_outline.mbt`、`cff_*`、`type1_*`、`font_recovery.mbt`、`reader_recovery.mbt`。
- `cmap_*`、`binary_cmap.mbt`、`builtin_cmap.mbt`、`cid_mapping.mbt`、`cid_geometry.mbt`。
- `text_order.mbt`、`text_geometry.mbt`、`text_layer.mbt`、`text_layout.mbt`、
  `text_clipping.mbt`、`search.mbt`，以及对应专用测试和新增文字工具。

`internal/cmap_assets/assets.mbt` 是生成资产，需要更新时保留固定来源和许可。
公共模型/collector 在 A2 的 `model.mbt` / `collector.mbt` 中；需要来源字段或调用调整时，
直接和 A2 交接该局部修改。优先用 sidecar/API，兼容现有公开 record 和消费者。

## 验收

字体改动用相同 bytes/GID 对照，复跑 `issue14462_reduced.pdf`、
`tracemonkey.pdf` 等真实样本；记录缺字、轮廓和定位差异。
文字改动覆盖双向/多栏、连字与 surrogate pair，并验证提取、搜索和选择
指向同一来源；不编造原始字节偏移。恢复诊断能定位资源/字符。

相关回归通过后运行共同检查，交付已接入的路径、真实差异和仍需保留的恢复分支。
