// DisplayResolverIntegrationTests.swift
//
// Gated integration test for per-screen capture.
//
// Background: SimBridge picks a framebuffer out of the several a simulator
// vends by matching the size of the screen it is told to capture. Before iPhone
// Duo it worked that size out itself, from whichever "Display class: 0" block
// `simctl io enumerate` listed first — fine while a device had one built-in
// screen. A Duo has two, both class 0, both vending a live framebuffer with the
// dark one solid black, and the enumeration order is not a promise. So the
// screen is now resolved in Swift, from devicectl's `active` flag, and passed
// down as an explicit size.
//
// This proves it end-to-end: on a real Duo, `.active` and the role selectors
// must come back at the right dimensions and the lit one must not be blank. It
// needs a booted simulator, so it no-ops unless SIPI_TEST_UDID names one — that
// keeps `swift test` green on a simulator-free CI box.

import XCTest
import Foundation
import SimCore
import SimNative
import SimShell

final class DisplayResolverIntegrationTests: XCTestCase {

    private var udid: String? {
        let value = ProcessInfo.processInfo.environment["SIPI_TEST_UDID"]
        return (value?.isEmpty == false) ? value : nil
    }

    private func capture(
        _ selector: DisplaySelection.Selector,
        udid: String
    ) throws -> (width: Int, height: Int, bytes: Int) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sipi-display-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try NativeDriver().screenshot(to: url, udid: udid, display: selector)

        let data = try Data(contentsOf: url)
        // PNG IHDR: 8-byte signature, 4-byte length, "IHDR", then width/height
        // as big-endian UInt32. Read it directly rather than pull in ImageIO.
        func be32(_ offset: Int) -> Int {
            (0..<4).reduce(0) { $0 << 8 | Int(data[offset + $1]) }
        }
        return (be32(16), be32(20), data.count)
    }

    /// `.active` must capture the screen the device is lighting, at that
    /// screen's pixel size — not the other one, and not the 7680x4320
    /// "Resizable" surface that is live and permanently black.
    func testActiveCaptureMatchesTheLitScreen() throws {
        guard let udid else {
            throw XCTSkip("SIPI_TEST_UDID not set; skipping live display-resolution test")
        }
        let displays = DisplayResolver.displays(udid: udid)
        try XCTSkipIf(displays.isEmpty, "devicectl cannot read this device's screens")
        guard let lit = DisplaySelection.active(displays) else {
            throw XCTSkip("no screen is lit; the device is asleep")
        }

        let shot = try capture(.active, udid: udid)
        XCTAssertEqual(shot.width, lit.pixelWidth)
        XCTAssertEqual(shot.height, lit.pixelHeight)
    }

    /// On a foldable, each role must resolve to its own screen and the lit one
    /// must have something on it. A dark screen compresses to a fraction of a
    /// live one, which is the whole failure this guards: before the fix a Duo
    /// capture could come back the right SIZE and still be blank.
    func testEachFoldableScreenCapturesAtItsOwnSize() throws {
        guard let udid else {
            throw XCTSkip("SIPI_TEST_UDID not set; skipping live display-resolution test")
        }
        let displays = DisplayResolver.displays(udid: udid)
        try XCTSkipIf(displays.count < 2, "not a foldable; nothing to choose between")

        let roles = DisplaySelection.roles(displays)
        let lit = try XCTUnwrap(DisplaySelection.active(displays), "no screen is lit")
        for display in displays {
            guard let role = roles[display.screenID], role != .screen else { continue }
            let byRole = try capture(.role(role), udid: udid)
            XCTAssertEqual(byRole.width, display.pixelWidth, "\(role.rawValue) width")
            XCTAssertEqual(byRole.height, display.pixelHeight, "\(role.rawValue) height")

            let byID = try capture(.screenID(display.screenID), udid: udid)
            XCTAssertEqual(byID.width, byRole.width, "screen \(display.screenID) by id and by role agree")

            if display.screenID == lit.screenID {
                // A solid-colour PNG of this size lands in the tens of KB; a
                // screen with a UI on it is megabytes.
                XCTAssertGreaterThan(
                    byRole.bytes, 500_000,
                    "the lit \(role.rawValue) screen captured blank"
                )
            }
        }
    }

    /// Naming a screen the device does not have fails loudly instead of quietly
    /// capturing the other one.
    func testNamingAMissingScreenThrows() throws {
        guard let udid else {
            throw XCTSkip("SIPI_TEST_UDID not set; skipping live display-resolution test")
        }
        let displays = DisplayResolver.displays(udid: udid)
        try XCTSkipIf(displays.isEmpty, "devicectl cannot read this device's screens")
        let missing = (displays.map { $0.screenID }.max() ?? 0) + 100
        XCTAssertThrowsError(try DisplayResolver.resolve(.screenID(missing), udid: udid))
    }
}

/// Gated integration test for folding a simulator.
///
/// Neither simctl nor devicectl can do this, so the whole path is private and
/// undocumented: a guest helper built against the iPhoneSimulator SDK, posting a
/// vendor-defined HID event. Everything about it could break with a toolchain
/// update, which is exactly why there is a live test — a unit test of our own
/// string formatting would not notice.
///
/// Needs a booted FOLDABLE, so it no-ops unless SIPI_TEST_UDID names one.
final class HingeControlIntegrationTests: XCTestCase {

    private var udid: String? {
        let value = ProcessInfo.processInfo.environment["SIPI_TEST_UDID"]
        return (value?.isEmpty == false) ? value : nil
    }

    private func foldableUDID() throws -> String {
        guard let udid else {
            throw XCTSkip("SIPI_TEST_UDID not set; skipping live hinge test")
        }
        try XCTSkipIf(
            DisplayResolver.displays(udid: udid).count < 2,
            "not a foldable; there is no hinge to move")
        return udid
    }

    /// The role of the lit screen, waited for rather than sampled.
    ///
    /// The handover trails the angle: the outgoing screen is still lit for a
    /// moment after the fold, so the first reading describes the pose that just
    /// ended. Polling until the EXPECTED role appears is what makes this an
    /// assertion about the fold rather than about timing — and returning the
    /// last reading on timeout keeps the failure message honest about what the
    /// device actually settled on.
    private func litRole(
        _ udid: String,
        expecting expected: DisplayRole,
        within seconds: TimeInterval = 3
    ) -> DisplayRole? {
        let deadline = Date().addingTimeInterval(seconds)
        var role: DisplayRole?
        repeat {
            let displays = DisplayResolver.displays(udid: udid)
            if let lit = DisplaySelection.active(displays) {
                role = DisplaySelection.roles(displays)[lit.screenID]
                if role == expected { return role }
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return role
    }

    /// Shutting the device must light the cover and opening it must light the
    /// inner screen — the whole point of the mechanism.
    func testFoldingMovesTheAngleAndHandsOverTheScreen() throws {
        let udid = try foldableUDID()
        let restore = DeviceCtl.hingeAngle(udid: udid)
        defer { if let restore { try? HingeControl.setAngle(udid: udid, degrees: restore) } }

        try HingeControl.setAngle(udid: udid, degrees: HingeControl.range.lowerBound)
        XCTAssertEqual(litRole(udid, expecting: .cover), .cover, "shut device should be showing its cover")
        XCTAssertEqual(DeviceCtl.hingeAngle(udid: udid), 0)

        try HingeControl.setAngle(udid: udid, degrees: HingeControl.range.upperBound)
        XCTAssertEqual(litRole(udid, expecting: .inner), .inner, "open device should be showing its inner screen")
        XCTAssertEqual(DeviceCtl.hingeAngle(udid: udid), 180)
    }

    /// The angle is a continuum, not two poses: a partly-folded device must
    /// report the angle it was given.
    func testAnIntermediateAngleIsHeld() throws {
        let udid = try foldableUDID()
        let restore = DeviceCtl.hingeAngle(udid: udid)
        defer { if let restore { try? HingeControl.setAngle(udid: udid, degrees: restore) } }

        try HingeControl.setAngle(udid: udid, degrees: 45)
        XCTAssertEqual(DeviceCtl.hingeAngle(udid: udid), 45)
    }

    /// Out-of-range input is clamped rather than sent, so a caller cannot drive
    /// the hinge somewhere the hardware has no pose for.
    func testAnglesAreClampedToTheHingeRange() throws {
        let udid = try foldableUDID()
        let restore = DeviceCtl.hingeAngle(udid: udid)
        defer { if let restore { try? HingeControl.setAngle(udid: udid, degrees: restore) } }

        try HingeControl.setAngle(udid: udid, degrees: 999)
        XCTAssertEqual(DeviceCtl.hingeAngle(udid: udid), 180)
        try HingeControl.setAngle(udid: udid, degrees: -20)
        XCTAssertEqual(DeviceCtl.hingeAngle(udid: udid), 0)
    }

    /// The helper is compiled on first use and cached. A second call must reuse
    /// it rather than rebuild, or every step of a suite would pay a compile.
    func testHelperIsBuiltOnceAndReused() throws {
        _ = try foldableUDID()
        let first = try HingeControl.helperPath()
        let second = try HingeControl.helperPath()
        XCTAssertEqual(first, second)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: first))
    }

    /// The published path must never be a build in progress.
    ///
    /// Compiling straight to the cache path publishes a half-written executable
    /// under the name everything treats as "the helper", and `isExecutableFile`
    /// cannot tell it from a good one — so a concurrent sipi, or the next run
    /// after an interrupted compile, spawns a truncated binary. The build
    /// happens under a scratch name and is renamed into place, and nothing
    /// scratch may survive a successful build.
    func testTheCacheHoldsNoHalfBuiltFiles() throws {
        _ = try foldableUDID()
        // From empty, so this asserts what THIS build leaves behind rather than
        // what the machine has accumulated from earlier sipi versions.
        try? FileManager.default.removeItem(at: HingeControl.cacheDirectory)
        let helper = try HingeControl.helperPath()
        XCTAssertFalse(helper.hasSuffix(".building"), helper)

        let leftovers = (try? FileManager.default.contentsOfDirectory(
            atPath: HingeControl.cacheDirectory.path)) ?? []
        XCTAssertTrue(
            leftovers.allSatisfy { !$0.hasSuffix(".building") && !$0.hasSuffix(".c") },
            "scratch files left in the cache: \(leftovers)")
    }

    /// Building twice concurrently must leave one good helper, not a torn one.
    func testConcurrentBuildsPublishAWorkingHelper() throws {
        let udid = try foldableUDID()
        let helper = try HingeControl.helperPath()
        try? FileManager.default.removeItem(atPath: helper)

        let group = DispatchGroup()
        var paths: [String?] = Array(repeating: nil, count: 4)
        var failures: [String] = []
        let lock = NSLock()
        for index in 0..<4 {
            DispatchQueue.global().async(group: group) {
                do {
                    let built = try HingeControl.helperPath()
                    lock.lock(); paths[index] = built; lock.unlock()
                } catch {
                    lock.lock(); failures.append(String(describing: error)); lock.unlock()
                }
            }
        }
        group.wait()

        let resolved = paths.compactMap { $0 }
        XCTAssertEqual(resolved.count, 4, "every build should have produced a path: \(failures)")
        XCTAssertEqual(Set(resolved).count, 1, "all builds should agree on one cached path")
        // The real proof is that the published file actually runs in the guest.
        XCTAssertNoThrow(try HingeControl.setAngle(udid: udid, degrees: 180))
    }
}
