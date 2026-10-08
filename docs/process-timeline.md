# Process Timeline v1 数据契约

状态：只读 CLI 与 GUI 页面、管理员 GUI 数据展示、普通权限下的权限提示、鼠标位于进程表格上时的页面滚动，以及选中行完整路径展开均已由用户确认；再次点击收起详情待验收。

## 1. 定义与范围

`ProcessTimelineReport` 表示某次扫描时仍在运行的进程相对于最近一次已确认完整启动的时间快照。它不是 ETW 采集的历史进程记录；进程若已退出，就不会出现在本次结果中。

Provider 使用 Windows `Win32_Process` 的只读 `CreationDate`。本机管理员权限样本中 270/270 条时间戳可读，枚举耗时约 727 ms（另一次相邻采样的进程总数为 273）。

Boot Offset 定义为：

```text
BootOffsetMs = Process.CreationTimeUtc - BootRecord.BootStartTimeUtc
```

偏移使用带符号整数毫秒，按最接近毫秒取整；负值保留，不归零。`BootStartTimeUtc` 是 BootLens 关联完整启动记录的时间锚点，不代表所有系统进程对象创建的绝对下界。

## 2. 报告字段

| 字段 | 类型 | 必需 | 语义 |
|---|---|---:|---|
| `SchemaVersion` | Integer | 是 | 固定为 `1` |
| `Source` | Enum | 是 | 固定为 `Win32ProcessCreationDate` |
| `SnapshotTimeUtc` | UTC Timestamp | 是 | 本次扫描时间 |
| `BootStartTimeUtc` | UTC Timestamp | 是 | 最近一次确认完整启动的锚点 |
| `BootKind` | Enum | 是 | 固定为 `Full` |
| `Scope` | Enum | 是 | 固定为 `CurrentRunningProcesses` |
| `ProcessCount` | Integer | 是 | 本次进程快照条数 |
| `TimestampedCount` | Integer | 是 | 成功取得创建时间的条数 |
| `UnavailableCount` | Integer | 是 | 创建时间不可用的条数 |
| `NegativeOffsetCount` | Integer | 是 | 负偏移条数 |
| `Processes` | Array | 是 | 按 Boot Offset 升序；无时间戳记录排在最后 |

## 3. 进程记录字段

| 字段 | 类型 | 必需 | 语义 |
|---|---|---:|---|
| `SchemaVersion` | Integer | 是 | 固定为 `1` |
| `Source` | Enum | 是 | 固定为 `Win32ProcessCreationDate` |
| `SourceIdentity` | String | 是 | 进程 ID 与创建时间组成；时间不可用时追加快照时间，避免 PID 复用造成碰撞 |
| `Name` | String | 是 | 进程名；缺失时为 `Unknown` |
| `ProcessId` | Integer | 是 | 当前快照中的 PID |
| `ParentProcessId` | Integer | 否 | 可用时的父进程 PID |
| `ExecutablePath` | String | 否 | Windows 返回路径；不可用时为 null，不主动解析或探测 |
| `CreationTimeUtc` | UTC Timestamp | 否 | `Win32_Process.CreationDate` 转换后的 UTC 创建时间 |
| `BootStartTimeUtc` | UTC Timestamp | 是 | 关联的完整启动锚点 |
| `BootKind` | Enum | 是 | 固定为 `Full` |
| `BootOffsetMs` | Signed Integer | 否 | 创建时间减启动锚点；创建时间不可用时为 null |
| `CreationTimeStatus` | Enum | 是 | `Available` 或 `Unavailable` |

不采集进程命令行，以避免在首版时间线中暴露不必要的命令参数或敏感信息。

## 4. 权限与失败语义

- 读取已确认 `BootRecord` 和完整进程快照需要管理员权限；失败时 CLI 给出管理员权限提示，不静默返回空列表。
- 单条进程没有有效 `CreationDate` 时保留该进程记录，`CreationTimeStatus` 为 `Unavailable`，时间与偏移为 null。
- Provider 只读，不结束进程、不启动进程、不修改系统配置。
- 进程快照不等于启动性能归因；Boot Offset 是进程创建相对时间，不是该进程耗时。
- GUI 切换到“进程时间线”页时才执行扫描；该页显示运行中进程、可读性汇总、启动时间、偏移和可执行文件路径。
