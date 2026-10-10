# Mooncakes 图像解码候选

核查日期：2026-10-10。先复用/验证现成 MoonBit 包，再决定需要补的分支。
本次只检索 registry、下载源码和查询 API；没有给 viewer 增加依赖或接入 decoder，
没有把包的自述测试数量当作本项目的测试/视觉证据。

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

registry 还存在 [trkbt10/jpeg2000](https://mooncakes.io/docs/trkbt10/jpeg2000@0.2.0)，
0.2.0，Apache-2.0，描述为 T.800-2015 JPEG2000 decoder。
目前只确认包存在，尚未验证 JP2/J2K、PDF colour/alpha、目标和真实样本覆盖。
I-01 首先核查这个候选，不能预设必须从零实现，也不能仅凭包描述勾选。

## W3 的下一步

先用独立临时 probe/fixture 核对现成 JPEG API，比较固定 PDF.js 像素、
decoder 的输出和分配/耗时，尤其 `issue13931.pdf` 的 JPEG + SMask + Matte。
选择合适依赖后，viewer 只做解码适配和 PDF image 的 `/Decode`、colour-key、
父 colour space、SMask/Matte 合成；不能对库已经转为 RGB 的像素错误地再按
CMYK/YCbCr 原始组件处理。

progressive/CMYK/ColorTransform 或原始组件 API 若不够用，再检索其他候选并
评估扩展现成库；只有确认不可复用的具体分支才安排自研。
未完成 JPEG parser 草稿保持暂停，不能成为默认实现路线。
