# MoonSurface 初验工程说明

阶段：2026 年 11 月月度新项目，`0.1.0-alpha.1`。本文件是开发与核查材料，
不作为参赛者本人撰写的一页正式申报书，也不表示赛事主办方已经审核通过。

## 本阶段交付

| 范围 | 可检查的实现/证据 |
| --- | --- |
| 受检三角输入、半边连接、边界、点邻域 | `indexed.mbt`、`topology.mbt`、`inspect.mbt`；拒绝非法索引、几何退化和边/点非流形 |
| 内部/边界 split、合法内部 flip | `split.mbt`、`flip.mbt`；可恢复错误在修改前检查；原网格快照不变测试 |
| 原始 Loop 与预算 | `loop.mbt`、`refine.mbt`；边界/价数权重、同步旧点更新、逐层计数、独立输出 |
| 导出和重算法线 | `normals.mbt`；面积权重、极端尺度例子、未定义法线报错 |
| 两条完整流程 | `examples/local_edit` 与 `examples/loop_refine`，README 给出输入任务及实际输出 |
| 可用入口 | 公开库 API、独立外部模块、UTF-8 JSON 文件 CLI、错误退出和不覆盖文件策略 |
| 工程规则 | Apache-2.0、来源与 AI 声明、清楚的 Git 历史、check/build/test CI、可复现验证工具 |

核心计算由 MoonBit 完成。Python 是开发参考/消费者验证，Node 是文件宿主。
测试没有调用 Python 来替代产品中的 Loop 或编辑算法。

## 重现核查

在干净、完整 Git clone 中，使用 README 的固定工具链运行：

```sh
python tools/verify.py --target js
python tools/verify.py --target wasm-gc
python tools/verify.py --target native
git rev-list --count HEAD
git log --reverse --oneline
```

实际验证对象区分为当前提交的源码、`git archive` 干净副本、实际 `moon package`
ZIP 的解包副本。两个消费者模式都通过独立模块的公开导入；它们采用显式
workspace member 替换，**不能据此声称注册表发布或下载通过**。

验证工具生成 `artifacts/reference-*.json`、`consumer-*.json`、`verification-*.json`
及 `cli.json`。CI 四个任务上传报告；对应提交的成功运行见仓库 Actions。
初验本地/远端核实结果另记录于十一月目录的开发记录中。
`verify.py` 要求至少 10 次历史，完整历史由 `fetch-depth:0` 获取；
有效性由真实改动内容判断，不靠数量脚本替代。前十次提交分别形成工程、输入、
拓扑、审计、split、flip、Loop、预算、法线及可运行入口，没有空提交。

当前每后端 28 项 MoonBit 测试，参考验证 40 个正常任务、8 个拒绝任务和 3 个
错误注入检查。覆盖单三角、四面体、五价点、环带、固定种子扰动方格、多分量、
反向面、不同尺度、连续编辑和编辑后细分。两类消费者各 4 项；Node CLI 13 项。
测试数量是已执行范围说明，不代表覆盖率或任意输入正确性证明。

## 与整月计划的关系

初验计划要求的基础拓扑、split/flip、Loop、示例、CI 和十次有效提交已进入本阶段。
三个**整月预期场景**仍是局部编辑、Loop 平滑细分、受约束 QEM 简化。
前两个已有运行闭环，第三个仍是预期场景，不能演示为已经实现。

后续终验必须补齐：

- 受检内部 collapse、存活/删除编号语义、compact 映射。
- quadric、候选求解与回退、局部优先队列、边界锁定、停止原因及 QEM 场景。
- 固定 OpenMesh 外部对照、更长随机编辑、分档规模与内存/性能记录。
- 完整 API/文档冻结，Mooncakes 发布及无本地替换的确切版本安装验证。
- 参赛者本人核对理解并人工撰写一页申报书，确认十一月入口/日期后办理提交。

十一月官方日期尚未由旧页面得出；计划中的 11/22 是内部目标。
报名、群身份、正式申报、终验和实际发布分别记录，不合并成一个“完成”状态。
