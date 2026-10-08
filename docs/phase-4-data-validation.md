# Phase 4 启动性能关联：数据验证

状态：GUI 展示、管理员权限下各页面数据读取及普通权限下 Event 101 权限提示均已由用户确认；PowerShell 测试套件已通过。启动退化详情再次点击收起的交互待验收。已取得最近 20 条摘要及代表性原始样本；Event ID 101 的 `StartTime` 在 3 次启动中与 Event ID 100 `BootStartTime` 精确匹配。`DegradationTime` 的计算公式及更广目标覆盖仍未验证，因此只展示原始字段，不派生影响时间。

## 验证目标

在实现任何启动项关联或影响分析之前，先验证 Windows Diagnostics-Performance Event ID 101 的真实记录内容、字段含义、时间语义和本机覆盖情况。Event 101 只能作为 Windows 明确记录的性能退化证据；不得仅凭进程启动偏移推断某个程序造成了启动延迟。

## 当前探测状态

2026-10-08 首次在非提升权限会话读取 `Microsoft-Windows-Diagnostics-Performance/Operational` 时被拒绝。用户随后在管理员 PowerShell 中成功运行探测脚本，并提供了一条 2026-10-06 的 Event ID 101 样本截图。

只读探测脚本：

```powershell
.\scripts\inspect-degradation-events.ps1
```

可用 `-MaxEvents` 调整读取的最新 Event ID 101 数量（1–100，默认 20）。脚本输出事件元数据、Windows 本地化描述及全部具名 EventData 字段的 JSON，不修改日志或系统设置。需在管理员 PowerShell 中运行。

使用 `-Summary` 可输出便于检查的关键字段表；使用 `-RecordId <编号>` 可只读取一条事件的完整 JSON，例如：

```powershell
.\scripts\inspect-degradation-events.ps1 -RecordId 1021
```

## 2026-10-06：首条已检查样本

用户提供的 Event ID 101 样本（RecordId 1093）：

```text
TimeCreated       2026-10-06 17:33:38.9268643 +08:00
EventData.StartTime 2026-10-06 09:31:55.0534537Z
Name              MathworksServiceHost.exe
FriendlyName      空
Version           空
TotalTime         6031 ms
DegradationTime   1031 ms
Path              C:\Users\SJQ\AppData\Local\MathWorks\ServiceHost\v2026.9.0.2\bin\win64\MathworksServiceHost.exe
ProductName       空
CompanyName       空
```

该 `StartTime` 转换为本地时间约为 `17:31:55.053 +08:00`，与同次 Restart 实验的 Event ID 100（RecordId 1092）及已记录的 `17:31:55` 完整启动时间相符。Event ID 101 的 `TimeCreated` 比 `StartTime` 晚约 103.873 秒，因此不能用事件写入时间直接作为应用事件发生时间或启动关联键；内部 `StartTime` 是当前样本更合适的候选关联字段。

Windows 描述与具名字段均显示 `TotalTime=6031 ms`、`DegradationTime=1031 ms`。两者必须分别保留；不能将总耗时 6.031 秒解释为启动被拖慢 6.031 秒。该样本提供 Windows 明确记录的 1.031 秒退化值，但单条样本尚不能证明该值与 BootLens 的启动总耗时可直接相加，也不能据此证明单个组件是唯一原因。

此样本具备可用于启动项关联的 `Name` 与 `Path`，但 `FriendlyName`、`Version`、`ProductName`、`CompanyName` 均为空。单条记录只证明存在可尝试的路径关联，尚未验证路径变化、同名程序、多目标/服务映射或缺失路径等边界。

## 2026-10-08：最近 20 条摘要

用户提供的管理员模式 `-Summary` 输出包含最近 20 条 Event ID 101，时间范围为 2026-06-17 至 2026-10-06。摘要中可见多个不同目标共享相同 `StartTimeUtc` 与 `TimeCreated`，例如 RecordId 1067/1066、1064/1063、1047–1044、1013–1011、981/980。这说明同一次启动可以产生多条退化事件；应先按 `StartTime` 归到启动，再保留每条独立事件，不能假定一条启动最多只有一条 Event 101。

另发现需要核对字段语义的异常样本：

```text
RecordId 1021  explorer.exe  TotalTime=5106 ms  DegradationTime=5871 ms
```

用户随后提供了此记录的完整 JSON。原始具名字段和本地化消息均确认：

```text
RecordId          1021
TimeCreated       2026-07-25 23:01:28.9701515 +08:00
EventData.StartTime 2026-07-25 14:59:29.7561980Z
Name              explorer.exe
FriendlyName      Windows 资源管理器
Version           10.0.22621.6133 (WinBuild.160101.0800)
TotalTime         5106 ms
DegradationTime   5871 ms
Path              C:\Windows\explorer.exe
ProductName       Microsoft Windows Operating System
CompanyName       Microsoft Corporation
```

`StartTime` 换算为本地时间约为 `22:59:29.756 +08:00`，比事件日志 `TimeCreated` 早约 119.214 秒。此样本再次说明二者语义不同；`StartTime` 是关联启动实例的候选，仍需与 Event ID 100 的 `BootStartTime` 做更多样本交叉验证。

Windows 描述称此应用启动时间超过正常时间并造成启动过程性能退化；但该样本的 `DegradationTime` 大于 `TotalTime`。本机 Provider 元数据确认 Event ID 101 是版本 1 的 Warning/Boot_Degradation 事件，但未给出这两个耗时字段之间的计算关系。因此当前只能将二者视为 Windows 分别报告的毫秒值，不假设大小关系，不相减，也不直接与 Event ID 100 的启动时长相加。该值表明的是 Windows 的退化诊断记录，并非已证明的单组件因果时间。

## 2026-10-08：Event 101 与 Event 100 时间锚点交叉验证

用户按日期查询到同次启动的 Event ID 100（RecordId 1019），并与 Event ID 101（RecordId 1021）原始样本比较：

```text
Event 100 RecordId        1019
Event 100 TimeCreated     2026-07-25 23:01:28 (+08:00)
Event 100 BootStartTime   2026-07-25T14:59:29.7561980Z
Event 100 BootTime        42646 ms

Event 101 RecordId        1021
Event 101 TimeCreated     2026-07-25 23:01:28.9701515 (+08:00)
Event 101 StartTime       2026-07-25T14:59:29.7561980Z
Event 101 TotalTime       5106 ms
Event 101 DegradationTime 5871 ms
```

此样本中，Event 101 `StartTime` 与 Event 100 `BootStartTime` 精确相等；两类事件的 `TimeCreated` 则都在启动后约 119 秒出现并落在同一秒。该证据支持将 `StartTime` 作为启动实例关联键，而不是把它解释成单个应用的进程创建时间，也不应以 `TimeCreated` 作为启动锚点。随后对另外两次启动完成同样的精确匹配，记录如下。

## 2026-10-08：额外两次启动锚点复核

用户按日期检索到的 Event ID 100：

```text
Event 100 RecordId 1065  BootStartTime 2026-09-04T07:29:54.7629821Z  BootTime 44781 ms
Event 100 RecordId 1062  BootStartTime 2026-09-03T02:27:46.9593321Z  BootTime 66397 ms
```

两次启动各自对应的 Event ID 101 摘要行具有完全相同的 `StartTimeUtc`：

```text
2026-09-04: Event 101 RecordId 1067/1066 -> 2026-09-04T07:29:54.7629821Z
2026-09-03: Event 101 RecordId 1064/1063 -> 2026-09-03T02:27:46.9593321Z
```

至此，3 次不同日期的启动样本均验证 Event 101 `StartTime` 与 Event 100 `BootStartTime` 精确相等；同一启动可关联多条 Event 101。Phase 4 当前可采用此精确时间戳作为候选启动实例关联键，并保留“多条退化事件对一条启动记录”的关系。若未来遇到不相等或缺失值，应标记未匹配并保留数据，不使用 `TimeCreated` 静默兜底。

同时，Event 100 的 `BootTime=42646 ms`、Event 101 的 `TotalTime=5106 ms`、`DegradationTime=5871 ms` 是不同事件中的指标。尤其 `DegradationTime` 大于该事件 `TotalTime`，证实它们不能简单视为可加总或有大小约束的启动时长分项。

## 2026-10-08：svchost.exe 目标归因边界

用户提供了 Event ID 101 RecordId 1045 的完整 JSON：

```text
TimeCreated        2026-08-11T10:22:18.7461248+08:00
StartTime          2026-08-11T02:20:32.9577826Z
Name               svchost.exe
FriendlyName       Windows 服务主进程
Version            10.0.22621.6133 (WinBuild.160101.0800)
TotalTime          7463 ms
DegradationTime    3669 ms
Path               C:\Windows\System32\svchost.exe
ProductName        Microsoft Windows Operating System
CompanyName        Microsoft Corporation
```

该记录只能确认 Windows 服务宿主程序及其通用路径。事件中没有服务名、服务组、进程 ID 或命令行，无法确定具体由哪个服务产生这条退化记录。多个服务可以共享同一 `svchost.exe` 路径，因此只按路径匹配启动服务会造成多对一歧义；当前应止于“Windows 服务宿主进程”级别，不能归因到某个服务。

## 2026-10-08：MathWorks 启动项路径候选比对

将 Event ID 101 RecordId 1093 的历史事件路径与当前 BootLens 启动项发现结果按 Windows 不区分大小写的路径比较：

```text
Event 101 Path:
C:\Users\SJQ\AppData\Local\MathWorks\ServiceHost\v2026.9.0.2\bin\win64\MathworksServiceHost.exe

当前启动项候选：
Name              Mathworks Service Host
Source            RegistryRun
Scope             CurrentUser
ExecutablePath    C:\Users\SJQ\AppData\Local\MathWorks\ServiceHost\v2026.10.1.1\bin\win64\MathWorksServiceHost.exe
CommandLineRaw    "...MathWorksServiceHost.exe" service --realm-id companion@prod@production
CommandParseStatus Resolved
EnabledState      Unknown
```

本次非管理员只读枚举发现 104 条项目；计划任务来源因权限被拒绝。MathWorks 条目来自可访问的 Current User Registry Run 数据。事件与当前启动项名称/产品目录/可执行文件名相符，但完整路径不相等，差异在版本目录 `v2026.9.0.2` 与 `v2026.10.1.1`（文件名大小写差异在 Windows 上不构成路径差异）。两个版本路径当前都存在。

结论：这是同一应用家族的合理候选关联，不是精确路径匹配，也不能证明当前 Registry Run 命令就是 2026-10-06 启动时的历史配置，更不能仅据此证明该启动项导致 Event 101 退化。当前只读启动项发现描述现在的配置，Event 101 描述过去的事件；应用升级后版本路径可以变化。若未来需要展示关联，应区分 `ExactPath` 与 `Name/InstallRoot candidate` 等置信度，并保留历史配置未知这一限制。

## 已确认的数据处理规则

| 维度 | 规则草案 | 证据与限制 |
|---|---|---|
| 启动实例关联 | 将 Event 101 `StartTime` 与 Event 100 `BootStartTimeUtc` 转为 UTC 时间瞬间后精确匹配；一条启动允许关联多条 Event 101。 | 3 次不同启动精确相等；不匹配或缺失时保留 Unmatched，不以 `TimeCreated` 兜底。 |
| 耗时字段 | 独立保存 `TotalTimeMs` 与 `DegradationTimeMs`，注明来源为 Windows Diagnostics-Performance；不相减、不假设大小约束、不加到 `BootDurationMs`。 | RecordId 1021 出现 `TotalTime=5106`、`DegradationTime=5871`；本机 Provider 元数据未给出计算公式。 |
| 精确路径 | Windows 路径按不区分大小写规范化后相等，记录为路径精确匹配。 | 只表示事件路径与被比较的启动项快照路径一致；若启动项快照不是事件当时采集，不能视为历史配置确证。 |
| 应用家族候选 | 名称/产品目录/可执行文件名相符但完整路径不同，标为 Candidate，不升级成 ExactPath。 | MathWorks 事件和当前 Registry Run 项版本目录不同；事件时的历史注册表配置未知。 |
| 通用宿主 | 如 `svchost.exe` 缺少服务名、服务组、PID、命令行时，只归到宿主程序级。 | 不能推断具体服务；同一映像路径可能对应多项服务。 |
| 未匹配 | 无可靠路径/身份对应时保留 Unmatched/Unknown，不猜测。 | Event 101 不包含可通用关联到启动项的 PID；不能仅凭名称制造精确关系。 |
| 因果措辞 | 描述为“Windows 记录的启动退化事件/退化值”，不直接写成“该启动项导致启动慢 X 秒”。 | 当前数据只给 Windows 的诊断结论和目标元数据，未证明对 Event 100 总耗时的可加贡献。 |

用户已确认以上范围。公开资料和当前实测都未确认 `DegradationTime` 的计算定义；产品保持原始字段语义，不衍生“影响秒数”或排名。

## 后续验证项

1. 用户提供的管理员 GUI 画面显示 30 条 Event 101、21 条关联完整启动、5 条路径精确匹配；列表可见 App family candidate、Exact path、Generic host 与 Unmatched 等级，原始退化值正常显示。
2. 用户提供的普通权限 GUI 画面确认 Event 101 页面显示管理员权限提示、计数为不可用、列表为空；这是预期降级状态。
3. `DegradationTime` 的计算公式及更广目标覆盖仍未知；不据此派生应用延迟或排名。GUI 技术选型/切页性能问题仍单独暂缓。
