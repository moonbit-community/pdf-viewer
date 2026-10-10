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
