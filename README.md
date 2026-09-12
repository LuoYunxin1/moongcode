# MoonGCode

面向 MoonBit 的 G-code 离线回放、刀路分析与机床配置预检库，同时提供 CLI。
它把带模态状态的程序转换成毫米制运动段，保留源行号，计算距离、理想匀速时间和完整几何包围盒，再按设备配置检查越界、进给、主轴、刀具等约束。

**这是分析工具，不是控制器。** 不连接串口、不驱动机床；通过静态审计不代表实机安全。
当前维护重点是让已有回放与审计结果可信，而不是扩展指令表。

## 快速开始

安装 MoonBit 工具链；JS 命令还需 Node.js。在仓库根目录执行：

```sh
moon update
moon run cmd/main --target js -- demo
moon run cmd/main --target js -- profiles
```

库名为 `LuoYunxin1/moongcode`；在自己的 MoonBit 项目中添加依赖后，导入该包即可调用库 API。
仓库版本仍为 0.1.0，本轮改动以 Git 提交为准；这里不表示 MoonCakes 已发布新版本。

## 三个可运行的例子

### 1. 螺旋刀路：不能只算平面圆弧

```sh
moon run cmd/main --target js -- analyze examples/helix.nc
moon run cmd/main --target js -- audit examples/helix.nc
```

从 `(10,0,0)` 沿半径 10 mm 的四分之一圆弧走到 `(0,10,10)`。
圆弧同时抬高 10 mm，真实空间长度应为 `hypot(10π/2, 10)`，约 **18.6209588912 mm**，不是平面投影的 15.7079632679 mm。
加上初始 10 mm 快移，CLI 总距离约 **28.6209588912 mm**；F60 下含快移的理想时间约 **18.7209588912 s**。默认铣床配置审计为 `PASS`。

### 2. 同行切换平面：端点没越界不代表圆弧没越界

```sh
moon run cmd/main --target js -- audit-profile examples/plane-switch.nc examples/shallow-z.profile
```

`G18 G2 I5 K0` 在同一行选择 ZX 平面并走完整圆。起终点都在原点，但圆弧的 Z 范围为 `[-5,5]` mm，超出配置的 `[-4,4]` mm。
预期输出 `FAIL`、第 2 行的 `audit.workspace.bounds`，退出码 **1**。这是预期的拒绝，不是运行故障。

### 3. 自动化检查：错误不能被成功退出码掩盖

```sh
moon run cmd/main --target js -- analyze examples/invalid-feed.nc
moon run cmd/main --target js -- auidt examples/safe.nc
```

第一条存在未设置进给的 G1 运动，输出 `interpret.feed.missing`，退出码 **1**；第二条故意拼错命令，输出 `cli.command.unknown`，退出码 **2**，不会悄悄运行演示。
`analyze`/`trace` 在错误程序上可能输出部分回放信息，必须同时检查退出码；这些信息不可作为有效加工轨迹。

## 库调用与处理流程

```moonbit
let execution = @moongcode.interpret_source(source)
let stats = @moongcode.analyze_execution(execution)
let report = @moongcode.audit_execution(execution, @moongcode.MachineProfile::desktop_mill())
println(@moongcode.safety_report_text(report))
```

`parser → interpreter → geometry → audit → render`：解析器保留源码行和诊断；解释器记录每行执行前后的单位、平面、运动、进给与主轴状态；几何层求解线段/圆弧；审计层使用该行生效后的平面检查完整包围盒。
库调用方应检查 `execution.is_valid()` 和 `report.passed()`，而不是只读取距离数值。

支持范围：`G0/G1/G2/G3`、`G4`、`G17/G18/G19`、`G20/G21`、`G90/G91`、`G90.1/G91.1`，以及 `F/S/T`、`M0/M1/M2/M3/M4/M5/M30`、XYZ/IJK/R/P、行注释、括号注释和可选校验和。
支持 IJK 中心偏移、绝对中心、带符号 R 圆弧和螺旋圆弧。默认把不支持的指令视为错误；库调用者可显式降级为警告。

不支持坐标系偏置、刀具补偿、宏、固定循环、碰撞检测、加减速规划或实机控制。时间只是距离/进给加停留，不是加工节拍承诺。

## CLI 契约

- `validate` 只检查语法，不能替代 `analyze` 或 `audit`。
- `normalize`、`explain` 检查解析结果；`trace`、`analyze` 检查解释执行结果。
- `audit` 使用默认铣床配置；`audit-laser` 使用激光配置；`audit-profile` 读取自定义配置；`audit-md` 输出 Markdown 报告。
- 退出码：0=该命令检查通过，1=输入/回放/审计未通过，2=命令参数或文件/配置读取错误。
- 无参数时运行内置 `demo`；未知命令和多余参数拒绝执行。

## 维护质量证据

相同参考脚本分别运行于维护基线 `612e573` 和修复代码 `f9ed665`，不修改旧版本测试预期：

| 检查 | 基线 | 修复后 |
|---|---:|---:|
| 432 组独立圆弧解析值校验 | 144/432 | 432/432 |
| 24 组工作空间边界审计 | 20/24 | 24/24 |
| 14 组 CLI 契约检查 | 5/14 | 14/14 |

本地 JS 测得圆弧长度最大绝对误差 **2.274×10⁻¹³ mm**；这是限定样本与解析公式间的浮点误差，**不是设备精度**。
普通测试由 99 项增至 104 项，本地 wasm-gc、wasm、JS 各 104 项通过。
CI 增加 JS/native 独立参考检查并上传 JSON；CI 是否通过须查看相应提交的实际运行，不能由本地结果推断。

```sh
moon fmt --check
moon check --target wasm-gc --deny-warn
moon check --target wasm --deny-warn
moon check --target js --deny-warn
moon check --target native --deny-warn
moon test --target wasm-gc
moon test --target wasm
moon test --target js
moon test --target native
python scripts/verify_reference.py --output _build/reference-js.json
python scripts/verify_reference.py --target native --output _build/reference-native.json
```

Native 编译/测试需要 C 编译器。参考样本覆盖范围、重现方式、对标边界见 [维护报告](docs/maintenance/REPORT.md) 和 [参考校验说明](scripts/README.md)。

## 许可与责任边界

原生 MoonBit 实现，Apache-2.0；CLI 使用 `moonbitlang/x` 的文件和进程辅助接口。
规范和对标资料只用于语义参照，没有移植 LinuxCNC/Grbl 源码。
第三方说明见 `THIRD_PARTY.md`，安全报告见 `SECURITY.md`，开发辅助工具说明见 `AI_USAGE.md`。
