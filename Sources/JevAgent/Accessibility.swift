import AppKit
import ApplicationServices

struct TargetSnapshot {
    let application: NSRunningApplication
    let element: AXUIElement?
    let range: CFRange?
    let context: [String: String]
    let readable: Bool
    let message: String
}

enum Accessibility {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        if let deadline = Thread.current.threadDictionary["JevCaptureDeadline"] as? Date {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            AXUIElementSetMessagingTimeout(element, Float(min(0.12, remaining)))
        } else { AXUIElementSetMessagingTimeout(element, 0.12) }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    static func string(_ element: AXUIElement, _ name: String, limit: Int = 512) -> String {
        String((attribute(element, name) as? String ?? "").unicodeScalars.prefix(limit))
    }
    static func focused(_ application: NSRunningApplication) -> AXUIElement? {
        let app = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.12)
        guard let value = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        guard AXValueGetType(ax) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(ax, .cfRange, &range) ? range : nil
    }
    static func capture(application app: NSRunningApplication?) -> TargetSnapshot? {
        // Capture runs off the main thread. Each proxy and the whole read share a finite budget.
        let deadline = Date().addingTimeInterval(0.65)
        Thread.current.threadDictionary["JevCaptureDeadline"] = deadline
        defer { Thread.current.threadDictionary.removeObject(forKey: "JevCaptureDeadline") }
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        var context = ["application": app.localizedName ?? "Unknown", "bundle_id": app.bundleIdentifier ?? ""]
        guard AXIsProcessTrusted(), let element = focused(app) else {
            return TargetSnapshot(application: app, element: nil, range: nil, context: context, readable: false,
                                  message: "Allow Accessibility in System Settings to read the focused field. Copy remains available.")
        }
        let role = string(element, kAXRoleAttribute)
        let subrole = string(element, kAXSubroleAttribute)
        guard subrole != kAXSecureTextFieldSubrole, role != "AXSecureTextField" else {
            return TargetSnapshot(application: app, element: nil, range: nil, context: [:], readable: false, message: "Secure fields are excluded. Choose a history item manually.")
        }
        context["role"] = role
        context["field_label"] = [string(element, kAXTitleAttribute), string(element, kAXDescriptionAttribute), string(element, "AXPlaceholderValue")].filter { !$0.isEmpty }.joined(separator: " · ")
        if let window = attribute(element, kAXWindowAttribute), CFGetTypeID(window) == AXUIElementGetTypeID() {
            context["window_title"] = string(window as! AXUIElement, kAXTitleAttribute)
        }
        let range = selectedRange(element)
        // AXStringForRange requests bounded text instead of reading the full document value.
        if let range {
            let start = max(0, range.location - 256)
            let count = (attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue
            let available = count.map { max(0, $0 - start) } ?? 512
            let nearby = CFRange(location: start, length: min(512, available))
            let selected = CFRange(location: range.location, length: min(512, range.length))
            for (key, rangeValue) in [("nearby_text", nearby), ("selected_text", selected)] {
                var requested = rangeValue
                if deadline.timeIntervalSinceNow > 0, let parameter = AXValueCreate(.cfRange, &requested) {
                    AXUIElementSetMessagingTimeout(element, Float(min(0.12, deadline.timeIntervalSinceNow)))
                    var output: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &output) == .success,
                       let text = output as? String { context[key] = String(text.unicodeScalars.prefix(512)) }
                }
            }
        }
        let readable = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
        return TargetSnapshot(application: app, element: element, range: range, context: context, readable: readable,
                              message: readable ? "" : "This field does not expose a supported text role. Copy is available.")
    }
    static func matches(_ target: TargetSnapshot) -> Bool {
        guard let expected = target.element, let actual = focused(target.application), CFEqual(expected, actual) else { return false }
        if let old = target.range {
            guard let new = selectedRange(actual), old.location == new.location, old.length == new.length else { return false }
        }
        return true
    }
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
