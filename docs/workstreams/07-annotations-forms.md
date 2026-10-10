# W7 批注与只读表单

TODO：A-01、A-02、A-03、A-04

状态：待分配实现切片。共同规则见 [PARALLEL.md](../PARALLEL.md)。

## 复用策略

字段/批注数据先用 pdflite；排版复用 W1 的字体 metrics、W2 的文字边界，
输入和命中用原生 DOM 控件/Pointer Events。项目保留 AP/DA/DR、字段继承和打印外观。
后续批注编辑、表单填写、签名保存先复用 pdflite writer/增量写入，
不另写 PDF serializer；接入与重开验收见 [完整阅读器路线](../TODO.md#完整阅读器的后续接入)。
当前四个 ID 仍是只读基线，不能把 writer API 存在算为编辑/保存已完成。
API 核查见 [既有依赖与宿主候选](../codec-candidates.md#xml宿主与完整阅读器)。

## 负责范围

让批注与字段具有可靠的只读外观和命中/导航体验。保持现有 AP 内容流优先
策略：合法空 AP 也能有意抑制 fallback，不能总是追加自造外观。
源 annotation index、display/print flags、资源/字体作用域保持稳定。

| TODO | 子任务与验收重点 |
| --- | --- |
| A-01 | 更多 subtype、无 AP 的几何/图标/markup/line ending 和真实外观 |
| A-02 | DA/DR/metrics 排版，FreeText/text widget 的 multiline/alignment/comb/password |
| A-03 | choice export/display、列表选中与按钮/radio 状态的只读显示 |
| A-04 | 命中/popup/link DOM、屏幕/打印切换、旋转坐标与页面生命周期 |

## 文件边界与依赖

本模块维护 `annotations.mbt`、`annotations_svg.mbt`、`annotations_wbtest.mbt`
及新字段布局/批注 DOM/helper 文件。公共 `PdfAnnotationItem` 和 AP collector
入口由集成 Agent接入。字体/字符 metrics 复用 W1/W2，坐标复用 viewport/W5。

`web/viewer.js`、CSS、HTML 和 bridge 归 W8；本模块给出数据、独立 DOM 实现
和 mount/update/dispose 调用位置，W8 串行接入。
单纯画出 link 外框不等于链接可用，未知/远程 destination 不伪装成本地跳转。

## 推荐切片

先完成 A-02 无 AP 文本/FreeText 排版，这项直接影响核心预览；
使用真实 DA/DR 与继承字段，而不是固定字号和任意居中。
再补 choice/button 状态和 DOM。本轮四项先验收只读显示；后续编辑/保存属于完整
阅读器目标，另拆任务接现成 writer；文档 JavaScript 不在当前任务内。
现有 `field_options : Array[String]` 未保留 choice 的 export/display 配对，
A-03 需要扩元数据或 sidecar，并经集成 Agent 处理公开模型兼容性。

## 验证与交付

覆盖 AP 状态字典、无/空 AP、多层字段继承、字体与 colour scope、
多行/对齐/comb/password、export/display 与 radio on-state；检查自身 clip。
保留 `annotation-freetext.pdf` / `annotation-highlight.pdf` 的视觉基线，
扩大真实 fixture。W8 接入 Chromium popup、link、旋转、print 和卸载回归。

交付各 subtype/字段支持范围、外观证据、DOM 事件/生命周期接入补丁。
模型 JSON 存在不等于可交互层已经进入 demo。
