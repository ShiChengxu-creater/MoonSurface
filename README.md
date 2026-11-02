# MoonSurface

[![validation](https://github.com/ShiChengxu-creater/MoonSurface/actions/workflows/ci.yml/badge.svg)](https://github.com/ShiChengxu-creater/MoonSurface/actions/workflows/ci.yml)

纯 MoonBit 的三角曲面处理库，供渲染器、模型工具与几何程序使用。
输入顶点/三角形数组，完成受检的拓扑编辑和平滑细分，再输出普通数组。
计算核心可在 native、JS、wasm-gc 运行，不依赖 Three.js 或 C++ 绑定。

**当前版本 `0.1.0-alpha.1`：十一月项目的初验开发里程碑。**
已实现拓扑、split/flip、原始 Loop 权重和两条完整示例流程。
collapse、压缩映射、QEM 和第三个简化场景属于后续阶段，当前没有这些 API。
尚未发布到 Mooncakes；初验工程完成不等于主办方已经审核通过。
完整初验说明见 [INITIAL_REVIEW.md](docs/INITIAL_REVIEW.md)。

## 能解决什么

| 任务 | 当前行为 |
| --- | --- |
| 从三角数组建立可靠连接关系 | 拒绝越界、非有限坐标、重复/退化面、朝向冲突、非流形边和点扇区；支持边界与多个分量 |
| 修改网格后继续使用 | 拆分内部/边界边、翻转合法内部对角线；可恢复检查错误不会留下部分编辑 |
| 让粗三角曲面变平滑 | 原始 Loop 内点权重、内部边 3/8–1/8 规则、边界规则、同步更新旧点、逐层预算和结果 |
| 接回渲染或其他算法 | 导出坐标和索引、重算法线、边界环、拓扑统计；数据所有权与调用方分离 |

Loop 会移动旧顶点。例如单三角形的原点经过一级细分变为 `(0.25, 0.25, 0)`，
不是仅在边上加中点。已有相近 MoonBit 项目及范围差异见
[RELATED_WORK.md](docs/RELATED_WORK.md)；本项目不声称是第一个网格库。

## 获取与运行

固定工具链：`moonc 0.10.14+7d59c7ec9`，`moon/moonrun 0.1.20260920`。
Node.js 22+ 用于 JS/文件 CLI；Python 3.12+ 只运行开发验证工具。
核心只使用随工具链提供的 MoonBit 标准库。Windows native 需要 MSVC x64 C++ 工具。
CI 固定安装器版本并核对编译器字符串；未声称这是最新工具链。

```sh
git clone https://github.com/ShiChengxu-creater/MoonSurface.git
cd MoonSurface
python tools/check.py --target js
moon run examples/local_edit --target js
moon run examples/loop_refine --target js
```

输出：

```text
local_edit: V=5 E=8 F=4 chi=1 boundary=4
loop_refine: level=0 V=4 E=6 F=4 chi=2
loop_refine: level=1 V=10 E=24 F=16 chi=2
loop_refine: level=2 V=34 E=96 F=64 chi=2
```

第一个示例建立方片、翻转对角线、拆分新对角线、校验连接、导出重建并计算法线。
第二个示例输入四面体、预检两级细分、执行并校验 64 面输出，同时确认输入未变。
替换 `--target` 可用 `native` 或 `wasm-gc`。Windows native 推荐用下方 Python
验证入口，它会通过 `vswhere` 初始化已安装的 MSVC 环境。

## 作为独立模块使用

当前采用**本地 workspace 依赖**，以下目录结构和导入方法已由消费者测试验证：

```text
workspace/
  moon.work
  MoonSurface/       # 此仓库，或实际 moon package ZIP 的解压目录
  app/
    moon.mod
    moon.pkg
    main.mbt
```

`moon.work`：

```toml
members = [ "./MoonSurface", "./app" ]
```

`app/moon.mod`：

```toml
name = "local/surface_demo"
version = "0.0.0"
import { "ShiChengxu/moonsurface@0.1.0-alpha.1" }
```

`app/moon.pkg`：

```moonbit
import { "ShiChengxu/moonsurface" @surface }
pkgtype(kind: "executable")
```

`app/main.mbt`：

```moonbit
fn main {
  try! {
    let mesh = @surface.Mesh::from_indexed(
      [
        { x: 0.0, y: 0.0, z: 0.0 },
        { x: 2.0, y: 0.0, z: 0.0 },
        { x: 0.0, y: 2.0, z: 0.0 },
      ],
      [(0, 1, 2)],
    )
    let result = @surface.subdivide_loop(mesh, 2)
    result.mesh.validate()
    println(result.mesh.face_count()) // 16
  }
}
```

在 workspace 中运行 `moon run app --target js`。`try!` 用于示例的快速失败；
应用应捕获 `SurfaceError`。所有实际公开签名在 [pkg.generated.mbti](pkg.generated.mbti)，
行为约定见 [API.md](docs/API.md)。此过程没有验证 Mooncakes 注册表安装。

## 文件 CLI

```sh
moon build --target js --deny-warn
node tools/moonsurface.mjs examples/data/triangle.json
node tools/moonsurface.mjs examples/data/patch.json --out edited.json
```

`--out` 只创建新文件，已有输出和输入不会被覆盖。失败退出码为 2。
输入只接受 UTF-8 JSON，16 MiB 上限；不直接读取 OBJ/STL。
JSON 解析、参数检查和几何处理由 MoonBit 的 `exchange` 包完成，Node 只处理文件和桥接。
文件协议、失败行为和完整输入见 [JOB_FORMAT.md](docs/JOB_FORMAT.md) 与 `examples/data/`。
原始 `cmd/moonsurface` 接受一个 JSON 字符串参数，可跨三个后端执行小任务；
它用 `{ "ok": false, ... }` 报告业务失败，文件 CLI 负责将其转换为非零退出码。

## 验证与 CI

提交修改后，在干净工作区运行：

```sh
python tools/verify.py --target js
python tools/verify.py --target wasm-gc
python tools/verify.py --target native
```

每次验证显式运行 `moon check/build/test --deny-warn`、两个示例、独立 Python
三角邻接/Loop 参考、干净 Git 快照消费者、**实际 `moon package` ZIP 消费者**，
并核对格式和生成接口。JS 验证另跑 13 项文件 CLI 检查。
验证入口要求当前提交已有至少 10 次历史；提交是否有效仍需查看实际内容。

当前 MoonBit 测试 28 项/后端；独立参考每后端 40 个正常任务、8 个拒绝任务和
3 个错误注入检查；两类消费者各 4 项公开 API 测试。这些数量不代表覆盖率。
参考是本仓库独立编写的数学实现；OpenMesh 外部对照、规模/性能评估仍待后续完成。

GitHub Actions 包含 Ubuntu native/JS/wasm-gc 和 Windows native 四个任务，
Windows 另验证 Node CLI；各任务上传 `artifacts/*.json`。
本地报告也在 `artifacts/`，每份带源码提交和时间。对应提交的远端运行以
[Actions 页面](https://github.com/ShiChengxu-creater/MoonSurface/actions)为准。

## 边界与许可

只接收一致组合朝向的三角二维流形；空网格允许，非空网格的孤立点拒绝。
不自动焊接、修洞、修朝向，不检查全局自交，不保留 UV/材质/骨骼等属性。
拓扑统计的 Euler 数不被当成任意网格的属数证明。
细长或浮点无法区分的三角形会被拒绝；容差、预算和复杂度见
[NUMERICS.md](docs/NUMERICS.md)。计数上限不是进程内存保证。

Apache-2.0。算法资料、工具经验来源和 AI 辅助分别见
[THIRD_PARTY.md](THIRD_PARTY.md)、[AI_USAGE.md](AI_USAGE.md)。
