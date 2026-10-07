# Phase 0 数据验证记录

本文档只记录已经观察到的事实。尚未完成验证的字段语义不在此处下结论。

## 2026-10-06：Event ID 100 初次访问

目标日志：

```text
Microsoft-Windows-Diagnostics-Performance/Operational
```

目标事件：

```text
Event ID 100
```

当前观察：

- 普通用户权限执行 `Get-WinEvent -ListLog` 时，Windows 返回访问被拒绝；
- 管理员 PowerShell 可以读取并导出 Event ID 100；
- 这也意味着“读取 Event ID 100 是否必须提升权限”需要作为 Phase 0 的兼容性问题继续验证。

检查命令：

```powershell
.\scripts\inspect-boot-events.ps1
```

如需保留最近 10 条事件的原始 XML：

```powershell
.\scripts\inspect-boot-events.ps1 `
    -MaxEvents 10 `
    -ExportRawXmlDirectory .\artifacts\event-100 `
    -ExportJsonPath .\artifacts\event-100.json
```

`artifacts/` 已被 Git 忽略，避免将机器相关的原始事件数据提交到仓库。

读取 Kernel-Boot Event ID 27 的原始启动类型代码：

```powershell
.\scripts\inspect-kernel-boot-types.ps1 -MaxEvents 20
```

## 2026-10-06：首批 10 条 Event ID 100

已成功读取最近 10 条记录。样本中的 `BootTime` 数据如下：

```text
Last       29.669 s
Average    38.795 s
Fastest    26.526 s
Slowest    66.397 s
```

### 已确认

- 本机事件提供者清单将 Event ID 100 的 `BootTime` 显示为 `Boot Duration`；
- 10 条样本全部满足：

  ```text
  BootTime = MainPathBootTime + BootPostBootTime
  ```

- `BootEndTime - BootStartTime` 与 `BootTime` 明显不同，不能用两个时间戳相减代替 `BootTime`；
- 10 条 Event ID 100 均能在相同启动时间附近找到 `Microsoft-Windows-Kernel-Boot` Event ID 27；
- 这些 Event ID 27 的原始 `BootType` 均为 `0x0`；
- 当前系统启用了 Fast Startup，但最近一次完整启动发生在 2026-09-05，当前连续运行时间约 31 天。

### 暂定解释

- `BootTime` 是 Phase 1 启动历史的主要候选值；
- `MainPathBootTime` 表示主启动路径，微软文档将对应指标描述为从 BIOS 初始化结束到 Windows UI 可见，且不包含 Post On/Off 阶段；
- `BootPostBootTime` 是主启动路径之后的阶段，并参与组成 `BootTime`。

### 尚未确认

- Event ID 27 中 `BootType = 0x0` 的数值映射仍需通过受控的 Restart、完整关机、Fast Startup 和 Hibernate 实验确认；
- 在该映射确认前，不将 `0x0` 硬编码为正式的 `FullBoot` 枚举；
- `BootStartTime`、`BootEndTime` 与 `BootTime` 为什么不满足直接相减关系，仍需继续查证；
- 普通用户是否存在不提升权限即可读取同等数据的稳定方案，仍需验证。

## 参考资料

- [Main Path Boot Duration & Main Path Resume Duration](https://learn.microsoft.com/windows-hardware/test/assessments/main-path-boot-duration-and-main-path-resume-duration)
- [Fast startup causes hibernation or shutdown to fail](https://learn.microsoft.com/troubleshoot/windows-client/setup-upgrade-and-drivers/fast-startup-causes-system-hibernation-shutdown-fail)
- [System power states](https://learn.microsoft.com/windows/win32/power/system-power-states)

## 2026-10-06：Restart 受控实验

本次通过 Windows Restart 产生一次新的完整启动记录。

关联事件：

```text
Diagnostics-Performance Event ID 100  RecordId 1092
Kernel-Boot Event ID 27               RecordId 212724
Kernel-Boot BootType                  0x0
```

Event ID 100 数据：

```text
BootTime               36.743 s
MainPathBootTime       13.043 s
BootPostBootTime       23.700 s
BootStartTime 到
BootEndTime             101.000 s
未计入 BootTime 的差值   64.257 s
UserLogonWaitDuration    1.126 s
BootIsDegradation        false
BootIsRebootAfterInstall false
```

本次实验再次满足：

```text
BootTime = MainPathBootTime + BootPostBootTime
```

当前结论：

- Windows Restart 对应的 Kernel-Boot `BootType` 为 `0x0`；
- Restart 可以作为 BootLens 的完整启动记录；
- `BootStartTime` 到 `BootEndTime` 的自然时间跨度不是启动耗时；
- 本次约 64 秒的差值未进入 `BootTime`，与等待用户登录的时间特征一致；
- `UserLogonWaitDuration` 仅为 1.126 秒，不能直接解释为用户停留在登录界面的时间。

仍需通过一次 `shutdown /s /t 0` 完整关机实验，确认完整关机后启动是否同样对应 `BootType = 0x0`。

## 2026-10-07：关机后开机实验

用户完成一次关机后重新开机，但系统没有产生新的完整启动记录。

观察结果：

```text
最近的 Kernel-General Event ID 12   2026-10-06 17:31:55
最近的 Kernel-Boot Event ID 27      2026-10-06 17:31:55
当前系统运行时间起点                 2026-10-06 17:31:54
HiberbootEnabled                    1
```

当前结论：

- 本次关机后开机没有重新启动 Windows 内核；
- 当前系统已启用 Fast Startup；
- 此类启动不能计入 BootLens 的完整启动历史；
- 系统运行时间和 Kernel-Boot 事件可以用于识别并排除此类记录；
- 仍需明确执行 `shutdown /s /t 0`，完成真正的完整关机实验。

## 2026-10-07：`shutdown /s /t 0` 完整关机实验

使用以下命令完成关机并手动重新开机：

```powershell
shutdown /s /t 0
```

本次启动产生了新的内核启动记录：

```text
Kernel-General Event ID 12   RecordId 212988
Kernel-Boot Event ID 27      RecordId 212995
Kernel-Boot BootType         0x0
Diagnostics Event ID 100     RecordId 1096
```

Event ID 100 数据：

```text
BootTime               32.865 s
MainPathBootTime        9.265 s
BootPostBootTime       23.600 s
BootStartTime 到
BootEndTime            104.000 s
未计入 BootTime 的差值  71.135 s
UserLogonWaitDuration   6.121 s
BootNumStartupApps      14
BootIsDegradation       false
BootIsRebootAfterInstall false
```

本次实验仍满足：

```text
BootTime = MainPathBootTime + BootPostBootTime
```

与 2026-10-06 Restart 实验对比：

```text
                         完整关机启动    Restart      差值
BootTime                    32.865 s     36.743 s   -3.878 s
MainPathBootTime             9.265 s     13.043 s   -3.778 s
BootPostBootTime            23.600 s     23.700 s   -0.100 s
BootNumStartupApps              14           16          -2
```

### 完整启动判定结论

当前机器上的三次受控实验已经形成一致证据：

- Windows Restart 会重新初始化内核，产生新的 Event ID 12、Event ID 27 和 Event ID 100；
- `shutdown /s /t 0` 后开机会重新初始化内核，并产生同样的一组新事件；
- 两种完整启动的 Kernel-Boot `BootType` 均为 `0x0`；
- 启用 Fast Startup 的普通关机后开机不会产生新的内核启动记录；
- BootLens 第一版可以通过“新的 Kernel-General Event ID 12 + Kernel-Boot Event ID 27 `BootType = 0x0`”确认完整启动；
- 无法确认启动类型或没有对应内核启动事件的 Event ID 100 不应进入完整启动统计。

至此，Phase 0 中“什么算一次完整启动”的定义已经稳定，可以开始建立最小 `BootRecord` 数据模型。

## 2026-10-07：日志关联窗口

对 12 条已确认的完整启动样本进行关联验证：

```text
Event ID 100 BootStartTime
        ↕
Kernel-Boot Event ID 27 TimeCreated
```

观测到的绝对时间差为：

```text
最小值  28.490 ms
最大值  31.049 ms
```

因此 `BootRecord` v1 使用 ±1 秒的保守关联窗口。超出窗口或出现多个匹配时排除记录，不进行猜测。
