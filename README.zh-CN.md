<h1 align="center">Jev agent</h1>

<h3 align="center">随手复制，按需粘贴。</h3>

<p align="center">
  面向 macOS 的上下文智能剪贴板助手。<br />
  邮箱、链接、地址、代码，像平常一样复制。准备粘贴时，Jev agent 根据眼前的输入框，从历史记录中推荐适合的内容。
</p>

<p align="center">在 Mac 上运行 Laya，或连接 Jev API。查看推荐，再粘贴完整原文。</p>

<p align="center">
  <a href="#preview"><strong>产品预览</strong></a> &nbsp;·&nbsp;
  <a href="#getting-started"><strong>开始使用</strong></a> &nbsp;·&nbsp;
  <a href="#use-cases"><strong>使用场景</strong></a> &nbsp;·&nbsp;
  <a href="#how-it-works"><strong>工作方式</strong></a> &nbsp;·&nbsp;
  <a href="./README.md"><strong>English</strong></a>
</p>

<p align="center">
  <a href="https://github.com/To3akaRin/Jev-agent/actions/workflows/ci.yml"><img src="https://github.com/To3akaRin/Jev-agent/actions/workflows/ci.yml/badge.svg" alt="构建与测试" /></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-22c55e" alt="MIT 许可证" /></a>
  <img src="https://img.shields.io/badge/macOS-Apple%20Silicon-334155" alt="Apple Silicon macOS" />
</p>

<a id="preview"></a>

## 让剪贴板理解当前场景

<p align="center">
  <img src="./docs/assets/jev-agent-preview.png" alt="Jev agent 界面概念图，左侧为剪贴板记录，右侧为完整原文预览" width="960" />
  <br />
  <sub>界面概念预览。</sub>
</p>

你先后复制了会议链接、邮箱和收货地址，现在光标停在邮箱输入框。Jev agent 可以利用这个上下文，推荐适合该字段的历史记录，减少逐条查找的操作。

**最终由你决定：** 检查完整原文、换一条记录，或取消。推荐不会自动提交表单或发送消息。

<a id="getting-started"></a>

## 在你的 Mac 上开始使用

需要 **Apple Silicon Mac**、Apple Command Line Tools 或 Xcode、Git，以及 [UV](https://docs.astral.sh/uv/getting-started/installation/)。Python 3.12 由 UV 管理。原生应用最低目标为 macOS 14，固定版本的 Laya 运行时已在 macOS 15.7.7 上测试。

缺少 Apple 开发工具时，先执行 `xcode-select --install`，然后运行：

```bash
git clone https://github.com/To3akaRin/Jev-agent.git
cd Jev-agent
bash scripts/bootstrap.sh laya
open "dist/Jev agent.app"
```

在**系统设置 → 隐私与安全性 → 辅助功能**中允许 Jev agent。复制一些文字，聚焦输入框，按下 **`⌘⇧V`**。

想使用 Jev？将初始化命令改为 `bash scripts/bootstrap.sh jev`，在应用 Settings 中选择 **Jev · Cloud** 并输入 key。使用 `both` 可以安装两种提供者。key 保存在 macOS Keychain。

当前为采用 ad-hoc 签名的源码构建应用。请保留项目目录及 `.venv`，它不是已公证的独立安装包。[安装、更新与排障指南 →](./docs/GUIDE.zh-CN.md)

<a id="features"></a>
<a id="use-cases"></a>

## 为下一个输入框找到合适内容

| 你正在做什么 | Jev agent 可以利用的信息 |
| --- | --- |
| 填写联系人表单 | 姓名、邮箱、地址等字段标签 |
| 分享会议链接 | 当前输入框和近期复制的网址 |
| 编写或讨论代码 | 代码片段与光标附近可获取的文字 |
| 组织较长的消息 | 确认前可以完整查看的多行原文 |

这些是目标使用场景，不代表准确率保证。上下文不可用或推荐不合适时，仍可搜索历史并手动选择。

<a id="how-it-works"></a>

## 复制 → 聚焦 → 查看 → 粘贴

1. **正常复制。** Jev agent 记录自身运行期间复制的纯文本。
2. **聚焦字段。** 按 `⌘⇧V`，获取当前应用及支持的输入框上下文。
3. **获得推荐。** 本地检索筛选最多 6 条候选，由所选模型选择一条或返回无匹配。
4. **查看并确认。** 检查完整原文后回车，应用重新核对目标再执行粘贴。

| 按键 | 操作 |
| --- | --- |
| `⌘⇧V` | 打开面板，可在 Settings 中修改 |
| `↑` / `↓` | 选择记录 |
| `Return` | 确认当前记录 |
| `Esc` | 取消 |
| `⌘V` | 保持普通系统粘贴 |

无法读取或恢复目标时，使用 **Copy** 手动粘贴。模型不会改写你选择的原文。

## 决定模型在哪里运行

| | Laya · Local | Jev · Cloud |
| --- | --- | --- |
| 运行方式 | Apple Silicon Mac 上的 MLX | TypeSafe 官方 API |
| 配置 | 下载固定的多语言模型 | 配置 API key |
| 网络 | 首次下载，之后可离线推理 | 推荐时需要网络 |
| 模型输入 | 在本机处理 | 当前上下文和候选摘录发送至 TypeSafe |

**默认使用 Laya。** 提供者由你显式切换，失败时不会自动把本地处理改成云端请求。只使用 Jev 时无需下载 Laya。

## 历史够用，也有边界

- **最多 3 天、20 MB。** 任一限制达到时清理最旧记录，模型及依赖单独存放。
- **保留完整原文。** 链接、空白、代码和多行文本保持原样。
- **随时管理。** 暂停记录、排除应用、删除单条或清空全部历史。
- **围绕当前字段。** 通过辅助功能读取支持的应用和字段信息，不截图、不做 OCR。

历史以明文保存在本机 `~/Library/Application Support/Jev agent/history`。明确标记为机密的剪贴板内容及安全输入框会被排除。Jev 仅在请求云端推荐时发送上下文和候选摘录，不上传全部历史。[数据、权限与配置说明 →](./docs/GUIDE.zh-CN.md)

<a id="validation"></a>

## 开源开发，真实模型验证

**当前为开发预览版。** 双模型、原生应用、测试及构建脚本已实现；Chrome、Safari、TextEdit 的完整自动粘贴验收仍在进行。

最新一轮使用相同预处理输入的 40 条合成样例结果：

| 提供者 | Top-1 选择正确率 | 模型请求耗时中位数 |
| --- | ---: | ---: |
| Laya | 40% | 12.6 ms |
| Jev | 85% | 327.9 ms |

错误请求计为失败。这组小规模合成结果不代表通用准确率，请求耗时也不包含桌面交互。Laya 推荐仍属实验性能力，请始终核对原文。[实测结果、原始响应与待验收事项 →](./docs/VALIDATION.md)

## 下一步，探索 Tab 驱动的桌面助手

从智能粘贴开始，逐步探索：在授权范围内理解用户操作和应用上下文，预测下一步意图，由用户按下 **Tab** 执行建议的 computer-use 操作。

这是后续方向，尚未包含在当前剪贴板版本中。

## 一起完善 Jev agent

通过 [Issues](https://github.com/To3akaRin/Jev-agent/issues) 提交可复现的问题或改进建议。反馈上下文读取问题时，请附应用版本、字段类型、提供者和合成示例。

项目使用 **Swift/AppKit** 接入 macOS，使用 **Python** 运行模型提供者，通过本地 JSON Lines 管道连接。原生运行，不需要 Docker 服务或监听端口。

```bash
bash scripts/check.sh
bash scripts/build-app.sh  # 重新构建前先退出 Jev agent。
```

| 了解什么 | 文档入口 |
| --- | --- |
| 安装、更新、配置与排障 | [使用与开发指南](./docs/GUIDE.zh-CN.md) |
| 环境变量默认值 | [`.env.example`](./.env.example) 与[配置说明](./docs/GUIDE.zh-CN.md#配置) |
| 模块结构与扩展提供者 | [目录结构](./docs/GUIDE.zh-CN.md#目录结构)与[本地 API](./API.md) |
| 参与贡献 | [贡献指南](./CONTRIBUTING.md)与[项目规格](./docs/SPEC.zh-CN.md) |
| 查看进展 | [更新日志](./CHANGELOG.md)与[验证记录](./docs/VALIDATION.md) |

### 几个常见问题

- **没有推荐？** 等待模型就绪，查看状态，或选择 **Retry model**；仍可手动使用历史。
- **不能粘贴？** 检查当前构建的辅助功能权限，不支持的字段保留仅复制方式。
- **支持图片和文件吗？** 当前版本支持纯文本、链接、代码及多行内容。
- **移动了项目目录？** 重新构建以更新运行时路径。[更多排障说明 →](./docs/GUIDE.zh-CN.md#常见问题与卸载)

## 许可证与致谢

Jev agent 采用 [MIT 许可证](./LICENSE)，使用 [Laya](https://huggingface.co/convaiinnovations/laya)、[Laya-MLX](https://github.com/mizorewww/laya-mlx) 与 [TypeSafe Jev API](https://docs.typesafe.ai/)。第三方依赖和权重保留各自许可证，详见[第三方说明](./THIRD_PARTY_NOTICES.md)。

这是独立项目，不是模型提供者的官方产品。
