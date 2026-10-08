# Phase 5 启动趋势：实现与验收记录

状态：PowerShell 7 管理员会话中的 CLI、JSON 和 GUI 人工验收已完成；自动化回归测试未运行。

## 实现范围

- 默认分析最近 30 条确认的完整实测启动；仍可用 `-Count` 或 GUI 顶部选择 5、10、20、30、50 条。
- CLI 文本和 JSON 报告提供中位数、最近启动与中位数差值，以及最近两次启动差值。
- GUI 启动历史页绘制总耗时、Main Path 和 Post Boot 三条实测曲线，并显示样本数和摘要。
- 数据按启动时间排序；差值为正表示耗时更长。记录不足时不插值；只有一条时不计算前后差值。
- 曲线纵轴按样本范围缩放。Event ID 101 不参与趋势或因果推断。

## 人工验收结果

用户在管理员 PowerShell 7 项目根目录完成以下检查：

```powershell
.\bootlens.ps1
.\bootlens.ps1 -AsJson | ConvertFrom-Json
.\bootlens-gui.ps1
```

- CLI 默认摘要显示 30 条完整启动；最近一次为 30,829 ms，中位数为 34,270 ms，较前一次少 2,036 ms。
- JSON `Trend.WindowLimit` 与 `Trend.SampleCount` 均为 30；`Trend.Records` 从 2026-02-14 18:15:13 排列至 2026-10-08 09:51:36，顺序为由早到近。
- GUI 趋势图显示正常；切换样本数量后曲线和摘要会更新。
- JSON 中最近一次、中位数和相邻启动差值与 CLI 文本摘要一致。

以上是用户在本机完成的人工验收。自动化回归测试未运行。
