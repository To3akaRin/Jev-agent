<h1 align="center">Jev agent</h1>

<h3 align="center">根据眼前的输入框，找到此刻该粘贴的内容。</h3>

<p align="center">
  面向 macOS 的上下文智能剪贴板助手。<br />
  选择本地 Laya 或 Jev API，查看推荐，再粘贴完整原文。

  未来将要变成 实时观察用户操作和应用上下文，预测下一步意图，按下 tab 就自动执行对应的 computer use 操作的 agent 。
</p>

<p align="center">
  <a href="#features"><strong>功能特性</strong></a> &nbsp;·&nbsp;
  <a href="#how-it-works"><strong>工作方式</strong></a> &nbsp;·&nbsp;
  <a href="#getting-started"><strong>开始使用</strong></a> &nbsp;·&nbsp;
  <a href="#validation"><strong>验证记录</strong></a> &nbsp;·&nbsp;
  <a href="./README.md"><strong>English</strong></a>
</p>

<p align="center">
  macOS · Apple Silicon · Laya 本地 / Jev 云端 · <a href="./LICENSE">MIT 许可证</a>
</p>

> **当前状态：开发预览版。** 原生应用、历史管理、双模型适配、测试及源码构建脚本已经实现。本地检查和真实 Jev API 探测与完整模型、桌面验收分别记录。需要辅助功能权限的 Chrome、Safari、TextEdit 工作流仍需在目标 Mac 验证。具体实测结果及阻断项见[验证记录](./docs/VALIDATION.md)，不能将当前状态视为已完成生产发布。

<a id="features"></a>

![使用合成剪贴板历史的原生面板](./docs/assets/demo.png)

*仅演示界面布局，不代表模型推荐或自动粘贴验收。*

## 功能特性

- **结合输入框选择：** 根据应用、窗口标题、字段标签及可获取的选区附近文字选择已有记录。
- **双模型：** Laya 通过 MLX 在 Apple Silicon 本地运行；Jev 调用 TypeSafe 官方 API。默认 Laya，显式切换，不在失败后静默改用云端。
- **确认后粘贴：** `⌘⇧V` 打开面板，查看推荐后回车；普通 `⌘V` 保持系统行为。
- **保留原文：** 链接、代码、空白和多行内容不改写。模型只选择记录，不提交表单。
- **有限历史：** 最多 72 小时、20,000,000 字节，包含元数据及历史临时写入。重复内容合并，超大单条完整跳过。
- **手动控制：** 搜索、复制、暂停记录、排除应用、单条删除及全部清空。模型失败时保留手选。

<a id="how-it-works"></a>

## 工作方式

1. 在 Jev agent 运行期间复制文字。
2. 聚焦支持的输入框，按 `⌘⇧V`。
3. 应用先保存目标，再打开面板；召回最多 6 条候选，保留最近 2 条并补充相关记录。
4. 当前提供者从候选或“无匹配”中选择，仅有界摘录进入模型请求。
5. 查看完整原文并确认；应用重新检查目标后执行粘贴。

方向键选择、回车确认、Esc 取消。无法读取或可靠恢复目标时，使用 Copy 手动粘贴。邮箱输入框遇到多个无关的近期剪贴板记录，是代表性测试场景，不是准确率保证。

## 数据与权限

| 数据 | 行为 |
| --- | --- |
| 历史 | 纯文本保存在 `~/Library/Application Support/Jev agent/history`，最多 72 小时／20 MB |
| 上下文 | 应用、窗口及当前字段元数据；支持时按有界文本范围读取 |
| Laya | 显式下载固定快照，之后推理仅加载本地文件 |
| Jev | 仅在 Jev 模式请求推荐时，将当前上下文和候选摘录发送至 `https://api.typesafe.ai` |
| API key | 桌面设置使用 macOS Keychain；CLI 测试使用 `TYPESAFE_API_KEY` |
| 排除项 | 机密剪贴板标记、安全输入框及配置的应用 |
| 权限 | 通过辅助功能读取支持的字段并自动粘贴 |

首版不截图、不做 OCR、不云同步历史、不在复制时后台调用云端模型，不处理图片／文件，也不导入第三方历史。历史是本地明文，不是加密保险库。来源应用仅在剪贴板提供明确标记时记录，否则显示未知；采集时还会检查当前应用是否位于排除列表。

原生界面目前使用英文。英文与简体中文项目文档同步维护。

<a id="getting-started"></a>

## 开始使用

### 环境要求

- Apple Silicon Mac。原生应用最低目标为 macOS 14；不代表所有 MLX 版本都支持该系统。实际机器和 Laya 兼容情况见[验证记录](./docs/VALIDATION.md)。
- Apple Command Line Tools 或 Xcode、Git、[UV](https://docs.astral.sh/uv/getting-started/installation/)。
- Python 3.12，由 UV 管理。首次安装依赖和下载模型需要网络，Jev 调用也需要网络。

缺少 Apple 开发工具时执行：

```bash
xcode-select --install
```

按照官方说明安装 UV 后：

```bash
git clone https://github.com/To3akaRin/Jev-agent.git
cd Jev-agent
bash scripts/bootstrap.sh laya
open "dist/Jev agent.app"
```

选择初始化模式：

| 命令 | 行为 |
| --- | --- |
| `bash scripts/bootstrap.sh laya` | 安装锁定依赖及 MLX、构建应用、下载固定快照并运行 Laya 合成冒烟检查 |
| `bash scripts/bootstrap.sh jev` | 不安装 MLX 扩展并构建；不下载 Laya，不发送云端决策请求 |
| `bash scripts/bootstrap.sh both` | 安装双模型依赖、构建应用、下载 Laya 并运行其冒烟检查 |

先构建应用，再下载模型。下载或冒烟失败时，已构建应用仍可使用手动历史功能；冒烟通过不代表效果评测通过。

初始化只准备依赖和构建，不授予辅助功能权限、不写入 Keychain、不证明模型效果，也不替你修改已保存的提供者。在菜单栏 Settings 中选择提供者。使用 Jev 时输入自己的 key；保留 `jev-1.13.0`，除非显式选择账号可访问的其他模型。在**系统设置 → 隐私与安全性 → 辅助功能**中允许 Jev agent。

应用采用 ad-hoc 签名，没有 Developer ID 签名和公证。运行配置记录当前 checkout 和 `.venv` 的绝对路径，两者需要保留；移动 checkout 后需重新构建。不能把这个 `.app` 当成独立安装包分发。

### 更新和重新构建

替换构建前先从菜单退出 Jev agent，在项目目录运行：

```bash
git pull --ff-only
bash scripts/bootstrap.sh both
open "dist/Jev agent.app"
```

只使用 Jev 时用 `jev` 替换 `both`。历史、应用偏好及 Keychain 凭据位于构建目录外。只重新构建而不安装依赖、下载模型：

```bash
bash scripts/build-app.sh
```

### 显式模型检查

安装 Laya 可选依赖后：

```bash
uv run --no-sync python -m jev_agent.cli download
uv run --no-sync python -m jev_agent.cli smoke --provider laya --timeout 10
```

Jev 测试在本地终端将占位符换成自己的凭据，禁止提交真实值。持久化账本将这组测试限制在 120 次决策内，不应通过重置账本绕过上限。

```bash
export TYPESAFE_API_KEY='YOUR_TYPESAFE_API_KEY'
export TYPESAFE_DEFAULT_MODEL='jev-1.13.0'
export JEV_AGENT_LIVE_BUDGET_FILE="$PWD/.runtime/jev-budget.json"
export JEV_AGENT_LIVE_BUDGET_LIMIT=120
uv run --no-sync python -m jev_agent.cli smoke --provider jev --models --timeout 10
uv run --no-sync python -m jev_agent.cli smoke --provider jev --timeout 10
```

`--models` 查询账号可见模型。冒烟测试使用合成内容，未选中正确邮箱候选时返回失败。客户端已配置或 HTTP 200 不能单独证明推荐成功。

### 配置

[`.env.example`](./.env.example) 说明默认项；应用**不会自动读取 `.env`**。桌面选项在 Settings 配置，CLI 测试在终端导出变量；Finder 启动的应用不一定继承终端环境。

| 环境变量 | 默认值／用途 |
| --- | --- |
| `JEV_AGENT_PROVIDER` | `laya`，可选 `jev`；桌面已保存设置优先 |
| `JEV_AGENT_LAYA_MODEL` | `aac6fef/laya-multilingual-mlx` |
| `JEV_AGENT_LAYA_REVISION` | `ba40c87fcb357f1643d04d71323af9cdc3b9e591` |
| `JEV_AGENT_DECISION_TIMEOUT_MS` | `2000`；桌面交互最多等待两秒 |
| `TYPESAFE_API_KEY` | Jev CLI 凭据；桌面凭据保存在 Keychain |
| `TYPESAFE_DEFAULT_MODEL` | `jev-1.13.0`；桌面已保存模型优先 |
| `JEV_AGENT_LIVE_BUDGET_FILE` | 显式真实测试的持久化决策计数文件，可选 |
| `JEV_AGENT_LIVE_BUDGET_LIMIT` | 真实测试最多调用次数，默认 `120`，不允许超过 `120` |

<a id="validation"></a>

## 检查与评测

```bash
bash scripts/check.sh
```

运行 Python lint、测试、Swift 核心检查、release 构建及本地文档链接检查。安装 Xcode 时核心检查运行 XCTest；只有 Command Line Tools 时改用独立 Swift 检查程序，并在输出中明确说明。两者都不代表 CI 已验证桌面授权、真实粘贴目标或付费模型。

`evaluation/cases.json` 包含固定的 60 条中英文合成样例。先安装 `both`、构建并按前文配置 Jev 测试环境，再以相同整理后的输入运行两种模型：

```bash
swift build -c release
uv run --no-sync python scripts/evaluate.py --provider laya --output laya-repro
uv run --no-sync python scripts/evaluate.py --provider jev --prepared artifacts/laya-repro/prepared.json --output jev-repro
```

再次运行需使用新的输出名称。`artifacts/` 中保存完整合成输入／响应、共同请求和汇总，默认不进入 Git。评测包含 Top-1、Top-3、无匹配识别、候选召回、最近项和纯检索基线、耗时及超过产品两秒预算的比例。模型响应时间与从快捷键到粘贴完成的桌面耗时分别统计。实际证据与限制见[验证记录](./docs/VALIDATION.md)。

## 目录结构

```text
Sources/JevAgent/       菜单栏、上下文、设置及模型进程桥接
Sources/JevCore/        历史存储和确定性候选检索
Sources/JevEval/        检索基线可执行程序
src/jev_agent/         Python 提供者、有界输入、协议和 CLI
Tests/                  Swift 与 Python 测试
evaluation/             固定合成评测集
scripts/                初始化、构建、检查和评测脚本
docs/                   规格、集成契约和验证记录
```

Swift/AppKit 接入原生剪贴板与辅助功能；Python 隔离模型依赖；JSON Lines 通过本地管道通信，不开放服务端口。协议见 [API 文档](./API.md)。本项目采用原生桌面部署，不是 Docker 服务。

## 常见问题与卸载

- **没有推荐：** 等待模型就绪，查看状态，或在菜单选择 **Retry model**；不会静默切换提供者。
- **字段不可读或粘贴失败：** 检查当前构建的辅助功能权限；不支持的字段保留 Copy。模型就绪不能代替系统授权。
- **Laya 快照缺失：** 重新运行 `download`。系统上的 Metal／MLX 失败应记录到[验证记录](./docs/VALIDATION.md)，不能由构建成功推断兼容。
- **Jev 鉴权、权限、限流或网络异常：** 核对 key、模型权限和网络，期间手选。交互请求不会自动重试。
- **快捷键冲突：** 在 Settings 更换组合，普通 `⌘V` 不被接管。
- **移动目录后找不到运行时：** 在新 checkout 运行 `bash scripts/build-app.sh`。
- **卸载：** 退出应用；如需删除历史，先在 Settings 清空，再删除构建的 `.app` 和项目目录。否则历史保留在前述路径。API 凭据可在“钥匙串访问”删除服务 `ai.jev.agent`、账号 `typesafe` 对应项目。Hugging Face 模型缓存独立保留，确认其他应用不再使用后单独删除。

## 贡献与许可证

阅读[贡献指南](./CONTRIBUTING.md)、[规格](./docs/SPEC.zh-CN.md)、[更新日志](./CHANGELOG.md)及[第三方说明](./THIRD_PARTY_NOTICES.md)。行为、安装方式或完成状态变化时同步两版 README。不要提交私人历史、真实凭据、模型权重或本地运行日志。

项目采用 [MIT 许可证](./LICENSE)，第三方依赖和模型保留各自条款。Jev agent 是独立项目，不是 TypeSafe AI、Convai Innovations 或 Laya-MLX 维护者的官方产品。
