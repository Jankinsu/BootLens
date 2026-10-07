# BootLens

> 一个轻量、透明、低资源占用的 Windows 启动性能分析工具。

BootLens 的目标不是成为另一个“大而全”的 Windows 系统管理器，而是专注做好一件事情：

> **准确、清晰地展示 Windows 启动过程，并帮助用户理解系统启动时间是如何构成的。**

项目优先考虑：

- 低资源占用
- 数据来源透明
- 测量结果可信
- 架构简单清晰
- 无后台常驻
- 不主动污染被测启动过程
- 按阶段逐步扩展能力

---

# 1. 项目背景

Windows 本身已经记录了大量启动性能信息，例如：

- 系统启动诊断事件
- 启动阶段耗时
- 启动性能退化事件
- 进程启动时间
- 注册表启动项
- Startup Folder
- Scheduled Tasks
- Windows Services

因此，一个启动分析工具并不一定需要：

- 开机时自动启动
- 后台常驻监控
- 持续采样 CPU
- 运行额外的计时服务

BootLens 采用的基本思想是：

```text
Windows 启动
    ↓
Windows 自身产生启动遥测数据
    ↓
系统正常进入桌面
    ↓
用户按需运行 BootLens
    ↓
BootLens 读取并分析已有数据
```

也就是说：

> **被测系统负责产生 telemetry，BootLens 负责事后分析 telemetry。**

这样可以尽量减少分析工具本身对启动过程的扰动。

---

# 2. README 的作用

本文档不仅用于介绍项目，也作为整个项目开发过程中最高层级的设计约束。

它主要承担四个作用。

## 2.1 定义项目边界

明确 BootLens：

- 要做什么
- 不做什么
- 当前阶段做到什么程度
- 哪些功能属于未来扩展

避免开发过程中不断添加与核心目标无关的功能。

## 2.2 规定开发路径

项目采用多阶段开发方式。

每一阶段：

1. 只解决一个明确问题；
2. 形成可运行版本；
3. 验证数据正确性；
4. 验证资源占用；
5. 再进入下一阶段。

不得为了“最终架构完整”而提前引入大量暂时用不到的代码。

## 2.3 作为 Codex 的开发约束

Codex 在修改本项目时，应首先阅读本文档。

任何功能开发都应满足：

> 当前阶段需求 > 简洁性 > 可维护性 > 扩展性 > 功能数量

如果某项设计明显增加：

- 依赖
- 程序体积
- 后台资源占用
- 架构复杂度

但没有解决当前阶段明确需求，则默认不采用。

## 2.4 记录项目设计哲学

BootLens 不只是一个工具实验。

项目同时用于学习：

- Windows Event Log
- Windows 启动机制
- 进程模型
- Registry
- Services
- Task Scheduler
- 软件分层
- 数据模型设计
- Windows 桌面软件开发

因此代码应尽量保持：

> **结构清楚到可以通过阅读源码理解 Windows 启动分析过程。**

---

# 3. 核心设计原则

## 3.1 按需运行，而非后台常驻

BootLens 默认：

- 不注册开机启动
- 不创建后台 Service
- 不常驻系统托盘
- 不长期轮询 Event Log
- 不持续监控进程

正常工作模型：

```text
启动 BootLens
    ↓
采集数据
    ↓
分析数据
    ↓
展示结果
    ↓
用户关闭
    ↓
资源完全释放
```

---

## 3.2 不为了测启动而拖慢启动

BootLens 本身不能成为明显的启动负担。

因此原则上禁止：

```text
BootLens 开机自动运行
        ↓
占用 CPU / RAM / I/O
        ↓
同时测量 Windows 启动性能
```

除非未来某个实验功能确实必须参与启动过程，否则启动分析优先采用 Windows 已保存的数据。

---

## 3.3 区分“测量值”和“推断值”

BootLens 必须严格区分不同来源的数据。

至少应区分以下三种语义。

### Measured

Windows 明确记录的性能数据。

例如：

```text
Diagnostics-Performance Event Log
```

这类数据可以标记为：

```text
Measured
```

---

### Boot Offset

某个程序在开机之后多久启动。

例如：

```text
Windows Boot       0 s
Explorer            8.4 s
OneDrive           12.1 s
Steam              18.7 s
```

这里的：

```text
18.7 s
```

表示：

> Steam 在系统启动约 18.7 秒之后启动。

它**不表示**：

> Steam 导致系统启动延长了 18.7 秒。

必须避免混淆。

---

### Estimated

无法获得可靠测量数据时，根据有限信息进行的估算。

任何估算值都必须明确标记：

```text
Estimated
```

不能以精确测量值的形式展示。

---

# 4. 第一原则：不要伪造精度

BootLens 宁可显示：

```text
Unknown
```

也不要为了让 UI “看起来完整”而编造一个看似精确的数据。

例如：

```text
Steam startup impact: 3.72 s
```

只有当 Windows 有足够可靠的数据支持这个数字时才能展示。

否则应展示：

```text
Steam

Started: +18.7 s after boot
Impact: Unknown
Source: Process Start Time
```

数据可信度优先于界面完整度。

---

# 5. 项目开发路径

BootLens 采用逐级增强方式开发。

---

# Phase 0：环境与数据验证

目标：

> 在写 GUI 之前，先确认 Windows 提供的数据到底是什么。

这一阶段只验证底层数据。

主要研究：

- Diagnostics-Performance Event Log
- Event ID 100
- Event ID 101 等启动性能事件
- Process.StartTime
- 系统启动时间
- Fast Startup 对数据的影响
- Shutdown / Restart / Sleep / Hibernate 的差异

允许使用：

- PowerShell
- Event Viewer
- 小型测试程序

本阶段不需要 GUI。

完成标准：

- 能稳定读取最近若干次启动记录；
- 明确每个关键字段的真实含义；
- 明确哪些数据可靠，哪些数据只能推断。

---

# Phase 1：启动历史

第一版真正可使用的软件。

核心功能：

```text
BootLens

Last Boot        13.4 s
Average          14.1 s
Fastest          12.7 s
Slowest          18.6 s
```

并显示最近若干次启动：

```text
2026-10-06    13.4 s
2026-10-05    14.0 s
2026-10-03    13.1 s
```

功能范围：

- 读取 Windows 启动日志
- 提取启动时间
- 最近 N 次启动
- 平均值
- 最快
- 最慢
- 基础异常检测

暂时不做：

- 启动项分析
- Service 分析
- Process Timeline
- 禁用启动项
- 实时资源监控

完成标准：

> BootLens 已经可以替代一个简单的 Windows 开机计时器。

---

# Phase 2：启动项发现

增加 Windows Startup Discovery。

数据来源逐步加入：

```text
Registry Run
Startup Folder
Scheduled Tasks
Windows Services
UWP Startup Tasks
```

统一转换为：

```text
StartupItem
```

推荐数据模型：

```text
StartupItem

Name
Source
Command
Path
Publisher
Enabled
Essential
```

此阶段关注：

> 谁会参与 Windows 启动？

而不是：

> 谁拖慢了多少秒？

UI 可以提供：

```text
Startup Items

Name           Source          Enabled
Clash Verge    Registry        Yes
OneDrive       Registry        Yes
Steam          Registry        Yes
ExampleSvc     Service         Yes
```

---

# Phase 3：启动时间线

加入 Process Start Time。

构造：

```text
系统启动时间
        ↓
进程 StartTime
        ↓
Boot Offset
```

最终形成：

```text
Startup Timeline

0 s        Windows Boot

8.2 s      Explorer
11.7 s     Clash Verge
13.1 s     OneDrive
17.4 s     Steam
```

重要：

> Boot Offset 不是 Startup Duration。

UI 和数据模型必须保持这种语义区分。

---

# Phase 4：启动性能关联

这一阶段开始尝试回答：

> 哪些程序可能真正拖慢了 Windows 启动？

数据来源：

```text
Diagnostics-Performance
Event ID 100
Event ID 101
其他相关启动性能事件
```

主要工作：

- Event Log 解析
- 启动项与性能事件匹配
- EXE 名称关联
- 文件路径关联
- Friendly Name 关联
- Service 关联
- Scheduled Task 关联

可能出现：

```text
StartupItem
    ↓
Process
    ↓
Event Log degradation entry
```

此阶段必须明确数据来源。

例如：

```text
Steam

Boot Offset: +18.2 s
Measured degradation: 1.4 s
Source: Windows Diagnostics
```

---

# Phase 5：趋势分析

在基础数据稳定后加入历史趋势。

例如：

```text
最近 30 次启动

平均启动时间
趋势变化
异常启动
性能退化
```

可以检测：

```text
过去平均：13.8 s
最近平均：18.4 s

↑ 33 %
```

进一步定位：

```text
可能变化：

新增启动项
新增 Service
某程序 degradation 增加
Windows Update
```

该阶段重点是：

> 从“看一次启动”升级到“观察系统长期状态”。

---

# Phase 6：诊断建议

只有当底层数据足够可靠后，才加入建议功能。

例如：

```text
Steam

Startup: Enabled
Boot Offset: +17.4 s
Measured Impact: 1.2 s

Suggestion:
Not required for Windows startup.
Consider disabling automatic startup.
```

建议必须满足：

- 有明确依据
- 不删除用户数据
- 不修改系统关键组件
- 不默认执行操作

BootLens 优先做：

> 分析工具

而不是：

> 系统优化大师

---

# 6. 明确不追求的功能

至少在早期阶段，BootLens 不计划实现：

- 系统垃圾清理
- 注册表清理
- 内存清理
- 驱动管理
- Windows 更新管理
- 杀毒功能
- 系统加速按钮
- 游戏优化
- 全系统实时监控
- 常驻资源监控
- 自动“一键优化”

避免项目演变为：

```text
又一个 Windows 系统工具箱
```

BootLens 始终保持核心定位：

> Windows Startup Performance Inspector

---

# 7. 推荐架构

推荐采用清晰的分层结构。

```text
BootLens
│
├── Models
│
│   ├── BootRecord
│
│   ├── StartupItem
│
│   ├── BootEvent
│
│   └── AnalysisResult
│
├── Providers
│
│   ├── EventLogProvider
│
│   ├── RegistryStartupProvider
│
│   ├── StartupFolderProvider
│
│   ├── TaskSchedulerProvider
│
│   ├── ServiceProvider
│
│   └── ProcessProvider
│
├── Services
│
│   ├── BootHistoryService
│
│   ├── StartupDiscoveryService
│
│   ├── TimelineService
│
│   └── StartupAnalysisService
│
├── ViewModels
│
├── Views
│
└── App
```

基本数据流：

```text
Windows
   ↓
Providers
   ↓
Models
   ↓
Services
   ↓
ViewModels
   ↓
Views
```

UI 不应该直接读取：

- Registry
- Event Log
- Services
- Process

所有系统数据访问统一通过 Provider / Service。

---

# 8. Provider 设计规范

不同 Windows 数据源应该尽可能保持独立。

例如：

```text
IStartupProvider
```

可以定义为：

```text
GetStartupItems()
```

然后：

```text
RegistryStartupProvider
StartupFolderProvider
ScheduledTaskProvider
ServiceStartupProvider
```

分别实现。

最终：

```text
StartupDiscoveryService
```

负责统一聚合。

这样未来增加数据源时：

```text
新增 Provider
```

而不是修改整个系统。

---

# 9. 数据模型优先

在开发 GUI 前，优先确保核心对象设计合理。

例如：

```text
BootRecord
```

负责描述一次 Windows 启动。

```text
StartupItem
```

负责描述一个启动项。

```text
BootTiming
```

负责描述时间数据。

建议将：

```text
时间值
```

和：

```text
时间来源
```

绑定。

例如：

```text
Timing

Value
Type
Source
Confidence
```

避免后续出现：

```text
StartupTimeMs = 18000
```

但没人知道：

> 18000 到底代表启动耗时还是启动时间点？

---

# 10. 时间语义规范

任何时间变量必须表达清楚语义。

推荐：

```text
BootDuration
BootOffset
MeasuredDegradation
ProcessStartOffset
```

避免：

```text
StartupTime
Time
Duration
Delay
```

这类语义模糊的变量。

例如：

```text
Steam starts 18 s after boot
```

应使用：

```text
BootOffset = 18s
```

而不是：

```text
StartupTime = 18s
```

---

# 11. 资源占用目标

BootLens 是一个性能分析工具，因此自身资源占用必须受到约束。

## 11.1 后台资源

关闭 BootLens 后：

```text
CPU = 0
RAM = 0
Background Process = 0
```

不得安装长期运行的后台 Service。

---

## 11.2 启动行为

默认不得：

- 开机自启
- 自动创建 Scheduled Task
- 创建后台 Service
- 常驻 Tray

---

## 11.3 运行时 CPU

主要资源消耗应发生在：

```text
扫描
解析
分析
```

阶段。

扫描完成后 CPU 应迅速下降到接近空闲。

---

## 11.4 RAM

RAM 应保持在普通轻量 Windows 工具合理范围。

如果某个功能明显增加数百 MB 内存占用，需要重新评估设计。

---

## 11.5 磁盘占用

应避免：

- 大型运行时重复打包
- Electron
- Chromium
- Node.js Runtime
- Python Runtime
- 大型数据库

如果技术栈必须带来较大的运行环境，应明确评估：

```text
功能收益 / 资源成本
```

---

# 12. 性能测量原则

任何 BootLens 性能优化必须基于实际测量。

不得因为：

```text
“感觉这个可能更快”
```

而增加复杂设计。

至少关注：

```text
Cold Start Time
Analysis Time
Peak RAM
Idle RAM
CPU Peak
Disk Reads
Final Package Size
```

---

# 13. 安全原则

BootLens 前期默认只读。

即：

```text
读取 Registry
读取 Event Log
读取 Services
读取 Scheduled Tasks
读取 Process
```

不主动修改系统。

任何修改系统的功能，例如：

```text
Disable Startup Item
Disable Scheduled Task
Change Service Startup Type
```

必须：

1. 单独实现；
2. 明确显示将要执行的操作；
3. 用户主动确认；
4. 提供恢复方式；
5. 不操作关键系统组件。

---

# 14. 管理员权限

BootLens 应尽量在普通用户权限下工作。

只有确实需要管理员权限的数据访问才申请提升权限。

原则：

> 能普通权限完成的功能，不要求管理员权限。

不要因为开发方便而默认：

```text
requireAdministrator
```

如果部分数据不可访问，应：

```text
正常启动
↓
显示部分数据
↓
提示某些高级数据需要管理员权限
```

而不是直接拒绝运行。

---

# 15. 错误处理规范

Windows 系统环境差异很大。

以下情况均属于正常情况：

- 某 Event Log 不存在
- 某 Registry Key 不存在
- 某 Service 无权限读取
- 某进程在扫描过程中退出
- 某 EXE 无版本信息
- Process.StartTime 无法访问
- 某 Scheduled Task 无法解析

因此 Provider 层必须能够：

```text
局部失败
≠
整个程序失败
```

例如：

```text
RegistryProvider 成功
ServiceProvider 成功
TaskSchedulerProvider 失败
```

BootLens 仍应展示能够获取的数据。

---

# 16. 日志规范

BootLens 自身应保留轻量日志能力。

主要用于：

- Provider 失败
- Event 解析错误
- 权限问题
- 未识别数据
- 程序异常

日志不得：

- 高频持续写磁盘
- 记录敏感用户数据
- 无限增长

默认采用简单滚动日志即可。

---

# 17. 测试策略

优先测试核心数据逻辑，而不是 UI。

重点测试：

```text
Event Log parsing
Startup Item deduplication
Path normalization
Process matching
Boot Offset calculation
Timing source classification
```

Provider 层应尽量支持 Mock 数据。

例如：

```text
FakeEventLogProvider
FakeProcessProvider
FakeRegistryProvider
```

这样可以在不依赖真实 Windows 状态的情况下测试分析逻辑。

---

# 18. Codex 开发规范

Codex 每次执行较大的开发任务前，应：

1. 阅读 README；
2. 确认当前 Phase；
3. 检查已有数据模型；
4. 优先复用现有抽象；
5. 不提前实现未来阶段功能。

修改代码时优先：

```text
小改动
明确边界
可测试
可回滚
```

不要为了所谓：

```text
“未来扩展性”
```

提前设计大量抽象层。

---

## 禁止行为

除非明确要求，否则 Codex 不应：

- 引入大型第三方框架
- 增加数据库
- 增加网络服务
- 增加遥测上传
- 增加账户体系
- 增加自动更新服务
- 创建开机启动项
- 创建后台常驻进程
- 擅自修改 Windows 设置

---

# 19. 开发提交原则

一次提交尽量只解决一个问题。

推荐：

```text
feat: add Event ID 100 boot history reader

feat: add registry startup provider

feat: add process boot-offset calculation

fix: distinguish boot offset from duration

refactor: extract startup provider interface

test: add boot timing parser tests
```

避免：

```text
update everything
final version
misc fixes
```

---

# 20. 文档同步

以下变化应同步更新 README：

- 项目定位变化
- Phase 完成
- 数据来源变化
- Timing 语义变化
- 架构变化
- 新增系统权限
- 新增后台行为
- 新增外部依赖

README 应始终反映：

> 当前项目真实状态。

---

# 21. 当前开发状态

当前项目处于：

```text
Phase 0 已完成
Phase 1 启动历史 CLI 初版已完成
Phase 1 轻量 GUI 原型已实现
Phase 2 Registry Run 启动项发现已实现
```

Phase 0 已经完成：

- Windows 完整启动判定；
- Event ID 100 关键字段验证；
- Fast Startup 排除规则；
- `BootRecord` v1 数据契约。

当前已有 Phase 0 检查脚本：

```powershell
.\scripts\inspect-boot-events.ps1
.\scripts\inspect-kernel-boot-types.ps1
```

当前已有 Phase 1 CLI 原型：

```powershell
.\bootlens.ps1
.\bootlens.ps1 -Count 5
.\bootlens.ps1 -Count 10 -AsJson
```

当前已有 Phase 1 GUI 原型：

```powershell
.\bootlens-gui.ps1
```

GUI 原型采用 Windows PowerShell 5.1 + WPF：

- 复用 CLI 已验证的数据采集与统计模块；
- 不引入额外运行时或第三方 UI 框架；
- 不创建后台进程、Service 或开机启动项；
- 关闭窗口后完全退出；
- 当前用于验证界面信息结构，不代表最终发布技术栈。

当前已有 Phase 2 Registry Run CLI：

```powershell
.\bootlens-startup.ps1
.\bootlens-startup.ps1 -ShowCommand
.\bootlens-startup.ps1 -AsJson
```

Registry Run Provider 当前提供：

- Current User Shared 注册表视图；
- Local Machine 32/64 位注册表视图；
- 原始命令行与安全路径解析；
- 文件存在性与 Publisher 读取；
- 稳定来源身份；
- 无法可靠解析时显示 `Unknown`。

2026-10-07 已使用本机真实注册表完成验证：发现 18 条登录启动配置，其中 13 条命令成功解析，5 条保持 `Unresolved`。

CLI 当前提供：

- 最近一次完整启动耗时；
- Main Path 与 Post Boot 分段耗时；
- 最近 N 次完整启动；
- 平均、最快和最慢启动耗时；
- Windows 原生性能退化标记；
- `BootRecord` v1 完整启动筛选。

2026-10-07 已使用本机真实事件日志完成验证：成功输出最近 10 次完整启动，并正确计算最近一次、平均、最快和最慢启动耗时。

在当前机器上读取 Diagnostics-Performance 日志需要管理员权限。CLI 不会自动提升权限；请按需在管理员 PowerShell 中运行。

当前验证记录见：

```text
docs/phase-0-data-validation.md
docs/boot-record.md
docs/startup-item.md
```

当前已经确认：

```text
Restart                          = 完整启动
shutdown /s /t 0 后开机          = 完整启动
启用 Fast Startup 的普通关机后开机 = 排除
```

当前任务：

> 验证 Startup Folder 的文件与快捷方式语义，建立下一种只读启动项来源。

---

# 22. 第一阶段建议任务

推荐按以下顺序执行。

### Task 1

读取：

```text
Microsoft-Windows-Diagnostics-Performance/Operational
```

中的：

```text
Event ID 100
```

输出最近 10 次记录。

---

### Task 2

分析 Event 100：

- BootStartTime
- BootEndTime
- BootTime
- MainPathBootTime
- BootPostBootTime
- 其他关键字段

确认其真实语义。

---

### Task 3

研究：

```text
Restart
Shutdown
Fast Startup
Sleep
Hibernate
```

分别会产生怎样的启动记录。

---

### Task 4

建立：

```text
BootRecord
```

数据模型。

---

### Task 5

做第一个 CLI 原型：

```text
bootlens
```

输出：

```text
Last Boot
Average
Fastest
Slowest
Recent Boots
```

---

### Task 6

确认 CLI 数据可靠之后，再进入 GUI 开发。

---

# 23. 长期愿景

BootLens 最终希望做到：

```text
打开软件
    ↓
立即知道：

Windows 最近启动表现如何？
    ↓
最近是否越来越慢？
    ↓
启动过程有哪些程序参与？
    ↓
这些程序什么时候启动？
    ↓
哪些项目有 Windows 明确记录的性能影响？
```

同时保持：

```text
轻量
透明
可信
无后台
低侵入
```

BootLens 不试图成为：

> 一个替用户做决定的 Windows 优化软件。

它更希望成为：

> **一个让用户真正看懂 Windows 启动过程的观察工具。**

---

# 24. 项目核心原则总结

如果未来开发过程中出现设计争议，优先按照以下顺序决策：

```text
数据可信
    ↓
语义准确
    ↓
低资源占用
    ↓
低系统侵入
    ↓
代码清晰
    ↓
易于维护
    ↓
功能丰富
```

最后一条原则：

> **不要为了分析系统性能，而成为系统性能问题的一部分。**
