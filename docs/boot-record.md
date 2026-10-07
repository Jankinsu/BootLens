# BootRecord v1 数据契约

状态：Phase 0 已确认，可用于 Phase 1 实现。

## 1. 定义

一个 `BootRecord` 表示一次已经通过证据确认的 Windows 完整启动。

第一版只接受：

```text
Restart
shutdown /s /t 0 后的完整启动
```

第一版不为以下情况创建 `BootRecord`：

```text
Fast Startup
Sleep Resume
Hibernate Resume
无法确认启动类型的记录
```

`BootRecord` 只描述 Windows 已测量的启动数据，不包含估算值。

## 2. 接受条件

一条 Diagnostics-Performance Event ID 100 必须同时满足以下条件：

1. 必需字段存在且能够解析；
2. 存在时间对应的 Kernel-General Event ID 12；
3. 存在时间对应的 Kernel-Boot Event ID 27；
4. Event ID 27 的原始 `BootType` 等于 `0x0`；
5. Event ID 100 的 `BootStartTime` 与 Event ID 27 的 `TimeCreated` 时间差不超过 1 秒；
6. 时间关联结果唯一；
7. 三个持续时间均为非负整数；
8. 满足 `BootDurationMs = MainPathBootDurationMs + PostBootDurationMs`。

任何条件不满足时：

```text
排除记录
记录诊断日志
不生成推断值
```

## 3. 时间关联依据

当前 12 条完整启动样本中，Event ID 100 的 `BootStartTime` 与对应 Event ID 27 的 `TimeCreated` 差值范围为：

```text
28.490 ms ～ 31.049 ms
```

第一版采用：

```text
CorrelationTolerance = 1 second
```

1 秒是保守容差，不代表启动阶段持续 1 秒。它只用于关联不同日志中的同一次启动。

## 4. 字段定义

| 字段 | 类型 | 必需 | 语义 |
|---|---|---:|---|
| `SchemaVersion` | Integer | 是 | 数据契约版本，第一版固定为 `1` |
| `BootStartTimeUtc` | UTC Timestamp | 是 | Event ID 100 的原始 `BootStartTime`，用于标识和关联一次启动 |
| `BootKind` | Enum | 是 | 第一版有效值仅为 `Full` |
| `KernelBootTypeCode` | Integer | 是 | Event ID 27 的原始 `BootType`，第一版接受值为 `0` |
| `BootDurationMs` | Integer | 是 | Event ID 100 的 `BootTime`，Windows 测量的总启动处理时间 |
| `MainPathBootDurationMs` | Integer | 是 | Event ID 100 的 `MainPathBootTime`，桌面出现前的主启动路径 |
| `PostBootDurationMs` | Integer | 是 | Event ID 100 的 `BootPostBootTime`，桌面出现后的稳定阶段 |
| `StartupAppCount` | Integer | 否 | Event ID 100 的 `BootNumStartupApps` |
| `IsWindowsDegradation` | Boolean | 否 | Event ID 100 的 `BootIsDegradation`，只表示 Windows 自身的退化判断 |
| `IsRebootAfterInstall` | Boolean | 否 | Event ID 100 的 `BootIsRebootAfterInstall` |
| `TimingType` | Enum | 是 | 第一版固定为 `Measured` |
| `TimingSource` | Enum | 是 | 第一版固定为 `DiagnosticsPerformanceEvent100` |
| `DiagnosticsEventRecordId` | Integer | 是 | Diagnostics-Performance Event ID 100 的记录 ID |
| `DiagnosticsEventVersion` | Integer | 是 | Event ID 100 的版本，用于兼容未来字段变化 |
| `KernelBootEventRecordId` | Integer | 是 | Kernel-Boot Event ID 27 的记录 ID |
| `KernelGeneralEventRecordId` | Integer | 是 | Kernel-General Event ID 12 的记录 ID |

所有持续时间统一使用整数毫秒，禁止在核心模型中使用浮点秒数。

秒数只在展示层计算：

```text
DisplaySeconds = DurationMs / 1000
```

## 5. 示例

来自 2026-10-07 的完整关机启动实验：

```json
{
  "SchemaVersion": 1,
  "BootStartTimeUtc": "2026-10-07T08:35:20.7602927Z",
  "BootKind": "Full",
  "KernelBootTypeCode": 0,
  "BootDurationMs": 32865,
  "MainPathBootDurationMs": 9265,
  "PostBootDurationMs": 23600,
  "StartupAppCount": 14,
  "IsWindowsDegradation": false,
  "IsRebootAfterInstall": false,
  "TimingType": "Measured",
  "TimingSource": "DiagnosticsPerformanceEvent100",
  "DiagnosticsEventRecordId": 1096,
  "DiagnosticsEventVersion": 2,
  "KernelBootEventRecordId": 212995,
  "KernelGeneralEventRecordId": 212988
}
```

## 6. 不进入核心模型的字段

### BootEndTime

保留在原始事件中用于诊断，但不进入 `BootRecord` v1。

原因：

```text
BootEndTime - BootStartTime != BootTime
```

不能使用两个时间戳相减计算启动耗时。

### UserLogonWaitDuration

不进入 `BootRecord` v1，也不解释为用户停留在登录界面的时间。

本机实验中，该字段与真实登录等待时间明显不一致。

### 启动来源细分

第一版不尝试区分：

```text
Restart
完整关机后开机
```

现有可靠事件只能确认两者都是完整启动，不能可靠恢复用户执行了哪一种操作。

### Estimated Timing

第一版不包含估算时间。无法测量时显示 `Unknown`，不创建伪精确数值。

## 7. Phase 1 使用边界

Phase 1 可以基于 `BootRecord` 计算：

```text
Last Boot
Average
Fastest
Slowest
Recent Boots
```

第一版统计只使用：

```text
BootKind = Full
TimingType = Measured
```

启动项归因、进程时间线和性能建议不属于 `BootRecord` v1。
