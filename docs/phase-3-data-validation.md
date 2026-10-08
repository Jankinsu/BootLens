# Phase 3 进程时间线数据验证

状态：首轮只读探测、管理员权限数据验证、CLI 验收和管理员 GUI 页面数据展示已由用户确认；普通权限下权限提示和降级行为也已确认。用户已确认鼠标位于进程表格上时页面滚动正常、选中进程后完整路径可以展开，并且再次点击所选行可收起详情。

## 验证目标

在实现 Process Start Time 前，确认当前进程启动时间的可读范围、系统启动时间锚点的权限要求，以及无法读取数据时的降级行为。

## 首轮只读探测

2026-10-07，在当前普通权限会话中：

```text
Get-Process 枚举进程                 274
StartTime 非空且非零                 140
StartTime 空值或不可用               134
Get-BootLensReport 读取性能启动日志   被拒绝，需要管理员权限
Win32_OperatingSystem CIM 查询       被拒绝
```

`System.Diagnostics.Process.StartTime` 是当前本机进程的启动时间公开属性，但本机探测说明普通权限下不能假设所有进程都有可读值。不可读时间必须保留为 Unknown/Unavailable，不得用扫描时间或其他估算值填充。

`Win32_Process` 的公开 WMI/CIM 模型包含只读 `CreationDate`，可作为待验证候选；尚未完成在本机的权限、性能和完整性验证。Windows Diagnostics-Performance Event ID 100 当前由 BootLens 用于确认完整启动，但本机普通权限读取该日志失败。

## 管理员权限实测

同日用户在管理员 PowerShell 中完成验证：

```text
Win32_Process 总数 / CreationDate 可读   273 / 273
枚举耗时                                727 ms
BootKind                                Full
BootStartTimeUtc                        2026-10-07T08:35:20.7602927+00:00
复核时间线进程总数 / 时间戳可读         270 / 270
早于 BootStartTimeUtc 的进程            2
```

时间线样本中，`Secure System` 与 `Registry` 分别早于 BootStartTimeUtc 约 0.20 秒和 0.14 秒；其余最早样本从约 +1.52 秒开始（`System Idle Process` 与 `System`），之后依次可见 `smss.exe`、`csrss.exe`、`wininit.exe`、`services.exe` 和 `winlogon.exe`。这验证了时间戳与 UTC 锚点可用于构造启动相对时间，但锚点之前的小幅负偏移真实存在，不能静默截断为 0，也暂不据此判为无效数据。

后续只读核对确认这些不是时区转换误差：

```text
BootStartTimeUtc                  08:35:20.7602927Z
Secure System CreationDate       08:35:20.5610450Z   (-199.248 ms)
Registry CreationDate            08:35:20.6164080Z   (-143.885 ms)
Kernel-Boot Event 27             08:35:20.7895954Z   (+29.303 ms)
Kernel-General Event 12          08:35:20.7891917Z   (+28.899 ms)
```

因此，`BootStartTimeUtc` 是 BootLens 确认启动记录所使用的时间锚点，并非所有系统进程对象创建的绝对下界。进程时间线的偏移必须允许带符号；微小负偏移不代表进程在一次启动之前运行。

2026-10-08 用户在管理员 PowerShell 中验证 `bootlens-processes.ps1`：

```text
Boot kind                               Full
Boot start                              2026-10-08 09:51:36.767
Snapshot                                2026-10-08 10:18:48.218
Processes / timestamped / unavailable  247 / 247 / 0
Before boot anchor                      2
Secure System offset                    -0.206 s
Registry offset                         -0.150 s
System / System Idle Process offset     +1.622 s
```

CLI 成功完成真实数据展示；负偏移、完整启动类型、进程排序和可执行文件路径均符合预期。路径不可用的系统进程显示为空，不影响时间戳与偏移结果。

## 当前结论与限制

- 当前进程快照只能展示扫描时仍然存在的进程；短暂启动后退出的进程不会出现在快照中，因此这不是完整的历史进程时间线。
- 管理员权限下 `Win32_Process.CreationDate` 本机样本全部可读，耗时低于 1 秒；普通权限下读取启动日志和系统 CIM 信息会被拒绝，因此权限提示/降级仍需设计。
- 进程创建时间能够与已确认的 `BootRecord.BootStartTimeUtc` 关联计算 Boot Offset；两个样本出现小于 0.2 秒的负偏移，需在契约中保留并解释。
- 不将 `BootTime`、`MainPathBootTime` 或 `PostBootDurationMs` 当作单个进程耗时。

## GUI 人工验收结果

2026-10-08，用户提供的管理员 GUI 画面确认：

```text
运行中进程         266
时间戳可读         266
时间不可用         0
早于启动锚点       2
```

画面中进程按 Boot Offset 排列，`Secure System` 与 `Registry` 的负偏移可见；“进程时间线”页顶部样本数选择器隐藏。当前页只展示扫描时仍运行的进程，系统进程不可用路径显示为 `Unknown`。

## 普通权限观察与验收结果

2026-10-08，用户在普通权限会话启动 GUI，确认只有启动项页面显示当前用户可读取的配置；启动历史、进程时间线和启动退化页无数据，并显示管理员权限提示。这是受限事件日志和系统进程数据在普通权限下不可用时的预期降级行为。

GUI 在启动历史、进程时间线和启动退化页提供页面内状态说明，读取失败时清空旧值；全局提示说明启动项页仍可能显示可读取配置。普通权限降级、进程列表滚动和超长路径展开均已由用户确认。历史进程追踪不在本次范围。

用户随后确认以管理员权限启动 GUI 后，各个页面均正常显示数据。历史进程追踪不在本次范围。

## 官方资料

- [Process.StartTime Property](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.starttime)
- [Win32_Process class](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-process)
- [StartupTask.GetForCurrentPackageAsync](https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.startuptask.getforcurrentpackageasync)
- [StartupTaskState enum](https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.startuptaskstate)
