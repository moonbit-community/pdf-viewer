# 生态复用候选与接入边界

核查日期：2026-10-10。先复用/验证现成 MoonBit 包，再决定需要补的分支。
本文件从图像解码扩展到字体、文字、绘制、色彩和宿主；对应
[TODO 的复用表](TODO.md#先复用再补-pdf-适配) 与各工作模块。
核查包括 registry/上游文档、下载源码及公开 API；A1 已固定接入 Unicode 库，
字体候选的实测限制见下文。没有把包的自述测试数量当作本项目的测试/视觉证据。pdflite 是已经集成的依赖，
其尚未被 viewer 使用的写入 API 也不能记为编辑功能完成。

## 核查状态与选择规则

- **已有依赖**：优先使用 pdflite、async、x 和 viewer 已有实现，避免同一项目出现两套 reader、色彩或采样逻辑。
- **文档候选**：确认包/接口存在，还没有验证源码、编译或项目样本。
- **源码/API 已核查**：记录所需入口和已知限制，仍需最小接入验证；不是已选定依赖。
- **可接入**：所需目标编译、真实 fixture、输出约定和性能验证通过后再决定，并把版本固定到依赖配置。

候选不够用时，先评估扩展现有库或薄绑定，再记录需要自研的具体分支。
不为验证一种底层能力引入整套 GUI/应用框架。native C FFI 与额外 Wasm 模块分别
验证构建/部署，不能默认等价于本项目的 wasm、wasm-gc、js、native 四后端支持。

## JPEG

| 包 | 核查版本与许可 | 已核查能力 | 本项目仍需验证 |
| --- | --- | --- | --- |
| [mizchi/image](https://mooncakes.io/docs/mizchi/image@0.4.3) | 0.4.3，Apache-2.0 | 纯 MoonBit baseline JPEG 解码，Gray/3-component，输出 RGBA8 `ImageData`；文档列出 js/native/wasm-gc | 真实 PDF 像素、采样/舍入、restart、性能、wasm 目标；无 progressive/4-component CMYK 支持，PDF ColorTransform/Decode 不能假定已处理 |
| [walkzzz/image](https://mooncakes.io/docs/walkzzz/image@0.5.0) | 0.5.0，MIT | 纯 MoonBit baseline JPEG、灰度/YCbCr、4:4:4/4:2:2/4:2:0，声明四后端可用，公开 `decode_jpeg_pure` | 同样需真实像素/性能验证；源码明确不支持 progressive/CMYK/arithmetic coding；PDF 的原始组件与颜色语义不等同于普通图像 RGB 解码 |
| [shunge/image](https://mooncakes.io/docs/shunge/image@0.1.4) | registry 0.1.4，MIT | registry 声明纯 MoonBit JPEG 解码 | 仅登记，尚未核查源码、具体编码覆盖和 API；不作为已选定依赖 |

`mizchi/image` 的 README 写明 baseline only；`src/jpeg_decode.mbt` 的 SOF0
分支只允许 1/3 个组件。`walkzzz/image` 的
`src/pure/codec/jpeg_decode.mbt` 文件头和公开函数说明明确列出 progressive、
CMYK 与 arithmetic coding 不支持。不能把“支持 JPEG”概括为完整 PDF JPEG 覆盖。

已运行的核查命令：

```bash
moon fetch mizchi/image
moon fetch walkzzz/image
```

在下载后的 `mizchi/image/0.4.3/src` 内：

```bash
moon ide doc 'decode_jpeg' 'ImageData'
```

确认 `decode_jpeg(Bytes) -> ImageData raise DecodeError`，`ImageData` 的
`width`、`height`、`data : Bytes` 与 README 的 RGBA8 约定。
在 `walkzzz/image/0.5.0/src/pure/codec` 内：

```bash
moon ide doc 'decode_jpeg_pure'
```

确认该 API 属于 `walkzzz/image/src/pure/codec`，返回 `@types.Image`。
源码暂存于被忽略的 `.repos/`，原始候选源码不修改。

## JPEG2000 / JPX

[trkbt10/jpeg2000](https://mooncakes.io/docs/trkbt10/jpeg2000@0.2.0)，
0.2.0，Apache-2.0；[上游源码](https://github.com/trkbt10/jpeg2000_mbt)。
已下载源码，核对 `src/decode.mbt`、`types.mbt` 和内部 decoder API：

- 公开 `decode(Bytes) -> ImageData raise DecodeError`，返回尺寸、组件数量、位深、符号和 bytes。
- 输入提取器接受 raw codestream，也会提取 JP2 的 `jp2c`；这不代表 JP2 色彩/alpha box 已被完整解释。
- 当前根入口调用的 `decode_samples` 有 `component0:raster:le` 输出路径；根 `ImageData` 不保留 `sample_layout`。
  内部另有 all-components 接口，但属于 `internal` package，不能把它当作本项目可稳定导入的公共 API。

因此不能直接将 `data` 当作 RGB/RGBA。I-01 先用灰度和彩色 JPX fixture 验证，
优先向现有库扩展公共多组件/布局 API；再核对组件采样、MCT、signed/位深、
JP2 colour/alpha、PDF `/SMaskInData`、支持的编码 profile、目标和内存限制。
只确认包存在或只有 component0 输出时不勾选 I-01，不预设要从零实现整个 JPEG2000。

## JBIG2

尚未确认可直接接入的 MoonBit decoder。下一步继续查 Mooncakes/上游实现，
并比较成熟解码器的绑定、移植或公共 API 扩展；只安排确定缺失的分支。
[jbig2dec](https://github.com/ArtifexSoftware/jbig2dec) 可作为能力/接口比较对象，
但其[许可为 AGPL-3.0-or-later](https://github.com/ArtifexSoftware/jbig2dec/blob/master/LICENSE)，
本项目尚未选用。需分别核对 globals/page stream、segment、Mask、资源限额、许可与交付目标，
不能把 native decoder 存在写成浏览器 MoonBit 解码已解决。

## 字体与 Unicode

| 包 | 版本/许可与核查状态 | 可复用能力 | 本项目的适配与限制 |
| --- | --- | --- | --- |
| [mizchi/font](https://mooncakes.io/docs/mizchi/font@0.7.4) | 0.7.4，Apache-2.0；已固定接入独立 cmap/post 接口，四后端回归通过；完整字体解析仍为 probe | `parse_cmap(BinaryReader, Int)` 支持 0/4/6/12；`parse_post(BinaryReader, Int, Int)` 读取字形名；`parse_font(Bytes)`、按 GID 取轮廓/metrics | cmap/post 前加 PDF 选表、字形名优先级、边界/展开限额和缓存；完整 parser 的缺 cmap/裸 Type 1、复合轮廓限制仍需保留现有恢复分支 |
| [moonbit-community/bidi](https://mooncakes.io/docs/moonbit-community/bidi@0.5.2) | 0.5.2，Apache-2.0；已固定接入，四后端回归通过 | UAX #9 的 `process`、levels 和 `reorder` 字符置换 | code point→glyph item 映射核对几何和内容流顺序；不直接改绘制文本；复杂 inverse bidi、表格和旋转布局仍有限制 |
| [moonbit-community/normalization](https://mooncakes.io/docs/moonbit-community/normalization@0.5.2) / [ucd](https://mooncakes.io/docs/moonbit-community/ucd@0.5.2) | 均为 0.5.2，Apache-2.0；已固定接入，四后端回归通过 | Unicode 16 NFKD、大小写映射和字符分类 | 分解/兼容展开/组合符号重排保留原文 UTF-16 来源；搜索策略额外折叠 ß、æ、œ，不承诺完整 locale/case-fold 语义；不改原文或 glyph 编码 |
| [moonbit-community/flate](https://mooncakes.io/docs/moonbit-community/flate@0.8.1) | 0.8.1，Apache-2.0；pdflite 已使用同版本，现固定为直接依赖；四后端回归通过 | zlib 流式校验、带输出上限的 raw DEFLATE 解码 | 字体/CMap 的完整流仅在 Adler-32 不匹配时恢复；单层 Flate、无变换 predictor，4 MiB 输入/16 MiB 恢复输出上限；保留严格解码和源对象，不增加另一套解压器 |

`mizchi/font` 的 `parse_font` 识别 sfnt/WOFF/TTC 等封装；当前 parser 还要求
`head/maxp/hhea/hmtx/cmap` 等表。PDF 子集字体可能缺表，裸 CFF 也不具有这些表，
需要 fixture 证明可用，或扩展库的输入接口，而不是直接删除现有解析器。
调用按 GID 的入口，不用 ToUnicode/`char_outline` 替代 PDF 的 CIDToGIDMap，
也不用通用文字 layout 改写 PDF 已规定的字距与位置。

可单独使用的 `parse_cmap` 不要求完整 sfnt。viewer 选定一个有效 subtable 后，
用库接受的 Unicode record header 调用该接口，原平台/encoding ID 仍用于 PDF
和 MacRoman 语义。库的 BinaryReader 不检查边界，因此先验证格式 0/4/6/12
的所有读取范围、段/组顺序和展开量；signed remainder 归一到 16 位，
glyph ID 再与 maxp 核对。无可用表沿用恢复路径；有效表中的缺字先尝试 post，
无法恢复时保留 GID 0。
缓存只保留 cmap，最多 8 项、1 MiB 源数据、262144 映射；单个 format 12
最多展开 131072 个码位，超出时该表不可用。format 2 的 subHeaderKeys、相对 glyph
offset、delta 和别名先验证，再转成 format 12 交给同一库解码；原平台语义保留。
罕见的 8/10/13 等表不在当前适配范围，仍走已记录的 post/缺表恢复路径。

独立 `parse_post` 用于 version 2 字形名；version 1 转为等价标准索引，复用库的
Macintosh 字形名表。version 2.5 的 signed offset 转为同一套索引并验证边界；
version 3 合法地不提供字形名，厂商格式不在当前适配范围。
先验证 maxp 数量、索引与 Pascal 字符串范围；缓存最多 8 项、1 MiB 源数据和
131072 个名称。Windows/Symbol cmap 的有效映射优先，Unicode 平台 cmap
优先显式 Encoding/Differences 名称；未知名称且无可用 post 时允许显式
ToUnicode 恢复。字形名到 Unicode 仍用 pdflite；不另抄 Adobe/Mac 名称表。

字体流恢复也复用现有 Flate 引擎：先保留 pdflite 严格解码，失败后用库区分
`ChecksumMismatch` 与其它错误，再用同库的有上限 raw 解码取得完整正文。
`issue13316_reduced.pdf` 的字体与 ToUnicode 都属于校验和不匹配，已恢复中文
绘制、提取及嵌入资源；filter chain、变换 predictor、缺失 trailer 等保持严格失败，
回归明确核对这些分支不会误用只忽略校验和的恢复。流和已知字体字段的 alias
循环在进入依赖之前停止，字体字典/编码/metrics 的修复只使用本地 shadow。
`tools/font_stream_probe.mbtx` 分别记录严格 PDF 解码和 zlib 的错误种类，避免
单个损坏字体掩盖其它 stream。验证与剩余像素差异见 [A1 验证](validation.md#font-stream-checksum-recovery)。

`bidi.reorder_string` 输出视觉顺序且会做镜像；不能直接拿它作为逻辑复制文本，
也不能重复重排已由 PDF 定位的字形。A1 使用置换与 Unicode 分类，
结合来源和几何验证混合方向、surrogate 与 ligature，覆盖 embedding/isolate 和零宽
控制符；旋转、剪切与短表格使用同一来源顺序。歧义未标记结构仍需保留内容顺序。

`tools/font_inventory.mbtx` 提取原始嵌入程序，`tools/font_library_probe.mbtx`
使用按 GID 的公开接口，不改字体 bytes。实测 `issue14462_reduced.pdf` 的 PFB Type 1
和 `ArabicCIDTrueType.pdf`、`TrueType_without_cmap.pdf` 的缺 cmap 子集均返回 None。
自制 6-glyph sfnt 的 GID/advance 可读，但后三个复合轮廓的 bounds 与预期不同；
数据和运行方式见 [A1 验证](validation.md#a1-fonts-unicode-and-reading-order)。这组结果
只覆盖所列输入，不能概括为字体库的所有输入都不可用。

## 绘制与合成

| 候选 | 核查状态 | 优先用途 | 不可直接假定的能力 |
| --- | --- | --- | --- |
| 浏览器 SVG / Canvas 2D | 现有 SVG 已由浏览器绘制；Canvas 尚未接入 | 路径、变换、clip、图像、基础 blend 与 surface；宿主 JS 可直接用 API | PDF 路径中途 CTM、non-isolated/knockout、overprint、soft-mask BC/TR；需逐项真实对照 |
| [mizchi/svg](https://mooncakes.io/docs/mizchi/svg@0.2.3) | 0.2.3；上游文档/API 已核查 | `PathCommand`、Transform、低层 raster primitives、CPU SVG 渲染与 mask/clip 等能力 | 上游记录仍有 SVG WPT 缺口；不是完整 PDF compositor，也不自动解决提前序列化时丢失的 PDF 状态 |
| [bobzhang/vg](https://mooncakes.io/docs/bobzhang/vg@0.3.0) / [上游 vg](https://github.com/moonbit-community/vg) | registry 0.3.0 与上游 main 绘制源码已核查；发布版差异待验证 | 向量命令、路径/paint 与 SVG/Canvas 输出适配候选 | 上游 `draw.mbt` 的部分描边/混合输出采用近似；需先验证，不能直接承诺精确 CTM 或全部 PDF blend |
| [klaseca/skia-sys](https://mooncakes.io/docs/klaseca/skia-sys@0.1.1) | 0.1.1；上游文档/API 已核查 | native Skia 绘制/混合绑定候选；应用层优先核查同项目高层封装 | 包不携带 native artifacts，需兼容 mono/skia 头文件、`libSkiaSharp` 与构建 hook；不是现成 js/wasm 后端 |

W5/W6 先让候选重放一组 CTM、clip、blend、group、pattern、mesh fixture，
记录哪些 primitive 可以直接用，再决定后端和局部补充。结构化路径、原始色彩、
资源和作用域由 PDF 适配层保留；只把已有 SVG 字符串送入另一个 renderer 无法补回这些信息。
通用曲线光栅化、blend 公式、渐变/三角插值不默认自研；PDF group/patch 等缺口单列。

## ICC 与颜色

[enanandesu/icc](https://mooncakes.io/docs/enanandesu/icc@0.1.1)，0.1.1，Apache-2.0，
已下载源码：`parse_from_bytes(Bytes) -> Map[String, String] raise ParseError`。
它读取 profile 的元数据，未提供 profile→profile 像素转换/LUT 引擎。
可评估用于 profile 诊断；根 package 还导入 fs，浏览器目标仍需验证。
**不能以这个包存在为依据勾选 C-01。**

[LittleCMS](https://github.com/mm2/Little-CMS) 是已有的 ICC 转换引擎（MIT，C 实现）。
W4 优先评估 native 薄绑定与浏览器额外 Wasm 模块的成本和输出差异，
目前未确认或接入 MoonBit 四后端通用绑定。ICCBased 的 Range/alternate、
PDF 色彩状态与资源缓存仍需 viewer 适配；专色/overprint 不等同于 ICC 转 RGB。

## XML、宿主与完整阅读器

| 复用对象 | 核查状态 | 对应工作 |
| --- | --- | --- |
| [moonbit-community/XMLParser](https://mooncakes.io/docs/moonbit-community/XMLParser@0.2.5) | 历史候选 0.2.5，Apache-2.0 | 未采用：单独 XML parser 不覆盖 XFA binder/paginator；本轮改为直接复用完整纯 XFA 组件 |
| PDF.js 纯 XFA 组件 | 固定 `89b500f5e1d98ed89bb90211e45b28730b2d99ac`，36 个未修改模块及 Apache-2.0 许可；[来源与 SHA](../vendor/xfa/UPSTREAM.json) | 已接入 XML/template/data binding/pagination/XfaLayer；pdflite 保持 PDF reader，字体复用既有程序/metrics，控件锁为只读，无文档脚本/编辑；[验收](readonly-completion.md#dynamic-xfa) |
| [mizchi/js_web](https://mooncakes.io/docs/mizchi/js_web@0.13.1) | 0.13.1；上游文档/API 已核查 | Worker/MessagePort、Fetch/Streams 等 JS 绑定候选；已有宿主 JS 可直接用浏览器 API，无需为此强制加包 |
| pdflite 0.2.2（已有依赖） | 本地 `pkg.generated.mbti` 已核查 | reader/CMap/AFM/structure tree、批注模型；`pdf_write_document` 和增量 writer 可用于后续编辑保存，不另写 serializer |
| 既有 Chromium/MoonBit/视觉 runner | 已有主路径，验证见 [validation.md](validation.md) | V-03 复用 runner 接 CI；不用为扩大 fixture 重建测试框架 |

原生 DOM 的 input/select、Pointer Events、Canvas、ARIA、IntersectionObserver
分别承担表单输入、笔迹/命中、宿主绘制、可访问性和可见页检测。
项目负责 PDF 字段/批注语义、来源映射、任务代次、缓存预算与保存重开。
writer 可写对象和批注不等于已经有表单编辑器或数字签名；后续路线见
[完整阅读器接入](TODO.md#完整阅读器的后续接入)。

本轮新增的源码下载命令（只下载到忽略的 `.repos/`，未改变依赖配置）：

```bash
moon fetch --no-update moonbit-community/bidi@0.5.2
moon fetch --no-update mizchi/font@0.7.4
moon fetch --no-update trkbt10/jpeg2000@0.2.0
moon fetch --no-update enanandesu/icc@0.1.1
```

## 图像解码的下一步

先用独立临时 probe/fixture 核对现成 JPEG API，比较固定 PDF.js 像素、
decoder 的输出和分配/耗时，尤其 `issue13931.pdf` 的 JPEG + SMask + Matte。
选择合适依赖后，viewer 只做解码适配和 PDF image 的 `/Decode`、colour-key、
父 colour space、SMask/Matte 合成；不能对库已经转为 RGB 的像素错误地再按
CMYK/YCbCr 原始组件处理。

progressive/CMYK/ColorTransform 或原始组件 API 若不够用，再检索其他候选并
评估扩展现成库；只有确认不可复用的具体分支才安排自研。
未完成 JPEG parser 草稿保持暂停，不能成为默认实现路线。
