# W2 文字语义与可访问性

TODO：T-01、T-02、X-01、X-02

状态：待分配实现切片。共同规则见 [PARALLEL.md](../PARALLEL.md)。

## 复用策略

Unicode UBA 优先接 `moonbit-community/bidi@0.5.2`，normalization 优先接
`moonbit-community/normalization@0.5.2`，不另写通用 Unicode 算法/数据表。
`bidi` indices 是 Char 索引，需要映射到 UTF-16 和源 glyph；视觉重排/镜像字符串
不能直接当作逻辑复制结果。PDF 几何阅读顺序、多栏和来源区间仍由本模块适配。
XFA 的 XML 部分先用 `moonbit-community/XMLParser`；ARIA 用 DOM 原生语义。
核查状态与限制见 [生态候选](../codec-candidates.md)。

## 负责范围

完善逻辑文字索引和来源映射，让复制、选择、搜索和可访问的 DOM 使用一致语义。
paint-order item index 已与 reading order 分离；这一约定必须保留。
当前来源是 item + UTF-16 范围，不宣称已有原始 PDF byte-span 或完整 bidi。

| TODO | 子任务与验收重点 |
| --- | --- |
| T-01 | Unicode bidi、混合方向、ligature/组合字符边界、词/行/多栏顺序；绘制顺序不改变 |
| T-02 | charcode/CID/GID、内容流/字符串原始 byte span、稳定 run 与选区回源 |
| X-01 | structure tree 与阅读顺序映射到 DOM/ARIA；覆盖实际辅助技术可消费的节点 |
| X-02 | 后期只读 XFA 解析/布局/文字；单独交付路径，无脚本或编辑能力 |

## 文件边界

本模块维护 `text_order.mbt`、`text_layer.mbt`、`search.mbt`、
文字范围/排序专用测试，并可新增来源索引、bidi 库适配、structure/XFA 实现文件。
PDF 字符切分与字体 lookup 由 W1 提供，不自行重写其 parser。
`pdf-viewer.mbt`、`page_model.mbt`、`text_layout.mbt` 的 source 字段接入
由集成 Agent处理；浏览器共用文件归 W8。

结构树 MCID/content-stream/marked-content 对应关系需要从 collector 保留，
仅调用既有 `struct_tree_json()` 不能完成 X-01：它返回 reader 的原始对象图，
不是已关联 glyph/DOM 的语义树。同一 Form 多次调用需区分实例，MCID 本身
不足以唯一定位来源。需要区分字符串内部、解压 stream 与原文件三个偏移空间；
现有 reader 解码/拼接后的 ops 无法直接给出原文件 byte-span。
XFA 涉及独立 XML/布局路径，是后期大任务，不作为顺便补充的 ARIA 改动。

## 推荐切片与依赖

先和 W1/集成 Agent落实来源数据约定，用混合方向/surrogate fixture 验证现成
bidi 的 levels/置换和 normalization-to-source 映射；再补 PDF 逻辑还原与多栏排序。
库适配可独立验证，最终必须进入
text content、selection、search 和 DOM，而不是多出一个未被使用的索引。
既有字距、纵排、隐藏 OCG、旋转与跨页选择应保留行为。
来源 sidecar/API 优先保留宿主可构造的公共 record 兼容性；未知 GID/原文件偏移
明确标记未知。同一模型缩放/旋转保持 index，跨 OCG 配置不能假设 index 不变。

## 验证与交付

回归混合 Arabic/Hebrew/Latin、组合字符、surrogate、ligature、逆序内容流、
表格/多栏、跨 item 搜索与反向选区；同一来源在缩放/旋转后仍可定位。
先跑 `text_order_wbtest.mbt`、`text_layer_*test.mbt` 和相关 selection/search
测试，再由 W8 接入 Chromium 鼠标/键盘/复制与 ARIA 回归。

交付稳定索引和来源映射的行为说明、未知来源的表达、真实文本对照和 DOM
接入补丁。视觉字形由 W1/W5 验证，不把提取文本一致当成视觉一致。
