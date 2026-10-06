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
