/// 面板生命周期的纯状态机；调用方在主线程持有，异步回调必须携带返回的令牌。
public struct NativeSession: Sendable {
    public struct RequestToken: Equatable, Sendable {
        fileprivate let generation: UInt64
    }
    public struct PasteToken: Equatable, Sendable {
        fileprivate let generation: UInt64
        fileprivate let confirmation: UInt64
    }
    public enum ResponseDisposition: Equatable, Sendable {
        case applySelection
        case preserveSelection
    }

    public private(set) var isOpen = false
    public private(set) var hasManualSelection = false
    public private(set) var hasAttemptedRequest = false
    public var pasteInFlight: Bool { pendingPaste != nil }
    private var generation: UInt64 = 0
    private var confirmation: UInt64 = 0
    private var pendingRequest: RequestToken?
    private var pendingPaste: PasteToken?

    public init() {}

    /// 新面板是新交互；旧推荐和延迟粘贴都失效。
    public mutating func open() {
        generation &+= 1
        isOpen = true
        hasManualSelection = false
        hasAttemptedRequest = false
        pendingRequest = nil
        cancelPaste()
    }

    /// 取消、目标变更、配置变更共用这个边界；必须重新打开才允许请求。
    public mutating func invalidate() {
        generation &+= 1
        isOpen = false
        pendingRequest = nil
        cancelPaste()
    }

    public mutating func selectManually() { hasManualSelection = true }

    /// 每次交互只允许一次请求。超时、进程恢复、重复 ready 不能清除此锁存。
    public mutating func beginRequest() -> RequestToken? {
        guard isOpen, !hasManualSelection, !hasAttemptedRequest else { return nil }
        hasAttemptedRequest = true
        let token = RequestToken(generation: generation)
        pendingRequest = token
        return token
    }

    /// 完成一次请求，拒绝重复或旧回调；手动选择只允许状态提示，不移动选中项。
    public mutating func resolveRequest(_ token: RequestToken) -> ResponseDisposition? {
        guard isOpen, token.generation == generation, pendingRequest == token else { return nil }
        pendingRequest = nil
        return hasManualSelection ? .preserveSelection : .applySelection
    }

    public mutating func beginPaste() -> PasteToken? {
        guard isOpen, pendingPaste == nil else { return nil }
        hasManualSelection = true
        confirmation &+= 1
        let token = PasteToken(generation: generation, confirmation: confirmation)
        pendingPaste = token
        return token
    }

    public func acceptsPaste(_ token: PasteToken) -> Bool {
        isOpen && token.generation == generation && pendingPaste == token
    }

    /// 在最终提交事件前消费令牌，一次确认最多提交一次。
    public mutating func consumePaste(_ token: PasteToken) -> Bool {
        guard acceptsPaste(token) else { return false }
        cancelPaste()
        return true
    }

    public mutating func cancelPaste() { pendingPaste = nil }
}
