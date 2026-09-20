// DisplaySelectionTests.swift
//
// Locks the rules for choosing between a device's built-in screens. Every one of
// these is a case iPhone Duo actually produces: two screens of the same class,
// the SMALLER one marked primary, screen IDs 1 and 3, and exactly one of them
// lit at a time.

import XCTest
@testable import SimCore

final class DisplaySelectionTests: XCTestCase {

    /// iPhone Duo, Xcode 27.1, as `devicectl device info displays` reports it.
    private func duo(folded: Bool) -> [DeviceDisplay] {
        [
            DeviceDisplay(
                screenID: 1, name: "LCD", pixelWidth: 1398, pixelHeight: 2034,
                pointScale: 3, active: folded, primary: true,
                rotation: folded ? "rot0" : "rot90"
            ),
            DeviceDisplay(
                screenID: 3, name: "LCD-1", pixelWidth: 2007, pixelHeight: 2853,
                pointScale: 3, active: !folded, primary: false, rotation: "rot90"
            )
        ]
    }

    private let phone = [
        DeviceDisplay(
            screenID: 1, name: "LCD", pixelWidth: 1206, pixelHeight: 2622,
            pointScale: 3, active: true, primary: true, rotation: "rot0"
        )
    ]

    // MARK: - Roles

    func testLargerScreenIsInnerAndSmallerIsCover() {
        let roles = DisplaySelection.roles(duo(folded: false))
        XCTAssertEqual(roles[3], .inner)
        XCTAssertEqual(roles[1], .cover)
    }

    /// `primary` names the Duo's COVER, and screen ID 1 is the cover too — so
    /// neither can stand in for "the big one".
    func testRoleIgnoresPrimaryAndScreenID() {
        let displays = duo(folded: false)
        XCTAssertTrue(displays.first { $0.primary }?.screenID == 1)
        XCTAssertEqual(DisplaySelection.roles(displays)[1], .cover)
    }

    func testSingleScreenHasNoInnerOrCover() {
        XCTAssertEqual(DisplaySelection.roles(phone), [1: .screen])
    }

    /// A device with three screens is one this build has never seen. Guessing
    /// which is "inner" would be worse than declining to.
    func testThreeScreensGetNoGuessedRoles() {
        let three = phone + duo(folded: false).map {
            DeviceDisplay(screenID: $0.screenID + 10, pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight)
        }
        XCTAssertEqual(Set(DisplaySelection.roles(three).values.map { $0 }), [.screen])
    }

    // MARK: - Which screen is lit

    func testActiveIsTheLitScreenNotThePrimaryOne() {
        XCTAssertEqual(DisplaySelection.active(duo(folded: false))?.screenID, 3)
        XCTAssertEqual(DisplaySelection.active(duo(folded: true))?.screenID, 1)
    }

    /// An asleep foldable lights nothing. Falling back to `primary` would answer
    /// "the cover" about a device that is open, so there is no fallback.
    func testNothingLitIsNotTheSameAsPrimary() {
        let asleep = duo(folded: false).map {
            DeviceDisplay(
                screenID: $0.screenID, name: $0.name, pixelWidth: $0.pixelWidth,
                pixelHeight: $0.pixelHeight, pointScale: $0.pointScale,
                active: false, primary: $0.primary
            )
        }
        XCTAssertNil(DisplaySelection.active(asleep))
        XCTAssertNil(DisplaySelection.isFolded(asleep))
    }

    /// devicectl reports `active` only where there is something to choose
    /// between, so a phone's one screen carries no flag. Reading that absence as
    /// "off" would refuse to capture every non-foldable — measured on an
    /// iPhone 17 / iOS 27.0, whose displays document has no `active` key at all.
    func testOneUnflaggedScreenIsTheLitScreen() throws {
        let unflagged = [DeviceDisplay(screenID: 1, pixelWidth: 1206, pixelHeight: 2622, pointScale: 3)]
        XCTAssertEqual(DisplaySelection.active(unflagged)?.screenID, 1)
        XCTAssertEqual(try DisplaySelection.resolve(.active, in: unflagged).screenID, 1)
    }

    /// Two unflagged screens is a document this build cannot interpret — there
    /// IS something to choose between and nothing says which. Better to say so
    /// than to pick one.
    func testTwoUnflaggedScreensAnswerNothing() {
        let unflagged = duo(folded: false).map {
            DeviceDisplay(
                screenID: $0.screenID, pixelWidth: $0.pixelWidth,
                pixelHeight: $0.pixelHeight, pointScale: $0.pointScale, primary: $0.primary
            )
        }
        XCTAssertNil(DisplaySelection.active(unflagged))
    }

    // MARK: - Folded

    func testFoldedIsCoverLit() {
        XCTAssertEqual(DisplaySelection.isFolded(duo(folded: true)), true)
        XCTAssertEqual(DisplaySelection.isFolded(duo(folded: false)), false)
    }

    func testSingleScreenDeviceIsNeitherFoldedNorOpen() {
        XCTAssertNil(DisplaySelection.isFolded(phone))
    }

    // MARK: - Point size

    func testPointSizeDividesByScale() {
        let inner = duo(folded: false)[1]
        XCTAssertEqual(inner.pointWidth, 669)
        XCTAssertEqual(inner.pointHeight, 951)
        let cover = duo(folded: false)[0]
        XCTAssertEqual(cover.pointWidth, 466)
        XCTAssertEqual(cover.pointHeight, 678)
    }

    /// A scale devicectl did not report must not divide by zero.
    func testPointSizeSurvivesAMissingScale() {
        let unscaled = DeviceDisplay(screenID: 1, pixelWidth: 100, pixelHeight: 200, pointScale: 0)
        XCTAssertEqual(unscaled.pointWidth, 100)
    }

    // MARK: - Parsing what the caller typed

    func testParsesEveryAcceptedSelector() {
        XCTAssertEqual(DisplaySelection.parseSelector("active"), .active)
        XCTAssertEqual(DisplaySelection.parseSelector("inner"), .role(.inner))
        XCTAssertEqual(DisplaySelection.parseSelector("cover"), .role(.cover))
        XCTAssertEqual(DisplaySelection.parseSelector("3"), .screenID(3))
        XCTAssertEqual(DisplaySelection.parseSelector("  Cover "), .role(.cover))
    }

    func testRejectsWhatIsNotASelector() {
        XCTAssertNil(DisplaySelection.parseSelector("outer"))
        XCTAssertNil(DisplaySelection.parseSelector("primary"))
        XCTAssertNil(DisplaySelection.parseSelector(""))
        XCTAssertNil(DisplaySelection.parseSelector("0"))
        XCTAssertNil(DisplaySelection.parseSelector("-1"))
    }

    // MARK: - Resolving

    func testResolvesRolesAndIDsAndActive() throws {
        let open = duo(folded: false)
        XCTAssertEqual(try DisplaySelection.resolve(.active, in: open).screenID, 3)
        XCTAssertEqual(try DisplaySelection.resolve(.role(.cover), in: open).screenID, 1)
        XCTAssertEqual(try DisplaySelection.resolve(.screenID(1), in: open).screenID, 1)
    }

    /// Naming a screen the device does not have is a caller mistake. Quietly
    /// capturing a different screen is the failure `--display` exists to stop,
    /// so it throws — and the message lists what IS there.
    func testNamingAScreenTheDeviceLacksThrowsWithAnInventory() {
        XCTAssertThrowsError(try DisplaySelection.resolve(.role(.inner), in: phone)) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("no 'inner' screen"), message)
            XCTAssertTrue(message.contains("1206x2622"), message)
        }
        XCTAssertThrowsError(try DisplaySelection.resolve(.screenID(9), in: duo(folded: true))) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("no screen 9"), message)
            XCTAssertTrue(message.contains("cover"), message)
            XCTAssertTrue(message.contains("inner"), message)
        }
    }

    /// Explicit `active: false` is different from an absent flag: the system
    /// looked and said no.
    func testAskingForTheLitScreenOfAnAsleepDeviceThrows() {
        let asleep = [DeviceDisplay(screenID: 1, pixelWidth: 1206, pixelHeight: 2622, active: false)]
        XCTAssertThrowsError(try DisplaySelection.resolve(.active, in: asleep)) { error in
            XCTAssertTrue(String(describing: error).contains("no screen is currently lit"))
        }
    }
}
