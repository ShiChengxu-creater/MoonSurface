# MoonSurface

[![validation](https://github.com/ShiChengxu-creater/MoonSurface/actions/workflows/ci.yml/badge.svg)](https://github.com/ShiChengxu-creater/MoonSurface/actions/workflows/ci.yml)

纯 MoonBit 的模型表面处理库：传递属性、保留锐边与接缝，执行局部编辑及各向同性重网格化，
输出可交给渲染器、模型工具或资产管线的几何、UV、材质和法线数据。
核心支持 native、JS、wasm-gc，不依赖 C++/Python 几何库或渲染引擎。

**稳定版 [`0.2.0`](https://mooncakes.io/docs/ShiChengxu/moonsurface@0.2.0) 已发布，**
三后端真实注册表消费者均已验证。发布源码为 `b993b41`，后续提交仅补充发布记录。
本版保持 0.2 alpha 的产品接口，增加连续编辑、异常任务、规模测量和交付验证。
QEM 尚未实现。发布事实见 [REGISTRY_RELEASE.md](docs/REGISTRY_RELEASE.md)。

## 模型处理能力

| 任务 | 当前行为 |
| --- | --- |
| 顶点属性 | 1–4 维线性数值、三维单位向量、离散通道；插值/归一化，冲突前拒绝 |
| 纹理/材质 | 面角 UV0 独立保存接缝两侧值，逐面材质继承；拒绝 UV 翻转 |
| 特征保护 | 二面角、显式边、边界、UV/材质/离散界面形成约束；特征顶点保守锁定，分裂继承约束 |
| 编辑/导出 | Model split/flip/受检内部 collapse、存活标记与 compact 映射；按特征分组重算面角法线 |
| 重网格化 | 拆长边、折短边、价数改善、切向松弛、参考 BVH 投影和属性重采样 |
| 质量约束 | 最小角底线、原表面见证点及新面采样距离检查；操作/拒绝分类与停止原因 |
| 原几何能力 | Mesh 半边、边界与邻域、独立数组导出、几何 Loop 与法线接口继续保留 |

详细范围见 [MODEL_CONTRACT.md](docs/MODEL_CONTRACT.md)，真实模型与独立对照见
[REAL_MODELS.md](docs/REAL_MODELS.md)。骨骼权重、形变目标、多套 UV、完整 glTF 往返与
全局自交检查不在当前范围。Loop 是几何接口，未宣称传递 Model 属性。

## 安装与运行

在已有 MoonBit 项目中安装已发布版：

```sh
moon add ShiChengxu/moonsurface@0.2.0
```

公开包提供 `ShiChengxu/moonsurface` 及 `ShiChengxu/moonsurface/exchange`。
完整 Model 调用见 [feature_remesh](examples/feature_remesh/main.mbt)，约束与错误见
[MODEL_CONTRACT.md](docs/MODEL_CONTRACT.md)。源码例子按下列命令运行。

固定编译器 `moonc 0.10.14+7d59c7ec9`，moon/moonrun `0.1.20260920`。
Node.js 22+ 运行文件宿主；Python 3.12+、NumPy 2.2.6 仅用于独立验证。
Windows native 需要 MSVC x64；验证脚本通过 `vswhere` 初始化已有工具链。

```sh
git clone https://github.com/ShiChengxu-creater/MoonSurface.git
cd MoonSurface
python -m pip install -r requirements-dev.txt
python tools/check.py --target js
moon run examples/local_edit --target js
moon run examples/loop_refine --target js
moon run examples/feature_remesh --target js
```

三个例子分别完成局部编辑、四面体细分、带 UV/材质和离散通道的特征保护重网格化。
第三个实际检查属性对应及原锐边覆盖。替换 target 可用 native 或 wasm-gc。

真实模型是许可明确的 glTF 局部几何，包含原始面角 UV 和材质；无需下载贴图：

```sh
moon build --target js --deny-warn
node tools/moonsurface.mjs fixtures/real/avocado/input.json --out avocado-remeshed.json
node tools/moonsurface.mjs fixtures/real/suzanne/input.json --out suzanne-remeshed.json
```

文件 CLI 只创建新输出。输入有界 UTF-8 JSON；Node 负责文件宿主，JSON/属性/几何/报告由
MoonBit 完成。协议见 [JOB_FORMAT.md](docs/JOB_FORMAT.md)。

## 独立模块接入

以下 workspace 用于源码或实际 ZIP 的本地开发。使用注册表依赖时无需创建
`moon.work`，采用上述已发布版本；`0.1.0-alpha.1` 只有旧几何接口。

```text
workspace/
  moon.work
  MoonSurface/
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
import { "ShiChengxu/moonsurface@0.2.0" }
```

`app/moon.pkg`：

```moonbit
import { "ShiChengxu/moonsurface" @surface }
pkgtype(kind: "executable")
```

`app/main.mbt`（原几何接口也继续支持）：

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

在 workspace 中运行 `moon run app --target js`。新流程使用 `Model::new` 接收几何与属性，
`remesh_isotropic` 返回快照与报告。完整调用见
[feature_remesh/main.mbt](examples/feature_remesh/main.mbt)，签名见 [pkg.generated.mbti](pkg.generated.mbti)。
实际应用应捕获 `SurfaceError`，示例 `try!` 仅用于快速失败。

## 验证

在干净已提交源码中运行：

```sh
python -m pip install -r requirements-dev.txt
python tools/verify.py --target js
python tools/verify.py --target wasm-gc
python tools/verify.py --target native
```

覆盖格式/接口漂移、显式 check/build/test、三个示例、Loop 独立参考、源码/实际 ZIP 消费者、
六个固定种子模型任务及四类损坏结果负控。JS 另跑真实模型与 13 项文件 CLI 检查。
当前 MoonBit 测试 46 项/后端，包括四组种子共 480 次连续编辑、失败快照保持、
反复重网格/压缩重导入及资源失败。源码/ZIP/注册表消费者各 5 项；数量不代表覆盖率。
JS 文件宿主另验证 4 个变换/折面任务、21 类非法任务和重复输出一致性。

外部对照另外运行，需要可选依赖：

```sh
python -m pip install -r requirements-reference.txt
python tools/model_verify.py --target js --real --reference
```

保留原模型、MoonSurface 属性模式/几何模式、MeshLab 几何模式的实际输出。约束策略不同，
不宣称全面质量或性能优势。报告在 `artifacts/model-*.json`，含源码、参数、环境、输入/输出哈希。
采样距离不是连续曲面的严格 Hausdorff 上界。

CI 包含 Linux native/JS/wasm-gc 和 Windows native；Windows 另执行固定 MeshLab 对照。
对应提交状态见 [Actions](https://github.com/ShiChengxu-creater/MoonSurface/actions)。
发布版本与确切提交记录见 [REGISTRY_RELEASE.md](docs/REGISTRY_RELEASE.md)。
终验范围及逐项重现入口见 [FINAL_REVIEW.md](docs/FINAL_REVIEW.md)。

可选分档测量（不设机器速度门槛）：

```sh
python tools/benchmark.py --sizes 32 64 128 --repeats 3
```

测量包含 Node 启动、文件输入、核心计算及输出序列化；进程内存为每 20 ms 观察的系统
峰值计数，属于观测下界，含宿主开销。较大任务可能因操作预算提前停止。
不能把计数上限当作可处理任意同规模模型的保证。实际分档结果及质量限制见
[SCALE.md](docs/SCALE.md)。

## 许可证与边界

MoonBit 库及主要验证代码为 Apache-2.0，真实模型为 CC0-1.0；可选独立
`reference_tools/meshlab_reference.py` 驱动为 GPL-3.0-only，许可证随目录保留。
没有随包分发 MeshLab 二进制。来源与 AI 辅助见 [THIRD_PARTY.md](THIRD_PARTY.md)、[AI_USAGE.md](AI_USAGE.md)。
计数预算不是 RSS 保证，约束可能使目标边长无法全部达到。数值政策见
[NUMERICS.md](docs/NUMERICS.md)，模型细节见 [MODEL_CONTRACT.md](docs/MODEL_CONTRACT.md)。
