# 验证记录与发布边界

验证日期：2026-09-21。环境：Apple M2 Max、32 GB、macOS 15.7.7、Swift 6.1.2、UV 0.11.29、Python 3.12.13。

**这是开发预览。源码、本地构建和真实模型评测已完成；完整的跨应用自动粘贴验收仍未完成，不能称整个计划已经交付或正式生产发布。**

## 已取得的证据

| 检查 | 结果与边界 |
| --- | --- |
| Python 单元与协议测试 | 46 项通过，包括 SDK HTTP 替身、异常响应、超时、依赖隔离和跨进程请求账本 |
| Swift 历史核心 | 独立 harness 10 场景通过：原文、去重、TTL、容量、临时写入峰值、损坏恢复、路径边界、搜索和召回 |
| Swift 原生会话状态机 | 独立 harness 9 场景通过，状态机已接入实际界面：单次请求、取消、配置失效、手动选择、粘贴单次执行 |
| XCTest | 本机仅有 Command Line Tools，无 XCTest 模块；保留 XCTest 源码并由 GitHub macOS CI 验证，不能把本机 harness 称为 swift test 通过 |
| 原生构建 | debug 与 release 构建通过；`.app` 使用 ad-hoc 签名并通过 codesign 验证，不是公证安装包 |
| 原生界面 | 实际打开候选和设置面板；搜索 Alex 得到两项，方向键切换到 Alex Chen，原文预览与 Copy 状态正确 |
| 手动复制回读 | 从 Jev agent 复制合成 Alex Chen，再通过 macOS 原生粘贴到 Chrome 本地表单，字段回读一致；这不是应用自动粘贴验收 |
| 目标变化 | 观察到目标切换后提示 Target changed，Paste 禁用 |
| Laya 真实运行 | 固定快照离线加载并完成正式评测；macOS 15.7.7 本机可运行此锁定版本，不外推其他设备 |
| Jev 真实运行 | key 可读取官方模型列表；即便列表只列 alias，明确请求 jev-1.13.0 已成功，响应也是该版本 |

## 模型与输入版本

- Laya：`laya-mlx==0.1.0`，`aac6fef/laya-multilingual-mlx`，revision `ba40c87fcb357f1643d04d71323af9cdc3b9e591`。
- 权重实际 SHA-256：`7fc5834af4d8fdfb268d272a9d1a66e5819a0daac98241651c4c888cc43adff1`，与上游 manifest 一致。
- Jev：`typesafe-sdk==0.7.0`，请求及返回模型 `jev-1.13.0`，仅访问官方 API。
- v1 使用 JSON 上下文；开发实验发现冗余元数据影响 Laya。独立 18 条开发样例对比后，v2 采用字段优先的自然语言，保留附近文字、选区、应用和窗口。
- 当前输入版本为 `clipboard-choice-v2`。v1 报告原样保留，不用 v2 成绩覆盖旧结果。

## 真实双模型评测

两轮分别使用同一份候选、state 和 questions 比较两种模型。每条包含完整合成输入、原始响应、用量、耗时和正确性；不包含私人剪贴板或 API key。

| 轮次 | 模型 | 样例数 | Top-1 | Top-3 | 无匹配识别 | P50 | P95 | 超过 2 秒 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| v1，60 条 | Laya | 60 | 16.7% | 36.7% | 58.3% | 14.4 ms | 19.6 ms | 0 |
| v1，60 条 | Jev | 60 | 85.0% | 85.0% | 100% | 363.1 ms | 601.7 ms | 0 |
| v2，新 40 条 | Laya | 40 | 40.0% | 62.5% | 50.0% | 12.6 ms | 22.8 ms | 0 |
| v2，新 40 条 | Jev | 40 | 85.0% | 87.5% | 100% | 327.9 ms | 1114.4 ms | 2 |

v1 最近项基线 10.0%，仅检索基线 31.7%；v2 分别为 7.5% 和 22.5%。有答案样例的候选召回率分别为 83.3% 和 90.0%，说明部分错误在模型调用前已经发生。

结果必须这样理解：

- Laya v2 优于本轮基线，但 40% 远不足以承诺可靠自动选择，因此所有推荐都必须由人核对。
- v1 和 v2 使用不同样例，不能把跨表差值解释为严格同集提升；输入修改的比较来自独立开发实验。
- Jev v1 有一条概率舍入到 0.99，被旧容差误拒绝。生产代码已按选项数兼容两位小数舍入；v1 记录仍计为失败，未事后改写成绩。
- Jev v2 包含 1 次 10 秒超时和 1 次约 3 秒连接失败，均计入失败；未剔除错误提高准确率。
- 时延包括 Python 输入处理与提供者调用，不包括 AX 采集、UI 展示或用户确认，不是整个桌面工作流的端到端耗时。P95 使用 nearest-rank。
- 这些是合成探索集，部分场景具有模板相关性，样本小，不能代表真实用户准确率或统计显著性。
- 初期 Jev 冒烟还出现超时与 503；正式轮恢复成功，不意味着服务永不失败。

### 原始证据

- [v1 Laya 汇总](./evaluation/laya-acceptance/summary.json) / [完整记录](./evaluation/laya-acceptance/results.jsonl)
- [v1 Jev 汇总](./evaluation/jev-acceptance/summary.json) / [完整记录](./evaluation/jev-acceptance/results.jsonl)
- [v2 Laya 汇总](./evaluation/laya-v2/summary.json) / [完整记录](./evaluation/laya-v2/results.jsonl)
- [v2 Jev 汇总](./evaluation/jev-v2/summary.json) / [完整记录](./evaluation/jev-v2/results.jsonl)
- [重复调用与本地内存记录](./evaluation/stability.json)

同一 v2 输入重复：Laya 10 次全部成功且选择一致；Jev 5 次中 4 次成功且选择一致，1 次达到产品 2 秒超时。稳定性试验进程峰值 RSS 927,170,560 字节，MLX 峰值分配 801,889,733 字节；不是安装大小或长期内存泄漏测试。

本轮 Jev 决策总计 110 次，包含最初独立探测、失败冒烟、两轮评测及稳定性；账本上限 120，未自动重置。官方模型列表读取不属于决策请求。

## 尚未通过的完成门槛

- Chrome、Safari、TextEdit 中分别完成 Laya/Jev 推荐 → 应用自动 Paste → 原文回读的完整矩阵。
- 原生快捷键、权限撤销、休眠唤醒及真实目标中途变化的完整人工验收。
- 从全新 checkout 初始化并验证两种提供者的桌面启动。
- 桌面工作流端到端时延和长期空闲资源测量。
- 正式 `v0.1.0` 发布。本地构建、源码公开和源码 CI 不替代上述验收。

已启动的测试进程显示 Accessibility: Granted；这只证明该启动上下文的授权状态，不能替代 Finder 启动和每个目标应用的实测。桌面测试期间前台持续有用户操作，不能把其他应用误当作测试表单。

## 复现

先按 README 初始化，再运行 `bash scripts/check.sh`。正式评测参考 README，并增加 `--cases evaluation/cases_v2.json` 运行第二轮；传同轮 Laya 输出的 `prepared.json` 给 Jev，输出目录必须为新的名称。

没有 key 的 CI 只跑替身测试，不访问真实 Jev。重跑会消耗调用额度，必须沿用当前批次账本；报告需要保存具体版本及全部失败。
