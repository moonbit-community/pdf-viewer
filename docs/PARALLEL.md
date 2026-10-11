# PDF 内核的两条工作线

当前只分两条主线，分别交给两个 Agent；都在现有仓库和根 package 内工作。

| 主线 | 目标 | 任务说明 |
| --- | --- | --- |
| A1 字体与文字 | 字体/CMap 恢复、字形与定位、阅读顺序、搜索和选择的来源映射 | [A1 任务](workstreams/core-text.md) |
| A2 图形与图像 | 图片解码、颜色转换、路径/裁剪、透明合成、pattern/shading 与绘制后端 | [A2 任务](workstreams/core-graphics.md) |

两边各自完成实现、接入和回归。A1 主路径已验收；浏览器 Worker、调度和只读批注/链接交互
及可访问 DOM 已在宿主、批注和可访问性专用文件接通，批注/表单编辑留在后续；
完整阅读器的最终目标仍以 [TODO.md](TODO.md) 为准。

## 文件边界

为减少同时修改主文件，已把字体资源、Type 3 字形、SVG 文字输出和文字选择
原样移到 `font_resources.mbt`、`type3_outline.mbt`、`svg_text.mbt`、
`text_selection.mbt`。它们仍属于根 package，函数名、可见性与调用方式不变。

- A1 修改字体、CMap、CID、reader 恢复及 `text_*`、`search.mbt`，包括上述四个专用文件。
- A2 修改 `pdf-viewer.mbt`、`svg.mbt`、`page_model.mbt`，以及图片、颜色、遮罩、pattern、mesh 和新增绘制后端文件。
- 新测试、fixture 清单和诊断工具分别放到各自主线的专用文件，避免同时改已有大型测试或公共 runner。
- `moon.mod`、`moon.pkg` 和已有公共测试/工具需要改时，两人直接交接，顺序修改。接口文件用 `moon info` 生成。

公共模型和内容收集器仍在 `pdf-viewer.mbt`。A1 若需要补来源数据或调整调用，
把具体字段/函数需求交给 A2 修改；A1 自己完成文字适配。绘制后端调用 A1 的
字形/文字函数，函数签名有变化时两人同步消费者。这个边界减少文件冲突，
不会消除 PDF 文字与绘制之间的接口依赖。

## 共同约定

先读 `AGENTS.md`、本页、所分配的任务说明和 [生态候选](codec-candidates.md)。
字体、Unicode、codec、色彩引擎和基础绘制优先复用现成实现，再补 PDF 适配；
候选源码已核查不等于已接入或已验证。PDF.js 继续作为对照。

页面数据保持 PDF-space 坐标；文字的 charcode、CID、GID、Unicode 与来源 index
分别保留。bidi/排序不重编号，搜索范围保留 UTF-16 来源映射。
图片样本、颜色转换与 alpha/Matte 分阶段处理，遮罩只应用一次。
新增 buffer 明确格式、stride 和 alpha 是否预乘。

每条主线先跑相关测试和真实 PDF 对照，记录差异，再运行
`moon info && moon fmt`、`moon test`、`moon check --target all`
和 `git diff --check`。同一工作目录的 MoonBit 检查顺序执行，避免构建锁争用。
交付写清改动、接入路径、测试结果和剩余差异；仅完成 probe 不勾选 TODO。
自动化工具沿用 `.mbtx`，资产记录来源和许可。

旧的 `workstreams/01–08` 保留为专题资料，其多角色分工已被本页替代。
