# StartupItem v2 数据契约

状态：Phase 2 Registry Run 与 Startup Folder 数据验证已完成，可用于统一启动项发现。

## 1. 定义

一个 `StartupItem` 表示 Windows 中一条可追溯来源的自动启动配置。

v2 支持两种来源：

```text
Registry Run
Startup Folder
```

注册表 `Run` 的触发语义是：

> 用户登录时，Windows 安排执行该命令。

它不表示该程序参与内核初始化，也不保证程序在桌面出现前执行。Windows 可能延迟执行，多个 `Run` 项之间也没有确定顺序。

## 2. v2 范围

当前实现接受：

```text
Registry Run
Current User scope
Local Machine scope
REG_SZ
REG_EXPAND_SZ
Current User Startup Folder
Common Startup Folder
Windows shortcuts (.lnk)
direct files
```

当前暂不包含：

```text
RunOnce
Scheduled Tasks
Windows Services
UWP Startup Tasks
Shell Extensions
```

`RunOnce` 是一次性安装或配置机制，不应与长期启动项混在同一批数据中。

## 3. 字段定义

| 字段 | 类型 | 必需 | 语义 |
|---|---|---:|---|
| `SchemaVersion` | Integer | 是 | 数据契约版本，当前固定为 `2` |
| `Name` | String | 是 | 用于展示的启动项名称 |
| `Source` | Enum | 是 | `RegistryRun` 或 `StartupFolder` |
| `Trigger` | Enum | 是 | 当前固定为 `UserLogon` |
| `Scope` | Enum | 是 | `CurrentUser` 或 `LocalMachine` |
| `CommandLineRaw` | String | 条件 | Registry Run 保存的原始命令行；Startup Folder 不伪造该字段 |
| `CommandLineExpanded` | String | 否 | 对 Registry `REG_EXPAND_SZ` 安全展开环境变量后的命令行 |
| `ExecutablePath` | String | 否 | 仅在能够可靠解析时填写的可执行文件路径 |
| `Arguments` | String | 否 | 仅在能够与可执行文件可靠分离时填写的参数 |
| `CommandParseStatus` | Enum | 是 | `Resolved` 或 `Unresolved` |
| `ExecutableExists` | Boolean | 否 | 解析出路径后，该文件在扫描时是否存在 |
| `Publisher` | String | 否 | 能够读取文件版本信息时的发布者；否则为空 |
| `EnabledState` | Enum | 是 | `Enabled`、`Disabled` 或 `Unknown` |
| `RegistryHive` | Enum | 条件 | Registry Run 的 `CurrentUser` 或 `LocalMachine` |
| `RegistryView` | Enum | 条件 | Registry Run 的 `Shared`、`Registry64` 或 `Registry32` |
| `RegistryKeyPath` | String | 条件 | Registry Run 中不包含 Hive 的键路径 |
| `RegistryValueName` | String | 条件 | Registry Run 的原始值名称 |
| `RegistryValueKind` | Enum | 条件 | Registry Run 的 `String` 或 `ExpandString` |
| `StartupFolderKind` | Enum | 条件 | `UserStartup` 或 `CommonStartup` |
| `StartupFolderPath` | String | 条件 | Startup Folder 的已知文件夹路径 |
| `StartupEntryPath` | String | 条件 | 启动文件夹条目的完整路径 |
| `StartupEntryType` | Enum | 条件 | `Shortcut` 或 `File` |
| `ShortcutTargetPath` | String | 否 | `.lnk` 保存的 TargetPath |
| `ShortcutArguments` | String | 否 | `.lnk` 保存的 Arguments |
| `ShortcutWorkingPath` | String | 否 | `.lnk` 保存的 WorkingDirectory |
| `SourceIdentity` | String | 是 | 用于标识来源记录的稳定复合键，不等同于程序身份 |

所有 Provider 输出相同的属性集合。不适用于当前 Source 的来源专属字段使用空值，不用空字符串或伪造值填充。

核心模型使用空值表达“没有可靠数据”。展示层可将空值显示为：

```text
Unknown
```

## 4. 命令行语义

对于 Registry Run，`CommandLineRaw` 是事实来源，必须始终保留。

本机样本中同时存在：

```text
"D:\steam\steam.exe" -silent
C:\Program Files\Microsoft OneDrive\...\OneDrive.Sync.Service.exe
D:\NDM\Neat Download Manager\NeatDM.exe -autostart
%windir%\system32\SecurityHealthSystray.exe
```

因此不能使用“按第一个空格切分”的方式提取可执行文件，否则会破坏包含空格但未加引号的路径。

第一版解析规则：

1. 原始命令始终写入 `CommandLineRaw`；
2. `REG_EXPAND_SZ` 先保留原值，再生成 `CommandLineExpanded`；
3. 带引号的可执行文件路径可以按引号边界解析；
4. 未加引号的路径只有在边界可以可靠确认时才解析；
5. 无法可靠确认时，`ExecutablePath` 和 `Arguments` 为空；
6. 解析失败不影响 `StartupItem` 本身进入结果集；
7. 注册表内容按不可信输入处理，扫描过程中绝不执行命令。

对于 Startup Folder：

1. `.lnk` 的 TargetPath、Arguments 和 WorkingDirectory 分别保留；
2. 不把快捷方式字段重新拼接成伪造的 `CommandLineRaw`；
3. 直接文件使用自身完整路径作为 `ExecutablePath`；
4. `desktop.ini` 和子目录不是启动程序，予以排除；
5. 无法解析或 TargetPath 为空的快捷方式仍可保留来源，但状态为 `Unresolved`；
6. UNC 目标可以记录，但扫描时不主动访问网络检查文件或 Publisher。

## 5. 启用状态

注册表 `Run` 值存在，只能证明该命令已经注册为登录启动项。

它不能单独证明：

```text
Windows 当前一定会执行它
用户没有在任务管理器中禁用它
程序本次登录已经实际运行
```

本机存在：

```text
Explorer\StartupApproved\Run
```

其中保存了任务管理器使用的二进制状态，但目前没有找到微软公开、稳定的数据格式说明。BootLens v2 不根据非公开字节值猜测启用状态。

因此当前 Registry Run 与 Startup Folder Provider 均使用：

```text
EnabledState = Unknown
```

后续只有在完成受控实验并确认兼容边界后，才能将其升级为 `Enabled` 或 `Disabled`。

## 6. 32 位与 64 位注册表视图

64 位 Windows 对注册表采用 Shared 与 Redirected 两种行为。

当前系统和微软文档均表明：

- `HKEY_CURRENT_USER\Software` 是 Shared，只读取一次并标记为 `RegistryView = Shared`；
- `HKEY_LOCAL_MACHINE\Software` 是 Redirected，需要分别读取 `Registry64` 和 `Registry32`；
- 不直接访问保留的物理路径 `Wow6432Node`，而是使用 Registry View API；
- 不因为名称或命令相同就合并不同 Scope 或不同 Registry View 的记录。

这样可以避免将 HKCU 的同一批记录错误统计两次，同时保留 HKLM 中真正独立的 32/64 位注册项。

## 7. 接受条件

### 7.1 Registry Run

一条注册表值必须同时满足：

1. 位于 v2 支持的 `Run` 键；
2. 值名称非空；
3. 值类型为 `REG_SZ` 或 `REG_EXPAND_SZ`；
4. 原始命令行非空；
5. Scope、Hive 和 Registry View 能够确定；
6. 来源身份可以稳定构造。

### 7.2 Startup Folder

一条文件夹记录必须同时满足：

1. 直接位于 Current User Startup 或 Common Startup 已知文件夹；
2. 是文件而不是子目录；
3. 文件名不是 `desktop.ini`；
4. 条目路径和 Scope 能够确定；
5. 来源身份可以稳定构造。

快捷方式目标无法解析时，不排除来源记录，只将 `CommandParseStatus` 设为 `Unresolved`。

不满足条件时：

```text
排除记录
记录诊断信息
不执行命令
不生成猜测字段
```

## 8. SourceIdentity

当前版本采用来源位置构造身份：

```text
RegistryRun|<Hive>|<View>|<KeyPath>|<EscapedValueName>
StartupFolder|<Scope>|<EscapedEntryPath>
```

`RegistryValueName` 在复合键中使用 URI 转义，避免名称本身含有分隔符时产生碰撞。

示例：

```text
RegistryRun|CurrentUser|Shared|Software\Microsoft\Windows\CurrentVersion\Run|Steam
StartupFolder|LocalMachine|C%3A%5CProgramData%5CMicrosoft%5CWindows%5CStart%20Menu%5CPrograms%5CStartup%5CTailscale.lnk
```

`SourceIdentity` 只表示同一个配置来源，不表示两个名称不同的记录一定属于不同程序。

跨来源程序归并属于后续的 `StartupDiscoveryService`，不在 Provider 中提前猜测。

## 9. 示例

```json
{
  "SchemaVersion": 2,
  "Name": "Steam",
  "Source": "RegistryRun",
  "Trigger": "UserLogon",
  "Scope": "CurrentUser",
  "CommandLineRaw": "\"D:\\steam\\steam.exe\" -silent",
  "CommandLineExpanded": null,
  "ExecutablePath": "D:\\steam\\steam.exe",
  "Arguments": "-silent",
  "CommandParseStatus": "Resolved",
  "ExecutableExists": true,
  "Publisher": "Valve Corporation",
  "EnabledState": "Unknown",
  "RegistryHive": "CurrentUser",
  "RegistryView": "Shared",
  "RegistryKeyPath": "Software\\Microsoft\\Windows\\CurrentVersion\\Run",
  "RegistryValueName": "Steam",
  "RegistryValueKind": "String",
  "StartupFolderKind": null,
  "StartupFolderPath": null,
  "StartupEntryPath": null,
  "StartupEntryType": null,
  "ShortcutTargetPath": null,
  "ShortcutArguments": null,
  "ShortcutWorkingPath": null,
  "SourceIdentity": "RegistryRun|CurrentUser|Shared|Software\\Microsoft\\Windows\\CurrentVersion\\Run|Steam"
}
```

示例中的 `Publisher` 只有在实际文件元数据读取成功时才填写。

Startup Folder 示例：

```json
{
  "SchemaVersion": 2,
  "Name": "Tailscale",
  "Source": "StartupFolder",
  "Trigger": "UserLogon",
  "Scope": "LocalMachine",
  "CommandLineRaw": null,
  "CommandLineExpanded": null,
  "ExecutablePath": "C:\\Program Files\\Tailscale\\tailscale-ipn.exe",
  "Arguments": null,
  "CommandParseStatus": "Resolved",
  "ExecutableExists": true,
  "Publisher": "Tailscale Inc.",
  "EnabledState": "Unknown",
  "RegistryHive": null,
  "RegistryView": null,
  "RegistryKeyPath": null,
  "RegistryValueName": null,
  "RegistryValueKind": null,
  "StartupFolderKind": "CommonStartup",
  "StartupFolderPath": "C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\Startup",
  "StartupEntryPath": "C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\Tailscale.lnk",
  "StartupEntryType": "Shortcut",
  "ShortcutTargetPath": "C:\\Program Files\\Tailscale\\tailscale-ipn.exe",
  "ShortcutArguments": null,
  "ShortcutWorkingPath": "C:\\Program Files\\Tailscale\\",
  "SourceIdentity": "StartupFolder|LocalMachine|C%3A%5CProgramData%5CMicrosoft%5CWindows%5CStart%20Menu%5CPrograms%5CStartup%5CTailscale.lnk"
}
```

## 10. 不进入 v2 的字段

### Startup Impact

`Run` 注册表项没有提供启动耗时。不能根据存在于 `Run` 键就生成影响时间。

### Boot Offset

注册表只描述配置，不描述进程本次何时启动。Boot Offset 属于 Phase 3。

### Essential

Windows 没有在 `Run` 项中提供“系统必需”标记。第一版不猜测该程序是否必要。

### Disable Action

Phase 2 仍然只读，不修改、移动或删除任何注册表值。

## 11. 本机验证结果

2026-10-07 只读检查得到：

```text
Current User / Shared      15 条
Local Machine / 64-bit     2 条
Local Machine / 32-bit     1 条
Current User Startup       1 条有效快捷方式
Common Startup             1 条有效快捷方式
统一结果                    20 条
```

样本确认：

- HKCU 32/64 逻辑视图会看到相同的 Shared 数据；
- HKLM 32/64 视图包含不同记录；
- `String` 与 `ExpandString` 均实际存在；
- 命令行同时存在带引号、未带引号、带参数和环境变量形式；
- `StartupApproved` 中存在已不在 `Run` 键内的历史名称，不能将其单独当作启动项来源；
- 注册表发现数量不能与 Event ID 100 的 `BootNumStartupApps` 直接比较，两者语义和统计范围不同。
- 两个 Startup Folder 均包含系统文件 `desktop.ini`，它不是启动程序；
- 当前用户 Startup 中的 OneNote 快捷方式包含 TargetPath 和 Arguments；
- Common Startup 中的 Tailscale 快捷方式包含 TargetPath 和 WorkingDirectory；
- 两个快捷方式目标均可解析且文件存在。

## 12. 参考资料

- [Run and RunOnce Registry Keys](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys)
- [Registry Redirector](https://learn.microsoft.com/en-us/windows/win32/winprog64/registry-redirector)
- [Registry Keys Affected by WOW64](https://learn.microsoft.com/en-us/windows/win32/winprog64/shared-registry-keys)
- [KNOWNFOLDERID](https://learn.microsoft.com/en-us/windows/win32/shell/knownfolderid)
- [Create a shortcut with Windows Script Host](https://learn.microsoft.com/en-us/troubleshoot/windows-client/admin-development/create-desktop-shortcut-with-wsh)

## 13. 版本变化

### v2

- 增加 `StartupFolder` Source；
- 增加 Startup Folder 与快捷方式来源字段；
- 所有 Provider 输出相同属性集合；
- SchemaVersion 从 `1` 更新为 `2`。

### v1

- 建立 Registry Run 的第一版字段和解析规则。
