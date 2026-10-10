# 多 Agent 协作拆分

更新日期：2026-10-10。范围和验收规则沿用 [TODO.md](TODO.md)。
这里把 **33 个剩余 TODO 分成 8 个工作模块**；不新增或勾选 TODO，
不改变原有 50/17/33 的统计。每个模块有一份可直接交给 Agent 的任务说明。

本次已由两个 Agent 完成只读的字体/文字、渲染/宿主边界审计；
功能实现任务尚未分发。拆分后四个后端分别通过 221/221 测试，
33 个剩余 ID 已核对全部覆盖且无重复归属，详见 [validation.md](validation.md#parallel-work-baseline)。

这些是工作边界，还不是 8 个已隔离的 MoonBit package。
当前多数实现位于同一个根 package，文件之间共享私有函数；
`pdf-viewer.mbt` 的模型/内容收集器和 `svg.mbt` 的输出入口仍有多方依赖。
可以并行验证候选依赖、实现 PDF 适配和回归，共用入口由集成 Agent 顺序接入。

最终产品目标包含批注编辑、表单填写和签名；本次 8 个模块对应的是只读基线的
33 个剩余项。后续编辑/保存接入见 [TODO](TODO.md#完整阅读器的后续接入)，不混入当前计数。

## 复用优先的交付约定

每个模块的第一份交付先给出依赖核查/最小接入结果，再决定需要自研的分支。
逐项映射见 [TODO 复用表](TODO.md#先复用再补-pdf-适配)，版本和源码/API 限制见
[生态复用候选](codec-candidates.md)。不把模块名解释成要从零写字体库、codec、
Unicode 算法、rasterizer 或 ICC 引擎。

最小验证记录输入/输出与公共 API、所需目标、真实 fixture、耗时/内存和已知差异。
有候选但未跑验证记为“待验证”；内部接口或编码分支不够用时，先比较扩展现有库
和绑定成本，再把具体缺口交给集成 Agent 记录。PDF 资源、状态、来源索引和恢复
语义仍由本项目适配；通用算法通过回归后逐步复用，不一次删除已工作的路径。

## 模块清单

| 模块 | 剩余 TODO | 项数 | 主要产出 | 任务说明 |
| --- | --- | ---: | --- | --- |
| W1 字体、编码与 reader 恢复 | R-02、F-03、F-05、F-06、F-07、T-04 | 6 | 字体/CMap/损坏文档恢复和可定位的诊断 | [W1](workstreams/01-fonts-reader.md) |
| W2 文字语义与可访问性 | T-01、T-02、X-01、X-02 | 4 | 阅读顺序、字符来源映射、结构树/ARIA、后续只读 XFA | [W2](workstreams/02-text-accessibility.md) |
| W3 图片解码与图像遮罩 | I-01、I-02、I-04 | 3 | JPEG/JPX/JBIG2 像素、image mask/Matte、采样 | [W3](workstreams/03-images.md) |
| W4 色彩管理 | C-01、C-03 | 2 | ICC、CMYK、专色/domain/overprint | [W4](workstreams/04-colour.md) |
| W5 路径几何与绘制后端 | G-01、G-02、G-03 | 3 | 完整 CTM 描边、精确路径/clip、像素绘制基础 | [W5](workstreams/05-geometry-renderer.md) |
| W6 透明合成与 pattern/shading | M-01、M-02、M-03、H-01、H-02、H-03 | 6 | group/backdrop/knockout、blend、soft mask、pattern/mesh | [W6](workstreams/06-compositing-patterns.md) |
| W7 批注与只读表单 | A-01、A-02、A-03、A-04 | 4 | 批注外观、字段排版、popup/link 交互层 | [W7](workstreams/07-annotations-forms.md) |
| W8 宿主调度与工程验证 | R-03、P-02、U-05、V-02、V-03 | 5 | 生命周期、Worker/取消/虚拟化、增量读取、压力基线/CI | [W8](workstreams/08-host-validation.md) |

W1 与 W2 必须共用字体/CID/GID/byte-span 和诊断约定；
W5 与 W6 必须共用绘制命令、像素 buffer、clip/group 作用域。
W7 的 DOM 层依赖 W8 的页面挂载/释放，XFA 和 range 读取放在后期。
它们不能同时各自改造整个主路径。

## 推荐并发安排

当前会话可同时运行 4 个 Agent，因此使用 **1 个集成 Agent + 3 个实现 Agent**。
8 个模块是任务队列，不代表立即启动 8 个实现 Agent。

| 阶段 | 三条可并行的工作线 | 集成 Agent 的职责 |
| --- | --- | --- |
| 第一轮 | W1 验证 `mizchi/font` 按 GID 轮廓/真实缺字；W2 验证 `bidi` 字符→来源映射；W3 验证现成 JPEG 解码的 SMask/Matte | 固定候选数据约定，接入通过验证的适配，复跑对应真实样本 |
| 第二轮 | W5/W6 联合比较 Canvas/绘图库的 CTM/clip/blend；W4 评估 ICC 引擎与目标适配；W8 用宿主 API 做生命周期/页面调度 | 确定共用绘制后端、buffer/颜色/alpha 和目标；顺序接入 collector/bridge |
| 第三轮 | W3 验证/扩展 JPX 公共多组件 API并评估 JBIG2；W7 的只读表单/批注；W1/W4 的剩余真实覆盖 | 用选定依赖接入图像、颜色和 annotation DOM，明确仍需补的 PDF 语义 |
| 第四轮 | W6 适配 group/soft mask/pattern/patch；W2 完善多栏/ARIA；W8 扩大性能/CI | 合成器/几何/色彩联合验证；通用算法只实现核查后的缺口 |
| 后续 | 扩大 reader/font corpus、网络 range、XFA、性能压力与 CI | 按依赖安排，不把高工作量项目当作短任务一次完成 |

首轮先用独立 probe/fixture 验证依赖，避免先扩大自己的 parser/raster 算法。
W4 的 overprint 依赖 W6，不能与 ICC 转换一起宣布整项完成；W6 先验证
后端已提供的合成 primitive，页面像素接入仍需要 W5 的结构化绘制基础。
每轮只登记实际运行的任务，不把这张建议表当成已经分配或完成的工作。

## 文件负责人和集成边界

| 文件/区域 | 默认负责人 | 协作方式 |
| --- | --- | --- |
| `pdf-viewer.mbt`、`page_model.mbt`、`svg.mbt`、`text_layout.mbt`、`text_clipping.mbt` | 集成 Agent | 模块 Agent 给出需要修改的函数/字段与局部补丁，由集成 Agent 串行接入；不要多人同时编辑这些入口 |
| `cmd/browser/bridge.mbt`、`web/viewer.js`、`web/viewer.css`、`web/index.html` | W8 | W2/W7 提供数据与独立 DOM/helper 文件，W8 接入页面生命周期和事件 |
| `image_colour.mbt`、`images.mbt`、`image_alpha.mbt`、`image_sampling.mbt` | W3 | W4 提供色彩转换实现；W6 提供 Form/group 合成；两者不分别重写图片路径 |
| `colour.mbt`、新增 ICC 引擎适配/专色语义 | W4 | 提供共享转换函数，W3/W6 调用；改变返回值语义时先同步消费者 |
| `masks.mbt`、`patterns.mbt`、`mesh.mbt` | W6 | 图像 payload/采样由 W3 提供，几何/像素后端由 W5 提供 |
| `text_order.mbt`、`text_layer.mbt`、`search.mbt` | W2 | 来源数据接入由集成 Agent 协调 W1；浏览器入口由 W8 接入 |
| `annotations.mbt`、`annotations_svg.mbt` | W7 | 字体布局复用 W1/W2，AP collector/renderer 入口经集成 Agent 接入 |
| `moon.mod`、根/既有 `moon.pkg`、既有 `pkg.generated.mbti` | 集成 Agent | 依赖/导入集中修改；接口文件通过 `moon info` 生成，禁止手改 |
| `docs/TODO.md`、`docs/validation.md`、`docs/architecture.md` | 集成 Agent | 模块结果写入自己的任务说明，主文档集中合并并核对统计 |
| `tools/visual_cases.json`、既有 browser/visual runner、`tools/pixels/`、CI | W8 | 每个模块可新增自己的 fixture manifest 和 `.mbtx` 诊断；公共 runner/清单由 W8 合并 |
| 模块内专用测试/任务说明 | 对应模块 Agent | 新测试按特性分文件；大型 `pdf-viewer_*test.mbt` 的共同 fixture/旧断言由集成 Agent 修改 |

W1 的专用文件清单见其任务说明；W5 优先新增候选后端适配/几何状态文件，
再由集成 Agent 修改既有入口。以上默认负责人可按一轮实际任务交接，
但每个共享文件在同一时间只有一个写入者。
协调是 Agent 之间交接，不要求用户逐次批准普通实现选择。

## 共同数据约定

- 页面模型使用 PDF-space 坐标；旋转、缩放、UserUnit/device pixel 换算集中由 viewport/后端处理，避免重复缩放。
- `PdfPageItem` 的稳定源 index 与逻辑阅读顺序分离；同一页面模型内排序/bidi 不能重编号，缩放/旋转后保留来源。切换 OCG 配置或重建文档需要重新解析来源，不承诺跨配置 index 不变。文字 API 的 UTF-16 范围必须保留来源映射，不拆 surrogate pair。
- 字体 charcode、CID、GID 和 Unicode 是不同信息；不能用 ToUnicode 代替 glyph CID。缺失字段需有明确未知状态，不编造原始 byte span。
- 区分字符串 operand 内 byte span、解压后的 stream offset 和原始文件 offset；pdflite 会解码/拼接内容流，不能从现有 glyph 反推原文件偏移。tagged 来源键至少带页、stream/Form 身份与调用实例，MCID 不能单独作为唯一键。
- `PdfPageModel`/`PdfTextItem` 等是宿主可构造的公开 record；来源/诊断优先评估新增 sidecar/API，直接增加必填字段须由集成 Agent统一处理现有宿主和 fixture。
- 原始图片样本、色彩转换与 alpha/Matte 合成分阶段；已集成 alpha 的图片不能再被 SVG/像素后端应用同一遮罩。image SMask 与 ExtGState/Form soft mask 分属 W3/W6。
- 色彩转换输出的空间、数值范围、alpha 是否预乘由 W4/W5/W6 在接入前统一记录。不能把现有 RGB hex 字符串当成完整的 ICC/overprint 或线性合成数据。
- 新像素后端必须明确 buffer 的格式、stride、alpha 约定与 clip/group 作用域；W5/W6 先统一这些接口，再接入复杂合成。
- 库能力保持 MoonBit 主路径，宿主 JS 负责浏览器布局/事件/调度。PDF.js 只用于对照，不能成为 viewer 的实际渲染器。
- 不修改 `reference/pdf.js`、`.mooncakes` 依赖或 `office.mbt`，不接入 OpenSeek；资产需记录来源和许可。
- 字体、Unicode、codec、色彩引擎和基础绘制先检索已有依赖/Mooncakes/成熟库并验证覆盖；可复用时优先适配现成实现，只对确认的缺口安排自研。候选见 [codec-candidates.md](codec-candidates.md)。
- Worker/网络/可见页检测/输入控件优先用浏览器 API；不为一个 primitive 引入整套 GUI。native FFI/额外 Wasm 模块须明确目标和构建成本，不记成四后端通用能力。

这些是必须共同维持的行为约定，并未声称新 API/后端已经存在。
具体新增接口由负责模块提出，集成 Agent 核对消费者后落实到代码与 `.mbti`。

## 基线、工作区与验证

最初拆分时的历史基线是 `a2d155e` 加未提交修改；2026-10-10 生态复用核查开始时
HEAD 已为 `fac0e2c`，工作区干净。启动实现时重新记录 HEAD 和 tracked/untracked
状态，不沿用旧的“当前 HEAD”描述；存在未提交能力时，单从 HEAD 创建 worktree 会遗漏它们。

可以先在同一个工作区按上面的文件负责人规则协作；需要隔离 worktree 时，
集成 Agent 先保存包含 tracked/untracked 文件的完整基线快照并记录来源，
每个 Agent 从同一快照开始。禁止用 reset/clean/stash 覆盖他人的未提交工作。
不要顺手提交或推送，提交作者及 `feat:`/`fix:` 等前缀沿用项目已有要求。

刚开始编写的 JPEG 解析器暂存于
[`drafts/jpeg-parser.mbt.txt`](drafts/jpeg-parser.mbt.txt)。它缺少 scan decoder、
IDCT、像素展开、测试和 image adapter，**未编译、未接入、未验证**。
W3 先验证生态 codec，草稿仅作缺口参考，不恢复为默认自研路线；草稿不计入完成度。暂存后 `moon check --target all`
通过，保留 24 条既有 warnings。

每个模块交付：改动文件、TODO 子范围、测试命令和结果、真实对照样本/报告、
剩余差异、需要共享入口接入的补丁。算法/测试写完但未接入主路径，状态记为
“待集成”；未跑真实像素对照时明确写“尚无视觉证据”。

在同一个工作目录内，由一个 Agent 依次运行 MoonBit 构建/测试；
多个 `moon test` 会争用 `_build/.moon-lock`，并不能真正并行。
各自拥有独立工作树/构建目录时才可以独立验证。
模块先运行有意义的窄测试，集成后执行：

```bash
moon info
moon fmt
moon test --target wasm
moon test --target wasm-gc
moon test --target js
moon test --target native
moon check --target all
git diff --check
```

涉及视觉的改动还须运行该模块的 PDF.js 对照；W8 合并公共清单后跑统一基线
和浏览器交互回归。真实差异不能被扩大容差、跳过文件或空白输出隐藏。
文档拆分本身不代表新增渲染能力，完成度仍由 TODO 验收条件决定。

## 交给 Agent 的公共提示

> 只在本仓库根目录及其子目录内工作。先读 `AGENTS.md`、
> `docs/TODO.md`、`docs/PARALLEL.md` 和本模块任务说明，再遵循 MoonBit skills。
> 先核查 `docs/codec-candidates.md` 的相关候选，提交最小接入验证与具体缺口，
> 优先复用已有依赖/生态库/宿主 API，不能默认从零编写通用算法。
> 只实现本轮明确分配的切片，维持约定的公共模型和来源索引。
> 在自己的文件内实现并添加必要回归；共享入口交给集成 Agent 串行接入。
> 不修改上游/依赖，不接入 OpenSeek，不提交或推送。
> 自动化只用 `.mbtx`。报告实际完成、验证证据、剩余限制及集成补丁。

集成 Agent 负责在启动时补上本轮切片、文件交接和基线说明；
不要仅发送“把 W1/W6 全部完成”就让多个 Agent同时改整个 collector。
