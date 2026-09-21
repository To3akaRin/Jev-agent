# 实施计划与集成契约

用户已批准：原生 macOS 菜单栏，Laya 本地 + Jev 官方 API 双提供者，72 小时 / 20 MB 纯文本历史，独立快捷键，确认后原文粘贴，英文与简体中文 README，MIT，公开 To3akaRin/Jev-agent。默认 Laya，Jev 必须显式选择，不静默切换；不自动发送消息。按 TDD 分任务实现。

## 阶段

- M0 工程与契约；M1 历史存储；M2 原生交互；M3 Laya；M4 Jev；M5 双模型与桌面验收；M6 构建和文档；M7 GitHub 发布。
- 真实 Jev 决策最多 120 次，合成测试正文保留完整响应；凭据不进入代码、日志、报告和 Git。
- 任何未完成真实验收明确标注，不以模拟测试替代；桌面权限由系统控制。

## Swift / Python JSON Lines v1

启动命令：绝对 Python 路径 `-m jev_agent.worker --provider laya|jev`。环境携带 SDK key，不能在请求里传 key。

stdout 仅协议，stderr 日志。启动后先发 `{"version":1,"type":"status","status":"loading","provider":"laya"}`，真实初始化成功后 status=ready；失败 status=error，附 error 对象。Jev 只建立客户端，不在后台自动发送付费请求。

请求：`{"version":1,"type":"decide","request_id":"UUID","config_version":1,"provider":"laya","context":{"application":"Chrome","bundle_id":"com.google.Chrome","window_title":"Test","field_label":"Email","role":"AXTextField","selected_text":"","nearby_text":""},"candidates":[{"id":"stable-id","text":"person@example.com"}]}`。

成功：`{"version":1,"type":"result","request_id":"UUID","config_version":1,"provider":"laya","model":"...","selected_id":"stable-id or null","probabilities":{"stable-id":0.8,"none":0.2},"confidence":0.5,"elapsed_ms":100,"usage":{},"error":null}`。

错误同 result，selected_id=null、probabilities={}，error=`{"code":"TIMEOUT","message":"..."}`；请求 ID 和 config_version 必须回传。`none` 是保留的模型无匹配标记，真实 ID 不得为 none。只有合法且未失效的结果可展示，不自动粘贴。2 秒交互预算由桌面强制执行，超时回收进程并最多自动重启一次。

## Swift core API

`ClipboardEntry: Identifiable,Codable,Equatable`：id String、text String、copiedAt Date、sourceApp String?、sourceBundleID String?、contentHash String。
`HistoryStore(directory: URL,maxBytes:Int=20000000,retention:TimeInterval=259200)` throwing init；`entries: [ClipboardEntry]` recent first；`add(text:sourceApp:sourceBundleID:now:) throws -> ClipboardEntry?`；`prune(now:) throws`；`delete(id:) throws`；`clear() throws`；`search(_ query:String) -> [ClipboardEntry]`；`bytesUsed: Int`。
`CandidateRanker.shortlist(entries: [ClipboardEntry],context: String,limit:Int=6) -> [ClipboardEntry]`，保留最近2条再填相关项。

## 验收

Swift 测试、Python 测试与 lint、release 构建；至少60条冻结双语样例，两模型和最近项/检索基线同输入；Chrome/Safari/TextEdit 合成业务。保存真实模型原始响应和版本，报告通过、失败和阻断项。发布前核验暂存、身份、远程、CI；完成状态按证据更新。
