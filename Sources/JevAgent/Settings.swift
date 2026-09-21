import AppKit
import Carbon
import Security

final class Settings {
    private let defaults = UserDefaults.standard
    var provider: String {
        get { defaults.string(forKey: "provider") ?? ProcessInfo.processInfo.environment["JEV_AGENT_PROVIDER"] ?? "laya" }
        set { defaults.set(newValue == "jev" ? "jev" : "laya", forKey: "provider") }
    }
    var model: String {
        get { defaults.string(forKey: "model") ?? ProcessInfo.processInfo.environment["TYPESAFE_DEFAULT_MODEL"] ?? "jev-1.13.0" }
        set { defaults.set(newValue, forKey: "model") }
    }
    var paused: Bool {
        get { defaults.bool(forKey: "paused") }
        set { defaults.set(newValue, forKey: "paused") }
    }
    var excluded: Set<String> {
        get { Set(defaults.stringArray(forKey: "excluded") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "excluded") }
    }
    var shortcutKey: UInt32 {
        get { defaults.object(forKey: "shortcutKey") == nil ? 9 : UInt32(defaults.integer(forKey: "shortcutKey")) }
        set { defaults.set(Int(newValue), forKey: "shortcutKey") }
    }
    var shortcutModifiers: UInt32 {
        get { defaults.object(forKey: "shortcutModifiers") == nil ? UInt32(cmdKey | shiftKey) : UInt32(defaults.integer(forKey: "shortcutModifiers")) }
        set { defaults.set(Int(newValue), forKey: "shortcutModifiers") }
    }
    var title: String { provider == "jev" ? "Jev · Cloud" : "Laya · Local" }
}

enum Keychain {
    private static let service = "ai.jev.agent"
    static func read() throws -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "typesafe",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "JevKeychain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Stored credential is not valid UTF-8."])
        }
        return value
    }
    static func save(_ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "typesafe"]
        let data = Data(value.utf8)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(updated)) }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

final class HotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let owner = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { owner.action?() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(key: UInt32, modifiers: UInt32) -> Bool {
        // Register first, retaining the old binding if the replacement conflicts.
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x4A455641, id: 1),
                                        GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr else { return false }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        return true
    }
    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
