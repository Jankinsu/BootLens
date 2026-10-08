# Diagnostic Observation v1 数据契约

状态：Phase 6 首版已实现；CLI、JSON 和 GUI 已由用户完成本机人工验收，用户报告现有 PowerShell 测试套件全部通过。

## 1. 目标与边界

本版只汇总 Windows 在 Diagnostics-Performance Event ID 100 中提供的 `IsWindowsDegradation` 标记。它是对 Windows 原始诊断字段的说明性展示，不是 BootLens 对性能问题的独立判定。

本版不根据耗时变化设人为阈值，不将 Event ID 101 的 `TotalTimeMs` 或 `DegradationTimeMs` 与 Event ID 100 的启动耗时合并，也不把某条记录归因到单个启动项或应用。没有证据时不生成建议或修改系统配置。

## 2. 窗口与计数规则

- 使用最近最多 N 条 `BootKind=Full` 且 `TimingType=Measured` 的 `BootRecord`；N 来自现有 `Count` 参数，默认 30。
- 对每条记录仅按原始字段分类：布尔 `true` 计入 `WindowsFlaggedBootCount`，布尔 `false` 计入 `WindowsNotFlaggedBootCount`，空值计入 `WindowsFlagUnknownBootCount`。
- 三种计数之和等于 `SampleCount`；窗口不足 N 条时只统计实际记录，不补值。
- 最近一次状态为 `Flagged`、`NotFlagged` 或 `Unknown`。状态来自最新完整启动的同一 Event 100 记录。

## 3. 报告字段

| 字段 | 类型 | 语义 |
|---|---|---|
| `SchemaVersion` | Integer | 固定为 `1` |
| `Source` | Enum | `DiagnosticsPerformanceEvent100` |
| `Scope` | Enum | `RecentMeasuredFullBoots` |
| `WindowLimit` | Integer | 请求的最大样本数 |
| `SampleCount` | Integer | 实际纳入的完整实测启动数量 |
| `WindowsFlaggedBootCount` | Integer | Event 100 字段为 `true` 的数量 |
| `WindowsNotFlaggedBootCount` | Integer | Event 100 字段为 `false` 的数量 |
| `WindowsFlagUnknownBootCount` | Integer | Event 100 字段为空的数量 |
| `LatestBootStartTimeUtc` | UTC Timestamp | 最近一次完整启动锚点 |
| `LatestBootDurationMs` | Integer | 最近一次 Event 100 的完整启动耗时 |
| `LatestWindowsDegradationState` | Enum | `Flagged`、`NotFlagged` 或 `Unknown` |
| `LatestDiagnosticsEventRecordId` | Integer | 最近一次 Event 100 的记录号，用于追溯原始事件 |

## 4. 展示文案

界面显示窗口中的三类计数、最近一次状态、启动时间和 Event 100 Record ID。需同时说明：

- `Flagged` 表示 Windows 对该启动记录设置了退化标记，不代表识别了原因或责任应用。
- `NotFlagged` 只表示该字段未设置，不证明用户体验没有变慢或不存在其他问题。
- `Unknown` 表示原始字段不可用，不得按 `false` 处理。
- Event ID 101 仍在独立页面展示，不能与该计数混为一类或据此进行单应用因果归因。
