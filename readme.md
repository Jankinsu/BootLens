# BootLens

BootLens 是一个面向 Windows 的只读启动观察工具。它读取 Windows 已记录的启动诊断信息，帮助查看完整启动历史、启动项配置和当前进程相对启动锚点的时间；不驻留后台，也不替用户自动修改系统。

## 功能

- **启动历史**：显示 Windows 确认的完整启动记录及启动阶段耗时。
- **启动项发现**：查看 Registry Run、Startup Folder、Scheduled Tasks 和自动启动 Windows Services。
- **进程时间线**：将扫描时仍在运行的进程创建时间与最近一次完整启动锚点比较。
- **启动退化事件**：显示 Windows Diagnostics-Performance Event ID 101 原始记录，并尝试关联到 Event ID 100 完整启动记录。

## 快速开始

### 运行要求

- Windows 和 PowerShell 7（`pwsh.exe`）；这是当前主要使用和验证的 PowerShell 版本。
- GUI 当前由 PowerShell 脚本加载 WPF 界面。
- 建议从**管理员权限**的 Windows Terminal / PowerShell 运行，以读取完整启动诊断日志和受限的启动项来源。非管理员运行时，部分数据可能不可用。
- 当前项目无需安装第三方 PowerShell 模块。

Windows PowerShell 5.1 不是当前主要测试目标；除非后续专门增加兼容性验证，不应默认假设两个版本的行为完全一致。

在项目根目录运行 GUI：

```powershell
.\bootlens-gui.ps1
```

### 命令行

```powershell
# 最近 10 次确认的完整启动
.\bootlens.ps1 -Count 10

# 发现启动项；可用 -Source 选择来源
.\bootlens-startup.ps1 -Source All

# 扫描当前仍在运行的进程
.\bootlens-processes.ps1 -Count 50
```

常用参数：

| 入口 | 参数 |
|---|---|
| `bootlens.ps1` | `-Count`、`-ScanEvents`、`-AsJson` |
| `bootlens-startup.ps1` | `-Source`、`-AsJson`、`-ShowCommand` |
| `bootlens-processes.ps1` | `-Count`、`-ScanEvents`、`-OperationTimeoutSec`、`-AsJson` |

启动项 `-Source` 可选 `All`、`RegistryRun`、`StartupFolder`、`ScheduledTask` 或 `WindowsService`。`-ShowCommand` 会输出配置中的命令行，分享结果前注意检查是否包含敏感信息。

## 如何理解结果

### 完整启动

BootLens 只将通过 Windows 启动事件交叉验证的完整启动纳入 `BootRecord`。已确认的 Restart 和 `shutdown /s /t 0` 后启动属于完整启动；Fast Startup、睡眠/休眠恢复及无法确认类型的记录不纳入。详细接受条件见 [BootRecord 数据契约](docs/boot-record.md)。

- **Main Path**：Windows 报告的桌面出现前主要启动阶段耗时。
- **Post Boot**：桌面出现后的 Windows 报告阶段耗时。
- **Boot Offset**：进程创建时间相对完整启动锚点的偏移，**不是该进程启动耗时**。

进程时间线是扫描时仍然存活的进程快照；已经退出的进程不会出现在其中。启动项页面显示的是配置发现结果，不表示项目实际运行耗时或对启动的影响。

### Windows 启动退化事件

Event ID 101 的 `StartTime` 与 Event ID 100 的启动锚点精确匹配时，关联到对应完整启动。`TotalTime` 和 `DegradationTime` 是 Windows 报告的两个独立原始字段：BootLens 不相减、不相加，也不把它们解释成单个程序造成的启动延迟。

目标匹配等级说明：

- **Exact path**：事件路径与当前发现的启动项路径相同；当前配置不一定等于事件发生时的历史配置。
- **App family candidate**：名称相符但完整路径不同，仅为候选。
- **Generic host**：如 `svchost.exe`，无法据此识别具体服务。
- **Ambiguous / Unmatched**：存在多项候选，或没有可靠匹配。

任何匹配都不证明目标导致了启动变慢。更多样本与边界说明见 [Phase 4 数据验证](docs/phase-4-data-validation.md)。

## 测试

在 PowerShell 7 的项目根目录运行全部测试：

```powershell
Get-ChildItem .\tests\*.Tests.ps1 | ForEach-Object {
    & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Test failed: $($_.Name)" }
}
```

只验证 GUI XAML 与必需控件（不会读取事件日志或打开窗口）：

```powershell
.\bootlens-gui.ps1 -ValidateOnly
```

## 项目结构

```text
bootlens.ps1                    启动历史 CLI
bootlens-startup.ps1            启动项发现 CLI
bootlens-processes.ps1           当前进程时间线 CLI
bootlens-gui.ps1                 WPF GUI 入口
ui/MainWindow.xaml               GUI 布局
scripts/                         数据 Provider 与只读探测脚本
tests/                           PowerShell 回归与契约测试
docs/                            数据契约、阶段验证记录
```

接手开发时建议先看本 README，再按任务阅读对应的数据契约和验证记录：

- [BootRecord](docs/boot-record.md)
- [StartupItem](docs/startup-item.md)
- [Process Timeline](docs/process-timeline.md)
- [Boot Trend](docs/boot-trend.md)
- [Diagnostic Observation](docs/diagnostic-observation.md)
- [Phase 6 数据验证](docs/phase-6-data-validation.md)
- [Phase 5 数据验证](docs/phase-5-data-validation.md)
- [Phase 0 数据验证](docs/phase-0-data-validation.md)
- [Phase 3 数据验证](docs/phase-3-data-validation.md)
- [Phase 4 数据验证](docs/phase-4-data-validation.md)

## 项目路线图

| 阶段 | 目标 | 状态 |
|---|---|---|
| Phase 0：数据验证 | 验证 Windows 启动事件、启动类型与数据语义 | 已完成 |
| Phase 1：启动历史 | 展示已确认的完整启动记录及阶段耗时 | 已完成 |
| Phase 2：启动项发现 | 只读发现常见自动启动配置来源 | 已完成 |
| Phase 3：启动时间线 | 展示当前存活进程相对完整启动锚点的创建时间偏移 | 数据展示、权限降级、列表滚动和完整路径展开已验收；详情开合待验收 |
| Phase 4：启动退化事件 | 展示 Event 101 原始数据、完整启动关联和目标匹配等级 | 数据展示和权限降级已验收；详情开合待验收 |
| Phase 5：趋势分析 | 分析最近完整启动的历史变化；首版查看最近 30 次启动及样本摘要 | 已实现，人工验收完成 |
| Phase 6：诊断提示评估 | 汇总 Windows 明确记录的退化标记；不做无依据的单应用因果归因或自动系统修改 | 首版已实现，人工验收完成 |

### Phase 5 验收状态

启动历史页和 CLI 默认展示最近 30 次确认的完整启动，并包含实测耗时趋势和样本摘要；CLI、JSON 和 GUI 已完成管理员 PowerShell 7 本机人工验收。趋势只描述启动记录本身；Event 101 仍作为独立的 Windows 诊断记录，不据此推导单个程序造成的启动延迟。

### Phase 6 验收状态

诊断观察首版只汇总最近完整实测启动中 Event 100 的 Windows 退化标记（已标记、未标记、未知），并显示最新记录的时间和 Event 100 Record ID。CLI、JSON 和 GUI 已完成人工验收。它不推断具体原因或责任应用；Event 101 仍独立展示。后续如需扩展其他提示，须先确认有足够证据。

### 当前下一步：验收两个页面的详情开合

用户报告现有 PowerShell 测试套件全部通过。管理员 GUI 下各页面均已确认正常；普通权限下启动项页面显示可读取配置，其他三个数据页显示管理员权限提示，这是受限数据源下的预期降级。进程时间线列表滚动和完整路径展开已由用户确认正常。本次修改让进程时间线与启动退化页面都支持再次点击所选行收起详情，待用户实操验收。

### 暂缓事项（独立于 Phase 5/6）

以下事项暂缓，尚未选定技术方案或开始重构：

- **独立 GUI 重构**：未来评估如何让 GUI 脱离当前 PowerShell 托管 WPF 的实现方式，选择并验证独立桌面应用技术栈；目前不预选框架。
- **GUI 性能评估**：已观察到加载完成后页面切换约有 2–3 秒延迟。后续与 GUI 技术选型一并复测；目前不把该现象预设为某个特定技术的缺陷。

## 开发约束

- 只读、按需运行；不创建后台服务、不修改启动配置。
- 优先使用 Windows 自身已有数据，明确标注数据来源与不可用状态。
- 严格区分测量值、快照、候选关联和推断；证据不足时保留 `Unknown` / 未匹配，不制造精度或因果结论。
- 先维护数据正确性和语义，再扩展功能；避免不必要的依赖、常驻工作和系统扰动。
