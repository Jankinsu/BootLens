# Boot Trend v1 数据契约

状态：Phase 5 首版已实现；PowerShell 7 / 管理员权限下的本机 GUI 与 CLI 验收待完成。

## 1. 定义与范围

`BootTrend` 描述最近最多 N 次已确认完整启动的 Windows 实测记录。默认 N=30；GUI 和 CLI 可通过现有 `Count` 参数选择其他窗口大小。

趋势只使用 `BootKind=Full` 且 `TimingType=Measured` 的 `BootRecord`。曲线展示 `BootDurationMs`、`MainPathBootDurationMs` 和 `PostBootDurationMs`。三个字段均来自 Diagnostics-Performance Event ID 100；阶段时长之和必须符合 BootRecord v1 契约。

## 2. 报告字段

| 字段 | 类型 | 语义 |
|---|---|---|
| `SchemaVersion` | Integer | 固定为 `1` |
| `Source` | Enum | `DiagnosticsPerformanceEvent100` |
| `Scope` | Enum | `RecentMeasuredFullBoots` |
| `WindowLimit` | Integer | 请求的最大样本数 |
| `SampleCount` | Integer | 实际可用的完整实测启动数，可能少于窗口上限 |
| `OldestBootStartTimeUtc` | UTC Timestamp | 当前窗口最早启动锚点 |
| `NewestBootStartTimeUtc` | UTC Timestamp | 当前窗口最近启动锚点 |
| `MedianBootDurationMs` | Integer | 窗口内总启动耗时中位数；偶数样本取中间两值均值并四舍五入到毫秒 |
| `LatestBootDurationMs` | Integer | 最近一次完整启动的总耗时 |
| `ChangeFromMedianMs` | Signed Integer | 最近一次总耗时减窗口中位数；正值表示耗时更长 |
| `PreviousBootDurationMs` | Integer or null | 紧邻最近一次之前的完整启动耗时；仅一条样本时为 null |
| `ChangeFromPreviousBootMs` | Signed Integer or null | 最近一次总耗时减前一次；仅一条样本时为 null |
| `Records` | Array | 按启动时间从早到晚排序的三个原始毫秒指标 |

## 3. 展示约束

- 内部数据继续以整数毫秒保存；秒数只在 CLI / GUI 展示时格式化。
- 最近 30 次是默认窗口；记录不足时展示实际样本数，不补值、不插值。
- 图表纵轴按当前窗口内的实测值范围缩放，并在界面明确说明；不对空白时间段作平滑或推测。
- 正的差值表示耗时更长，不表示统计显著性或性能退化结论。
- Event ID 101 保持为独立诊断记录。趋势不将其值加到启动耗时，不用于单应用因果归因或自动优化建议。

## 4. 可视化边界

图表的三个系列是总启动耗时、Main Path 和 Post Boot。时间顺序从左到右由较早到最近。每个点对应一个 BootRecord，不代表单个应用的启动耗时；当前不提供预测、回归拟合或退化判定阈值。
