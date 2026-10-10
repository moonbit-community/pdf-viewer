# W4 色彩管理

TODO：C-01、C-03

状态：归档专题资料。本文的旧文件归属和多角色安排已被
[PARALLEL.md](../PARALLEL.md) 中的两条主线替代，不作为当前分工。

## 复用策略

先按 [ICC 候选](../codec-candidates.md#icc-与颜色) 评估 LittleCMS 等已有转换引擎，
比较 native 薄绑定与浏览器额外 Wasm 模块，明确四后端边界；不默认从零实现 CMM/LUT。
`enanandesu/icc@0.1.1` 只返回 profile 元数据，可作诊断候选，不提供颜色转换。
PDF ICCBased/Range/alternate、专色/tint/overprint 与现有恢复策略由本模块适配。

## 负责范围

提供路径、文字、图片、pattern、shading 和 mask 可共用的色彩转换。
CalGray/CalRGB/Lab 主路径已经完成；CMYK 仍是固定 PDF.js 的 SWOP 拟合，
ICCBased 仍走 alternate，二者不能当作已实现 profile/LUT 色彩管理。

| TODO | 子任务与验收重点 |
| --- | --- |
| C-01 | ICC profile 解析/LUT/输出空间与 CMYK 转换；真实印刷 PDF，合法 alternate 与损坏 profile 恢复 |
| C-03 | Separation/DeviceN 特殊 colorant/domain、alternate/tint、overprint 的最终可见输出 |

## 文件边界

本模块维护 `colour.mbt`、`colour_wbtest.mbt`，可新增 ICC 引擎适配、PDF tint
实现与测试。`image_colour.mbt` 归 W3，`mesh.mbt`/`patterns.mbt`/`masks.mbt`
归 W6；由消费者接入共享转换，避免本模块顺手改所有 paint 路径。
content colour state 的公共入口由集成 Agent处理。

## 推荐首轮切片

先用 RGB/Gray/CMYK profile fixture 验证候选引擎/API 和所需目标，再接共享转换。
确定输入组件范围、输出色彩空间和量化规则；没有合适依赖时记录具体原因及局部缺口。
用固定 PDF.js/成熟色彩实现作真实对照，新增专用 manifest 和采样诊断。
已有校准色彩抽样须保持，避免只改善一份 CMYK 文档却退化 Lab/CalRGB。

overprint 需要输出色版和 compositing 语义，依赖 W5/W6；
不能只在 RGB hex 转换函数里加标记就声称 C-03 完成。
接入前和 W5/W6 记录颜色/alpha 的约定，明确转换和合成的先后次序。

## 验证与交付

覆盖 RGB/Gray/CMYK profiles、matrix/LUT、组件 Range/Decode、Indexed
base space、Separation/DeviceN、zero-domain、None/All colorant、损坏 profile。
复跑 `colour_wbtest.mbt` 和现有校准色块诊断，再扩真实印刷样本。
`devicen.pdf` / `devicen-none-zero-domain.pdf` 当前仍有差异，保留作为回归。

交付引擎选择/适配及确认的局部缺口、支持/未知的 ICC 分支、profile 许可来源、样本证据和
各消费者接入补丁。转换数值通过不等于整页 blend/overprint 已对齐。
