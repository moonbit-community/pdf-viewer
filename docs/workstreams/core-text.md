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
- 新增 `text_sources()`、页面/文档 `text_diagnostics()`。来源保留 item、charcode、
  字体和 UTF-16 范围；CMap 诊断保留资源路径和直接 stream 对象号。
  ToUnicode 目标串允许多 scalar、内部空白和空串，源字符码仍限制为 1–4 字节，
  避免将合法长目标串误报为坏 token。
- 用独立 `.mbtx` probe 验证 `mizchi/font`：缺 cmap 的 PDF 子集和裸 Type 1
  程序仍不可用，复合字形剪切/点对齐/缩放偏移与 fixture 预期不符，因此未替换
  当前字体恢复路径。真实对照和回归记录见 [validation.md](../validation.md#a1-fonts-unicode-and-reading-order)。

这一批没有勾选整个 TODO。后续仍需字体库扩展、其它 cmap 格式、post 表和损坏字体覆盖、
复杂 bidi/表格/旋转布局、PDF byte span 与 CID/GID 来源，以及统一恢复策略和真实
UseCMap/reader 损坏样本。跨方向边界目前保留显式空白，不推断额外空格；
无法核对的 bidi 置换保留内容流顺序。

## 可修改的文件

- `font_resources.mbt`、`type3_outline.mbt`、`svg_text.mbt`、`text_selection.mbt`。
- `truetype_outline.mbt`、`cff_*`、`type1_*`、`font_recovery.mbt`、`reader_recovery.mbt`。
- `cmap_*`、`binary_cmap.mbt`、`builtin_cmap.mbt`、`cid_mapping.mbt`、`cid_geometry.mbt`。
- `text_order.mbt`、`text_geometry.mbt`、`text_layer.mbt`、`text_layout.mbt`、
  `text_clipping.mbt`、`search.mbt`，以及对应专用测试和新增文字工具。

`builtin_cmap_assets.mbt` 是生成资产，需要更新时保留固定来源和许可。
公共模型/collector 在 A2 的 `pdf-viewer.mbt` 中；需要来源字段或调用调整时，
直接和 A2 交接该局部修改。优先用 sidecar/API，兼容现有公开 record 和消费者。

## 验收

字体改动用相同 bytes/GID 对照，复跑 `issue14462_reduced.pdf`、
`tracemonkey.pdf` 等真实样本；记录缺字、轮廓和定位差异。
文字改动覆盖双向/多栏、连字与 surrogate pair，并验证提取、搜索和选择
指向同一来源；不编造原始字节偏移。恢复诊断能定位资源/字符。

相关回归通过后运行共同检查，交付已接入的路径、真实差异和仍需保留的恢复分支。
