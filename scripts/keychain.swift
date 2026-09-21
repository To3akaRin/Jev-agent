import Foundation
import Security

// 仅通过 stdin 接收凭据；不接受明文命令行参数。
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "ai.jev.agent",
    kSecAttrAccount as String: "typesafe"
]
let mode = CommandLine.arguments.dropFirst().first ?? "read"
if mode == "store" {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let text = String(data: input, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { exit(2) }
    let secret = Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: secret] as CFDictionary)
    if status == errSecItemNotFound {
        var attributes = query
        attributes[kSecValueData as String] = secret
        let created = SecItemAdd(attributes as CFDictionary, nil)
        guard created == errSecSuccess else { fputs("Keychain store failed: \(created)\n", stderr); exit(1) }
    } else if status != errSecSuccess {
        fputs("Keychain update failed: \(status)\n", stderr); exit(1)
    }
} else if mode == "read" {
    var attributes = query
    attributes[kSecReturnData as String] = true
    attributes[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(attributes as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { exit(1) }
    FileHandle.standardOutput.write(data)
} else { exit(2) }
