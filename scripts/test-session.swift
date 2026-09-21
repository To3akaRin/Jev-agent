import Foundation

@main
struct SessionRegression {
    static func main() throws {
        var passed = 0
        func check(_ name: String, _ body: () throws -> Void) rethrows {
            try body()
            passed += 1
            print("PASS \(name)")
        }
        func expect(_ value: Bool, _ message: String) {
            guard value else { fputs("FAIL \(message)\n", stderr); exit(1) }
        }
        check("closed panel cannot request or paste") {
            var state = NativeSession()
            expect(state.beginRequest() == nil, "closed request")
            expect(state.beginPaste() == nil, "closed paste")
        }
        check("timeout and ready notifications cannot cause a second request") {
            var state = NativeSession()
            state.open()
            let token = state.beginRequest()!
            expect(state.resolveRequest(token) == .applySelection, "first result")
            for _ in 0..<10 { expect(state.beginRequest() == nil, "retry after completion") }
            expect(state.resolveRequest(token) == nil, "duplicate response")
        }
        check("late response preserves a manual selection") {
            var state = NativeSession()
            state.open()
            let token = state.beginRequest()!
            state.selectManually()
            expect(state.resolveRequest(token) == .preserveSelection, "manual choice overwritten")
        }
        check("manual selection before ready suppresses request") {
            var state = NativeSession()
            state.open()
            state.selectManually()
            expect(state.beginRequest() == nil, "manual then ready")
        }
        check("cancel and reopen reject previous response") {
            var state = NativeSession()
            state.open()
            let old = state.beginRequest()!
            state.invalidate()
            state.open()
            let new = state.beginRequest()!
            expect(old != new, "request epochs reused")
            expect(state.resolveRequest(old) == nil, "stale response")
            expect(state.resolveRequest(new) == .applySelection, "fresh response")
        }
        check("configuration switch invalidates request and pending paste") {
            var state = NativeSession()
            state.open()
            let request = state.beginRequest()!
            let paste = state.beginPaste()!
            state.invalidate()
            expect(state.resolveRequest(request) == nil, "old provider response")
            expect(!state.acceptsPaste(paste), "old configuration paste")
        }
        check("paste confirmation is single flight and single use") {
            var state = NativeSession()
            state.open()
            let paste = state.beginPaste()!
            expect(state.beginPaste() == nil, "duplicate confirmation")
            expect(state.consumePaste(paste), "first confirmation")
            expect(!state.consumePaste(paste), "duplicate delivery")
        }
        check("cancel invalidates delayed paste closure") {
            var state = NativeSession()
            state.open()
            let paste = state.beginPaste()!
            state.cancelPaste()
            expect(!state.acceptsPaste(paste), "cancelled delayed paste")
        }
        check("reopen invalidates paste even when focus returns to the same field") {
            var state = NativeSession()
            state.open()
            let old = state.beginPaste()!
            state.open()
            let new = state.beginPaste()!
            expect(!state.consumePaste(old), "old paste after reopen")
            expect(state.consumePaste(new), "new paste after reopen")
        }
        print("\(passed) native session regression scenarios passed")
    }
}
