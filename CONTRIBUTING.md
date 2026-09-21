# 贡献指南

## 开发环境

需要 Apple Silicon macOS、Swift 工具链、UV 和 Git。完整设置见 [README](./README.zh-CN.md)。仅修改协议或 Jev 时不必下载本地权重：

```bash
git clone https://github.com/To3akaRin/Jev-agent.git
cd Jev-agent
bash scripts/bootstrap.sh jev
```

修改 Laya 时：

```bash
bash scripts/bootstrap.sh both
```

当前是开发预览版，支持范围及未完成验收以[验证记录](./docs/VALIDATION.md)为准。

## 文档驱动流程

1. 阅读 README、[规格](./docs/SPEC.zh-CN.md)、[本地协议](./API.md)、[更新日志](./CHANGELOG.md)和相关模块。
2. 明确业务术语、边界、例外和验收标准；范围变化先更新规格并完成评审。
3. 为行为变化先添加失败测试，再做最小实现；小步检查，独立模块可以分任务开发。
4. 执行本地检查和与变更相关的真实验收，分别报告模拟、本地模型、云端模型及桌面结果。
5. 同步文档、示例配置、版本记录和验收证据，再提交 PR。

不要使用运行成功、HTTP 200 或界面可打开代替“原文正确粘贴到目标字段”的验收。

## 分支、提交与 PR

从 `main` 建立 `feat/简短主题` 或 `fix/简短主题` 分支；实际分支名建议 ASCII。提交信息用 `feat:`、`fix:`、`docs:`、`test:` 或 `chore:` 前缀概括最终变化。

提交前检查：

```bash
git status --short
git branch --show-current
git remote -v
git var GIT_AUTHOR_IDENT
git var GIT_COMMITTER_IDENT
git diff --check
bash scripts/check.sh
```

显式暂存本次文件，不使用 `git add .`。查看暂存差异后提交；推送前确认目标分支与远程，PR 中说明问题、最终行为、测试证据和未完成项，不附真实凭据或私人输入。涉及 UI 变化的截图只使用合成历史。

## 测试入口

```bash
uv run --no-sync pytest Tests/python
uv run --no-sync ruff check src Tests/python scripts/*.py
bash scripts/test-core.sh
bash scripts/test-session.sh
swift build -c release
uv run --no-sync python scripts/check_docs.py
```

`bash scripts/check.sh` 串联这些检查。只有 Command Line Tools 的环境缺少 XCTest，`test-core.sh` 使用独立 Swift 核心检查并在输出标明；Xcode 环境运行 XCTest，二者不要混称。

真实模型调用必须显式执行，步骤见 README。公开 PR 和普通 CI 不使用维护者 key；错误、限流等路径通过测试替身验证。真实 Jev 测试共享持久化请求账本，计入冒烟和评测，单批不得超过 120 次；不得清空账本规避限制。

模型评测使用冻结的 `evaluation/cases.json`，调参样例与验收集分离。对比模型时复用 `--prepared` 输入，报告所有错误和超时；不得只筛选成功响应计算整体效果。新增验收样例须解释覆盖的新业务边界。

## 风格与模块边界

- Swift 使用原生 Foundation/AppKit；历史核心不依赖 UI，UI 不直接嵌入模型 SDK。
- Python 按 Ruff 检查，提供者依赖按需导入；Jev 模式不加载 MLX，本地模式不建立 Jev 连接。
- 新增注释和技术文档优先使用中文；用户界面首版为英文，文案集中管理方向保持一致。
- JSON Lines stdout 仅承载协议；日志走 stderr。新错误包含可定位的操作、状态、完整错误和耗时。
- UI、AX IPC、模型加载和网络等待遵守有界执行；旧请求、已取消请求不能改变当前用户选择。
- API、配置、目录或部署变化同步 API/README；环境项写入 `.env.example`，真实密钥不得进入仓库。

## 数据与许可证

不得提交剪贴板历史、Keychain 凭据、真实 `.env`、下载权重或本地日志。合成测试保留完整输入和响应，发布前检查内容与身份。第三方依赖或权重调整时更新 [THIRD_PARTY_NOTICES](./THIRD_PARTY_NOTICES.md) 并保留上游许可证及 NOTICE。

本项目采用用户已确认的原生桌面部署例外，不增加 Docker Compose 后端，也不把源码构建 `.app` 宣称为包含全部运行时的安装包。
