import XCTest
@testable import JevCore

final class SessionTests: XCTestCase {
    func testOneRequestPerPanelEvenAfterTimeoutOrWorkerRecovery() throws {
        var state = NativeSession()
        XCTAssertNil(state.beginRequest())
        state.open()
        let request = try XCTUnwrap(state.beginRequest())
        XCTAssertEqual(state.resolveRequest(request), .applySelection)
        XCTAssertNil(state.beginRequest())
        XCTAssertNil(state.resolveRequest(request))
    }
    func testManualSelectionDoesNotMoveOnLateResponse() throws {
        var state = NativeSession()
        state.open()
        let request = try XCTUnwrap(state.beginRequest())
        state.selectManually()
        XCTAssertEqual(state.resolveRequest(request), .preserveSelection)
        state.open()
        state.selectManually()
        XCTAssertNil(state.beginRequest())
    }
    func testOldResponseCannotCrossCancelReopenOrConfigurationChange() throws {
        var state = NativeSession()
        state.open()
        let old = try XCTUnwrap(state.beginRequest())
        state.invalidate()
        XCTAssertNil(state.resolveRequest(old))
        state.open()
        let current = try XCTUnwrap(state.beginRequest())
        XCTAssertNil(state.resolveRequest(old))
        XCTAssertEqual(state.resolveRequest(current), .applySelection)
    }
    func testPasteIsSingleFlightAndConsumedOnlyOnce() throws {
        var state = NativeSession()
        XCTAssertNil(state.beginPaste())
        state.open()
        let paste = try XCTUnwrap(state.beginPaste())
        XCTAssertNil(state.beginPaste())
        XCTAssertTrue(state.consumePaste(paste))
        XCTAssertFalse(state.consumePaste(paste))
    }
    func testDelayedPasteCannotCrossCancellationOrNewPanel() throws {
        var state = NativeSession()
        state.open()
        let cancelled = try XCTUnwrap(state.beginPaste())
        state.cancelPaste()
        XCTAssertFalse(state.acceptsPaste(cancelled))
        let old = try XCTUnwrap(state.beginPaste())
        state.open()
        XCTAssertFalse(state.consumePaste(old))
        let current = try XCTUnwrap(state.beginPaste())
        XCTAssertTrue(state.consumePaste(current))
    }
    func testConfigurationInvalidatesPendingPasteAndRequest() throws {
        var state = NativeSession()
        state.open()
        let request = try XCTUnwrap(state.beginRequest())
        let paste = try XCTUnwrap(state.beginPaste())
        state.invalidate()
        XCTAssertNil(state.resolveRequest(request))
        XCTAssertFalse(state.consumePaste(paste))
    }
}
