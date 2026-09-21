# 第三方组件与模型归属

Jev agent 自身代码和文档采用 [MIT](./LICENSE)。该许可证不覆盖第三方代码、云端服务或模型权重；相关组件保留自己的条款。

## 直接组件

| 组件 | 锁定版本／来源 | 许可证与归属 |
| --- | --- | --- |
| TypeSafe Python SDK | `typesafe-sdk==0.7.0` | MIT；[官方源码](https://github.com/typesafe-ai/typesafe-sdk-python)，TypeSafe AI 及贡献者 |
| Laya-MLX | `laya-mlx==0.1.0` | Apache-2.0；[源码](https://github.com/mizorewww/laya-mlx)，laya-mlx contributors |
| Laya 原始模型 | [Convai Innovations / Laya](https://huggingface.co/convaiinnovations/laya) | 模型卡标记 Apache-2.0；Convai Innovations 及贡献者 |
| 多语言 MLX 权重 | [aac6fef/laya-multilingual-mlx](https://huggingface.co/aac6fef/laya-multilingual-mlx)，revision `ba40c87fcb357f1643d04d71323af9cdc3b9e591` | 快照包含 Apache-2.0 LICENSE 和 NOTICE；来自 `convaiinnovations/laya-multilingual` 的 MLX FP16 转换 |
| Jev 模型服务 | `https://api.typesafe.ai`，默认请求 `jev-1.13.0` | 外部云端服务，不分发模型权重；适用服务方账号和使用条款，SDK 的 MIT 不替代服务条款 |

以上 SDK 许可证以安装包的 METADATA / LICENSE 核验，权重以固定快照的模型卡、LICENSE 和 NOTICE 核验。完整直接与传递依赖版本见 `uv.lock`；重新分发依赖时须保留安装包中的许可证文件。

## Laya-MLX NOTICE 要点

Laya-MLX 的 NOTICE 归属为 Copyright 2026 laya-mlx contributors。它包含派生自 [NandhaKishorM/laya](https://github.com/NandhaKishorM/laya) 的软件，原归属为 Convai Innovations and Laya contributors，原始源版本为 `6a5819129eb220570792e417e49723d697efd76f`。

上游说明 token 序列构造、问题渲染、confidence 计算、预设、邮件工具及语言路由源自 Laya，神经网络使用 Apple MLX 重新实现并遵循 Laya / ModernBERT 结构。Jev agent 使用这些包作为依赖，不宣称这些能力为本项目原创。发布包含上游源码、依赖或模型的制品时，应保留完整上游 LICENSE 和 NOTICE；本文摘要不是替代文本。

模型权重由初始化步骤单独下载，不提交至本仓库。上游性能数据不能当作 Jev agent 的剪贴板效果或目标 Mac 验收数据，项目自身证据见[验证记录](./docs/VALIDATION.md)。

## 布局参考与项目关系

双语 README 顶部的语言切换布局参考 [Archify](https://github.com/tt-a1i/archify)。本项目没有复制其品牌、Logo、排名、社区链接或统计徽章。

Jev agent 是独立项目，不隶属于 TypeSafe AI、Convai Innovations、Apple、Archify 或 Laya-MLX 维护者。项目名称不表示获得这些组织的官方认可。
