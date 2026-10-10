# W8 宿主调度与工程验证

TODO：R-03、P-02、U-05、V-02、V-03

状态：待分配实现切片。共同规则见 [PARALLEL.md](../PARALLEL.md)。

## 复用策略

Worker/MessageChannel、AbortController、Fetch/Streams/Range、IntersectionObserver
与 ResizeObserver 优先用浏览器 API；宿主 JS 可直接使用，MoonBit JS 绑定可评估
`mizchi/js_web`，不要重造线程/网络层或为了可见页检测引入整套 GUI。
已有 async 和公共 runner 继续复用。项目负责任务代次、缓存预算、页面生命周期
和 PDF 按需数据接口；Range transport 不等于 pdflite 已支持分段读取。
版本/核查边界见 [生态候选](../codec-candidates.md#xml宿主与完整阅读器)。

## 负责范围

完善独立浏览器的生命周期与性能，同时维护公共构建/交互/视觉验证入口。
当前独立 viewer、cursor 选择、跨页映射、目录/metadata/附件/搜索已存在。
每次缩放/旋转仍会重建页面，Worker、取消、虚拟化和内存上限尚未实现。

| TODO | 子任务与验收重点 |
| --- | --- |
| P-02 | 宿主任务/错误分类、document/page 释放、API 生命周期行为 |
| U-05 | Worker、取消、可见页虚拟化，保留缩放/旋转/选择/搜索/打印 |
| V-02 | 缓存预算/资源释放、压力 fixture、耗时与峰值内存基线 |
| V-03 | 四后端/浏览器/corpus/视觉/差距表 CI、固定 reference/依赖、资产来源许可 |
| R-03 | 后期 range/增量数据来源；依赖 reader 可消费分段数据，不只是 fetch Range |

## 文件边界与依赖

本模块维护 `cmd/browser/bridge.mbt`、`web/viewer.js`、`web/viewer.css`、
`web/index.html`、既有 `tools/*` 公共 runner、`tools/pixels/`、CI。
可新增 Worker、任务队列、缓存/生命周期和模块专用实现文件。
根公共模型/collector 和依赖配置由集成 Agent负责。

W2/W7 提供文字/ARIA/annotation 独立数据和 DOM 文件，本模块接入生命周期。
W3 提供可估算/受限的图片资源，字体缓存预算需和 W1 协调。
像素后端/Worker message 的序列化能力取决于 W5，不能擅自移动公共模型。
先规定 document generation/task id 与取消/过期结果行为，再接入 Worker。

## 推荐切片

先处理稳定的生命周期、缓存/虚拟化与过期结果丢弃，再移 Worker。
用户快速重开文件、缩放或旋转时，旧任务不能覆盖新文档。
卸载可见页面不能破坏跨页选择来源、搜索定位和打印路径。
range 与 XFA 属后期，不因为一个网络适配器存在就勾选 R-03。

## 验证与交付

保留现有 33 项 Chromium 检查，扩大重复打开/close、快速缩放/旋转、
取消、Worker error、缓存淘汰、长文档滚动、selection 恢复/全选、search 和 print。
压力基线记录文件 hash、页数/资源规模、冷/热缓存、耗时和峰值内存，
性能进步不能以漏画/不完整文字为代价。

各模块维护自己的视觉 manifest，本模块合并公共清单/runner。CI 需要实际
安装/构建固定 PDF.js 和 Chromium、运行有界真实样本并保留失败报告，
不能把退出成功的普通测量模式当成像素一致的门槛。
当前公共清单有大量已知差异，CI 先区分测量失败、已知差异和新回归；
`--strict` 可用于已经证实匹配的切片，不要求把整份已知差异清单伪装成通过。
新自动化只用 `.mbtx`，dev server 保持 4312 并向 Lody 报告预览。

交付生命周期/调度 API、浏览器回归、性能数字、CI 执行证据及仍同步的阶段。
集成 Agent集中更新 TODO/validation，避免多人覆盖统计。
