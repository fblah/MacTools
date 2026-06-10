import XCTest
@testable import DMonteCore

/// Headless tests for `GlobalHotKey`'s shared-dispatch routing. Registering real Carbon hotkeys
/// needs a GUI session, so these drive the internal registry and `dispatch(signature:id:)`
/// directly — the exact lookup the shared Carbon callback performs. Guards the regression where
/// every hotkey in a process fired the same (most-recently-installed) handler because the
/// callback never read the event's `EventHotKeyID`.
final class GlobalHotKeyDispatchTests: XCTestCase {
    /// 'CLIP' — must match `GlobalHotKey.signature`.
    private let clipSignature = OSType(0x434C_4950)

    /// Lock-guarded firing log — the registry's handlers are `@Sendable`, so they can't
    /// mutate a captured local var directly.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [UInt32] = []

        func append(_ value: UInt32) {
            lock.lock()
            defer { lock.unlock() }
            values.append(value)
        }

        var fired: [UInt32] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    override func tearDown() {
        GlobalHotKey.handlersByID.removeAll()
        super.tearDown()
    }

    func testDispatchRoutesEachIDToItsOwnHandler() {
        let recorder = Recorder()
        GlobalHotKey.handlersByID[1] = { recorder.append(1) }
        GlobalHotKey.handlersByID[2] = { recorder.append(2) }
        GlobalHotKey.handlersByID[6] = { recorder.append(6) }

        XCTAssertTrue(GlobalHotKey.dispatch(signature: clipSignature, id: 2))
        XCTAssertTrue(GlobalHotKey.dispatch(signature: clipSignature, id: 6))
        XCTAssertTrue(GlobalHotKey.dispatch(signature: clipSignature, id: 1))

        // Each id must reach exactly its own handler, in firing order.
        XCTAssertEqual(recorder.fired, [2, 6, 1])
    }

    func testDispatchIgnoresUnknownID() {
        let recorder = Recorder()
        GlobalHotKey.handlersByID[1] = { recorder.append(1) }

        XCTAssertFalse(GlobalHotKey.dispatch(signature: clipSignature, id: 99))
        XCTAssertTrue(recorder.fired.isEmpty)
    }

    func testDispatchIgnoresForeignSignature() {
        let recorder = Recorder()
        GlobalHotKey.handlersByID[1] = { recorder.append(1) }

        let foreign = OSType(0x4F54_4852 /* 'OTHR' */)
        XCTAssertFalse(GlobalHotKey.dispatch(signature: foreign, id: 1))
        XCTAssertTrue(recorder.fired.isEmpty)
    }

    func testDispatchReportsUnhandledWhenRegistryIsEmpty() {
        XCTAssertFalse(GlobalHotKey.dispatch(signature: clipSignature, id: 1))
    }
}
