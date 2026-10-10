# W1 字体、编码与 reader 恢复

TODO：R-02、F-03、F-05、F-06、F-07、T-04

状态：归档专题资料。本文的旧文件归属和多角色安排已被
[PARALLEL.md](../PARALLEL.md) 中的两条主线替代，不作为当前分工。

## 复用策略

先按 [生态候选](../codec-candidates.md#字体与-unicode) 验证 `mizchi/font@0.7.4`
的 `parse_font` 和按 GID 的轮廓/metrics。PDF charcode/CID/GID、Widths、FontMatrix
继续由现有适配层处理；不使用 Unicode cmap 代替 CIDToGIDMap。裸 CFF、Type 1、
缺表子集和损坏字体分别核查，不能把 OpenType-CFF 支持当成它们都已覆盖。
reader/CMap/AFM 先复用 pdflite 和已有资产；只有确认的缺口才扩展本地解析算法。

## 负责范围

补 viewer-local 损坏文档/字体/CMap 恢复，保留正常 pdflite reader 路径。
错误需要可定位到资源/对象/字符；恢复失败不应无声丢掉整页文字。
Standard 14 的 AFM 定位已存在，宿主字形高保真和缺字诊断仍待完成。
字体许可与宿主回退策略沿用现有方案，不擅自捆绑字体文件。

| TODO | 子任务与验收重点 |
| --- | --- |
| R-02 | 扩大损坏 xref/页树/object stream/资源继承的真实覆盖；不得恢复错误 xref 版本或绕过加密 |
| F-03 | UseCMap 继承、reader 丢失数据、真实样本与可读取诊断；保持 CID/Unicode 分离 |
| F-05 | TrueType cmap/symbol/composite/损坏字体，核对 font mode 与 outline mode |
| F-06 | Type 1/CFF FontMatrix、charstring、缺字恢复；真实失败 glyph 可追踪 |
| F-07 | Standard 14 宿主字形覆盖、确定性策略/诊断与真实像素差异 |
| T-04 | 损坏文本/未知字符/缺失 ToUnicode 或 metrics 的统一诊断；和 W2 约定来源位置 |

## 文件边界

本模块维护 `reader_recovery.mbt`、`font_recovery.mbt`、`cmap_recovery.mbt`、
`cmap_text.mbt`、`binary_cmap.mbt`、`builtin_cmap.mbt`、`cid_mapping.mbt`、
`cid_geometry.mbt`、`truetype_outline.mbt`、`cff_*`、`type1_*` 及各自专用测试。
资产文件只有需要更新映射且记录固定来源/许可时才改。

`pdf-viewer.mbt` 的 font resources/collector、`text_layout.mbt` 的操作适配、
`text_clipping.mbt` 和 `svg.mbt` 由集成 Agent 接入。
W2 提出的 charcode/CID/GID/原始 bytes 数据由本模块提取，
公共来源模型由集成 Agent统一，避免两个 Agent各建一套映射。

Type 1 复用 CFF path state、编码表与 path helper，二者暂由同一 Agent 负责。
F-07 的 metrics/host family/display filtering 辅助块目前也在主文件里；
需要独立维护时由集成 Agent 先原样移到专用文件，再交接，不和其他主路径改动
同时进行。CMap/字体/字符串的恢复事件统一进入 T-04 诊断模型。

## 推荐首轮切片

先用相同 font bytes/GID 比较现有实现与候选库，记录能直接替换的路径和
需要扩接口/保留现有恢复的分支。再定位 `issue14462_reduced.pdf` / `tracemonkey.pdf`
已测量的 Type 1/CFF 失败 glyph。为适配或具体缺口修复保留可复现的 charstring
回归和真实页面输出；不要把合法 reader 恢复或 host font 替换当成轮廓已对齐。
F-03 的真实 UseCMap corpus 缺口需单独寻找，不能只补合成测试就勾选。

## 验证与交付

先跑对应 `type1_font_wbtest.mbt`、`cff_outline_wbtest.mbt`、
`font_recovery_wbtest.mbt` 或 CMap 测试。reader 改动复跑密码和 xref 恢复回归。
使用 `tools/cmap_corpus.mbtx` / `tools/corpus.mbtx` 定位覆盖，
再给真实样本增加模块自己的视觉 manifest；转换成功不等于像素匹配。

交付具体恢复分支、来源/错误模型、窄测试结果、真实差异及共享入口补丁。
T-04 的诊断 API 未接通宿主前只能记为内部恢复，不能算整项完成。
