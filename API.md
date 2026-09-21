# 本地接口与模型协议

Jev agent 没有面向网络的 HTTP 服务，不需要 FastAPI、端口映射或 Docker。Swift 桌面通过子进程标准输入／输出传递 UTF-8 JSON Lines；Jev 提供者内部调用官方 HTTPS API。

## 启动与配置

从已初始化的项目目录运行：

```bash
uv run --no-sync python -m jev_agent.worker --provider laya
```

或在配置 `TYPESAFE_API_KEY` 后：

```bash
uv run --no-sync python -m jev_agent.worker --provider jev
```

桌面使用构建时写入 `Contents/Resources/runtime.json` 的 Python 绝对路径和项目路径，不依赖 Finder 的 PATH。Jev key 通过子进程环境传递，不放在参数列表或 JSON 正文中。正常协议 stdout 不混入运行日志；日志使用 stderr。

## 初始化状态

```json
{"version":1,"type":"status","status":"loading","provider":"laya"}
```

加载成功：

```json
{"version":1,"type":"status","status":"ready","provider":"laya","model":"aac6fef/laya-multilingual-mlx"}
```

失败时 `status` 为 `error` 并携带错误对象，进程结束。Jev ready 表示客户端配置完成，不表示 key 权限或真实决策已验证；只有显式调用才产生决策请求。Laya 初始化只读取固定的本地快照，缺失时使用 CLI 显式下载。

## 决策请求

每个请求是一行 JSON，以换行符结束。

| 字段 | 类型 | 规则 |
| --- | --- | --- |
| `version` | integer | 必填，固定 `1` |
| `type` | string | 必填，固定 `decide` |
| `request_id` | string | 必填，1～128 字符；桌面为每次交互生成新值 |
| `config_version` | integer | 必填，非负整数；用于丢弃过期配置的响应 |
| `provider` | string | 必填，`laya` 或 `jev`，必须等于当前进程提供者 |
| `context` | object | 必填，白名单字段，值均为 string |
| `candidates` | array | 必填，最多 6 项；空数组返回无匹配，不调用上游 |

上下文字段白名单：`application`、`bundle_id`、`window_title`、`field_label`、`role`、`selected_text`、`nearby_text`、`field_description`、`placeholder`。没有读取到的内容可以省略，不能推测补齐。

每个候选仅包含 `id` 和 `text`。`id` 是 1～128 字符的唯一字符串，禁止保留值 `none`；`text` 为非空摘录。桌面仍在本地保留完整原文，不能从模型摘录执行最终粘贴。

```json
{"version":1,"type":"decide","request_id":"example-001","config_version":1,"provider":"laya","context":{"application":"Synthetic form","field_label":"Email address","role":"AXTextField"},"candidates":[{"id":"entry-url","text":"https://example.com"},{"id":"entry-email","text":"alex@example.com"}]}
```

从命令行发送合成请求：

```bash
printf '%s\n' '{"version":1,"type":"decide","request_id":"example-001","config_version":1,"provider":"laya","context":{"field_label":"Email address"},"candidates":[{"id":"entry-email","text":"alex@example.com"}]}' | uv run --no-sync python -m jev_agent.worker --provider laya
```

Python 单行输入上限为 256,000 字节。过大或非法 JSON 会产生错误，无法解析请求时 `request_id`、`config_version` 可以为 null。调用方必须有自己的截止时间，不能把无法关联的错误当成另一个请求的成功响应。

## 决策响应

示例仅说明格式，概率与耗时不是实测值：

```json
{
  "version": 1,
  "type": "result",
  "request_id": "example-001",
  "config_version": 1,
  "provider": "laya",
  "model": "aac6fef/laya-multilingual-mlx",
  "selected_id": "entry-email",
  "probabilities": {"entry-url": 0.05, "entry-email": 0.9, "none": 0.05},
  "confidence": 0.8,
  "elapsed_ms": 100.0,
  "usage": {},
  "error": null
}
```

- `selected_id` 为当前有效候选 ID；无匹配为 null。`probabilities` 使用实际 ID 和 `none`。
- 必须检查 `error`，不能仅凭 null 选择判断为有效无匹配。
- 模型概率必须有限、位于 `[0,1]`，候选集合一致。总和容差为 `选项数 × 0.005 + 0.000001`，兼容 Jev 两位小数输出；保留原始概率，不归一化或伪造精度。
- `confidence` 可以为 null，与候选概率含义不同，也不等于业务准确率。
- `usage` 采用上游提供的对象，本地模型不编造计费信息。
- Jev 额外返回 `http_status` 和 `upstream_request_id`；Laya 额外返回 `model_revision` 和 `checkpoint`。
- `prompt_version` 标识当前输入模板，当前为 `clipboard-choice-v2`；自然语言 state 优先呈现字段，不向模型发送 Bundle ID 和 AX role 技术标识。
- Python 直接调用方可获得 `input` 与 `raw` 用于合成评测；worker 在发送桌面响应前删除这两个字段。

响应必须同时匹配请求 ID、配置版本和提供者；模型输出不会直接触发粘贴。桌面仍需等待用户确认并重新验证目标。

## 错误与超时

错误保持 `type=result`，`error` 包含：

```json
{
  "code": "TIMEOUT",
  "message": "TimeoutError",
  "method": "POST",
  "path": "/v1/systemone",
  "upstream": "https://api.typesafe.ai",
  "http_status": null,
  "business_code": null,
  "business_status": null,
  "upstream_request_id": null
}
```

Laya 没有 HTTP 上游，对应字段为 null。错误消息按实际异常记录，调用方不应依赖示例字符串。

| 错误码 | 含义与处理 |
| --- | --- |
| `TIMEOUT` | 推理超时；保留手选；MLX 内核不可协作取消，桌面回收进程 |
| `INVALID_RESPONSE_OR_REQUEST` | 请求协议、候选选择或概率异常；不展示为有效推荐 |
| `AUTHENTICATION_OR_PERMISSION` | Jev 返回 401/403；核对 key 与模型权限，停止该批真实测试 |
| `RATE_LIMITED` | Jev 返回 429；手动稍后重试 |
| `UPSTREAM_ERROR` | 其他上游 HTTP 错误，例如 5xx；保留手选 |
| `INVALID_RESPONSE` | 上游 HTTP 状态与预期响应不一致 |
| `CONNECTION_FAILED` | 显式连接异常；网络相关异常也可能保留为 `PROVIDER_ERROR`，以完整消息为准 |
| `PROVIDER_ERROR` | 初始化、配置、SDK 或其他提供者异常 |
| `REQUEST_LIMIT` | 显式真实测试的持久化预算耗尽或无效；不再发送决策 |

桌面交互默认最多等待 2 秒；CLI `smoke --timeout 10` 和评测的 10 秒预算用于测量，不能被报告为两秒内交互通过。Jev SDK 设置 `RetryPolicy(max_retries=0)`。取消本地等待不保证服务器未处理请求，因此不能自动重复付费请求。

## 官方 Jev 上游

固定调用 `POST https://api.typesafe.ai/v1/systemone`，通过 `Authorization: Bearer <API_KEY>` 鉴权。`typesafe-sdk==0.7.0` 的异步客户端使用 `Choice` 与 `system_one()`，请求模型默认 `jev-1.13.0`。

适配器将候选映射为短标签 `c0`～`c5`，问题名为 `paste`，加 `none`；校验上游 `answers.paste` 后映射回本地 ID。模型、版本及 usage 保留上游事实。接口和问题语义参考[官方 SDK](https://docs.typesafe.ai/sdk/python/)；不接受任意第三方 base URL。

## 扩展提供者

扩展 Python `DecisionProvider` 时实现初始化、关闭、输入准备和 `_infer`，输出经过统一 `validate_response`。同步增加提供者选择、协议白名单、无依赖隔离测试、配置和双语文档。新提供者不得静默取代用户选择的提供者。
