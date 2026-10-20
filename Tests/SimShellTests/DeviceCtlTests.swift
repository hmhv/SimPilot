// DeviceCtlTests.swift
//
// Pure-value coverage for the devicectl wrapper: the flag vocabulary it emits
// and the state shape it reports. No process is spawned — the calls that shell
// out are exercised by the live-simulator path, not by unit tests.
//
// The flag names here are a contract with `xcrun devicectl device settings
// appearance`; a rename there surfaces as an argument error at run time, so the
// spelling is locked.

import Foundation
import XCTest
@testable import SimShell

final class DeviceCtlTests: XCTestCase {

    // MARK: - AppearanceSetting flags

    func testBooleanFacetsEmitOnOff() {
        XCTAssertEqual(AppearanceSetting.reduceMotion(true).arguments, ["--reduce-motion", "on"])
        XCTAssertEqual(AppearanceSetting.reduceMotion(false).arguments, ["--reduce-motion", "off"])
        XCTAssertEqual(AppearanceSetting.reduceTransparency(true).arguments, ["--reduce-transparency", "on"])
        XCTAssertEqual(AppearanceSetting.showBorders(false).arguments, ["--show-borders", "off"])
        XCTAssertEqual(AppearanceSetting.increaseContrast(true).arguments, ["--increase-contrast", "on"])
        XCTAssertEqual(AppearanceSetting.colorFilter(true).arguments, ["--color-filter", "on"])
        XCTAssertEqual(
            AppearanceSetting.largerAccessibilitySizes(true).arguments,
            ["--larger-accessibility-sizes", "on"])
    }

    func testStringFacetsPassValueThrough() {
        XCTAssertEqual(AppearanceSetting.mode("dark").arguments, ["--mode", "dark"])
        XCTAssertEqual(AppearanceSetting.lookAndFeel("tinted").arguments, ["--look-and-feel", "tinted"])
        XCTAssertEqual(AppearanceSetting.textSize("accessibility-large").arguments,
                       ["--text-size", "accessibility-large"])
        XCTAssertEqual(AppearanceSetting.colorFilterType("deuteranopia").arguments,
                       ["--color-filter-type", "deuteranopia"])
    }

    /// devicectl parses `0.5`, never `0,5`. Rendering must not follow the host
    /// locale, or this breaks on a machine set to a comma-decimal locale.
    func testNumericFacetsRenderLocaleIndependently() {
        XCTAssertEqual(AppearanceSetting.liquidGlassOpacity(0.5).arguments, ["--liquid-glass-opacity", "0.5"])
        XCTAssertEqual(AppearanceSetting.liquidGlassOpacity(1.0).arguments, ["--liquid-glass-opacity", "1"])
        XCTAssertEqual(AppearanceSetting.colorFilterIntensity(0.75).arguments,
                       ["--color-filter-intensity", "0.75"])
    }

    // MARK: - AppearanceState

    func testEmptyStateIsEmpty() {
        XCTAssertTrue(AppearanceState().isEmpty)
        XCTAssertFalse(AppearanceState(reduceMotion: false).isEmpty)
    }

    /// A nil facet means "unsupported / unknown", which must not serialize as
    /// `false` — a restore that wrote it back would leave the device in a state it
    /// was never in.
    func testUnknownFacetsAreOmittedFromJSON() {
        let state = AppearanceState(userInterfaceStyle: "dark", reduceMotion: false)
        let object = state.jsonObject
        XCTAssertEqual(object["user-interface-style"] as? String, "dark")
        XCTAssertEqual(object["reduce-motion"] as? Bool, false)
        XCTAssertNil(object["reduce-transparency"])
        XCTAssertNil(object["color-filter"])
    }

    func testJSONKeysAreKebabCase() {
        let state = AppearanceState(
            userInterfaceStyle: "light",
            lookAndFeel: "Liquid Glass",
            textSize: "Large",
            increaseContrast: false,
            reduceMotion: true,
            reduceTransparency: false,
            showBorders: false,
            liquidGlassOpacity: 0.5,
            colorFilterEnabled: true,
            colorFilterType: "grayscale",
            colorFilterIntensity: 1.0,
            largerAccessibilitySizes: false
        )
        XCTAssertEqual(Set(state.jsonObject.keys), [
            "user-interface-style", "look-and-feel", "text-size", "increase-contrast",
            "reduce-motion", "reduce-transparency", "show-borders", "liquid-glass-opacity",
            "color-filter", "color-filter-type", "color-filter-intensity", "larger-accessibility-sizes"
        ])
    }

    // MARK: - PhysicalOrientation

    /// `deviceOrientation` reads `faceUp` / `faceDown` / `unknown`; `flat` must be
    /// non-nil only for the two genuinely flat states, so an upright device is
    /// never reported as flat.
    func testFlatIsOnlySetForFlatOrientations() {
        XCTAssertEqual(
            DeviceCtl.PhysicalOrientation(deviceOrientation: "faceUp", nonFlat: "portrait", isLocked: false).flat,
            "face-up")
        XCTAssertEqual(
            DeviceCtl.PhysicalOrientation(deviceOrientation: "faceDown", nonFlat: "portrait", isLocked: false).flat,
            "face-down")
        XCTAssertNil(
            DeviceCtl.PhysicalOrientation(deviceOrientation: "portrait", nonFlat: "portrait", isLocked: false).flat)
        XCTAssertNil(
            DeviceCtl.PhysicalOrientation(deviceOrientation: "unknown", nonFlat: "portrait", isLocked: false).flat)
    }

    func testOrientationVocabularyCoversAllSix() {
        XCTAssertEqual(DeviceCtl.orientationNames.count, 6)
        XCTAssertTrue(DeviceCtl.orientationNames.contains("faceUp"))
        XCTAssertTrue(DeviceCtl.orientationNames.contains("faceDown"))
    }
}

// MARK: - Hinge angle formatting

/// The hinge angle crosses into a C program through `atof`, so it has to be
/// written the way C reads it — not the way the host's locale would.
final class HingeAngleFormatTests: XCTestCase {

    func testWholeDegreesHaveNoDecimalNoise() {
        XCTAssertEqual(HingeControl.format(0), "0")
        XCTAssertEqual(HingeControl.format(180), "180")
        XCTAssertEqual(HingeControl.format(90), "90")
    }

    func testFractionsSurvive() {
        XCTAssertEqual(HingeControl.format(82.5), "82.5")
        XCTAssertEqual(HingeControl.format(0.25), "0.25")
    }

    /// A comma decimal separator would reach `atof` as "22,5" and be truncated
    /// to 22 — a fold that silently lands 0.5° away, or a sweep that finishes
    /// early. The formatter pins POSIX regardless of the host's locale.
    func testDecimalSeparatorIsAPeriodWhateverTheHostLocaleIs() {
        let formatted = HingeControl.format(22.5)
        XCTAssertFalse(formatted.contains(","), formatted)
        XCTAssertEqual(Double(formatted), 22.5)
    }

    /// The angles the range's ends produce must round-trip, because `--closed`
    /// and `--open` are written from them.
    func testRangeEndsRoundTrip() {
        XCTAssertEqual(Double(HingeControl.format(HingeControl.range.lowerBound)), 0)
        XCTAssertEqual(Double(HingeControl.format(HingeControl.range.upperBound)), 180)
    }

    /// The measured handover points are what every fold waits on.
    func testHandoverPointsSitInsideTheHingeRange() {
        XCTAssertTrue(HingeControl.range.contains(HingeControl.lastCoverDegrees))
        XCTAssertTrue(HingeControl.range.contains(HingeControl.firstInnerDegrees))
        XCTAssertLessThan(HingeControl.lastCoverDegrees, HingeControl.firstInnerDegrees)
    }

    /// The MEASURED points are known, not unknown. Treating them as inside the
    /// uncertain band made a fold to exactly the last known angle skip waiting
    /// for the handover it was about to cause, so the next step read the
    /// outgoing screen.
    func testTheMeasuredHandoverPointsThemselvesAreKnown() {
        XCTAssertEqual(HingeControl.impliedRole(atAngle: HingeControl.lastCoverDegrees), .cover)
        XCTAssertEqual(HingeControl.impliedRole(atAngle: HingeControl.firstInnerDegrees), .inner)
    }

    func testTheEndsOfTheHingeImplyTheObviousScreens() {
        XCTAssertEqual(HingeControl.impliedRole(atAngle: 0), .cover)
        XCTAssertEqual(HingeControl.impliedRole(atAngle: 180), .inner)
    }

    /// Only the angles between the two measurements are unknown, and saying so
    /// is better than guessing: a wait for a screen that never lights costs the
    /// full timeout on every fold into that band.
    func testOnlyTheUnmeasuredMiddleIsUnknown() {
        XCTAssertNil(HingeControl.impliedRole(atAngle: 83))
        XCTAssertNil(HingeControl.impliedRole(atAngle: 87))
        XCTAssertNil(HingeControl.impliedRole(atAngle: 85.5))
    }

    /// The pose a run restores comes from this, so a stale record must not win
    /// over the screen that is lit: a device recorded shut but showing its inner
    /// screen was opened since, and restoring it to 0° would be wrong.
    func testTheRecordedAngleYieldsToTheLitScreenAtTheEnds() {
        XCTAssertEqual(HingeControl.reconcile(recorded: 0, lit: .inner), 180)
        XCTAssertEqual(HingeControl.reconcile(recorded: 180, lit: .cover), 0)
        XCTAssertEqual(HingeControl.reconcile(recorded: nil, lit: .cover), 0)
        XCTAssertEqual(HingeControl.reconcile(recorded: nil, lit: .inner), 180)
        XCTAssertEqual(HingeControl.reconcile(recorded: 120, lit: .inner), 120)
        XCTAssertEqual(HingeControl.reconcile(recorded: 50, lit: .inner), 50)
    }
}

// MARK: - recordVideo command line

/// `--display` is positional in a way simctl's help does not make obvious: it is
/// listed under "Common arguments" but only accepted after the operation. Before
/// it, simctl prints usage and exits 117 having recorded nothing — and the only
/// symptom is a missing file when the run ends.
final class RecordVideoArgumentsTests: XCTestCase {

    func testDisplayFollowsTheOperation() {
        let args = SimShell.recordVideoArguments(udid: "U", outputPath: "/tmp/v.mp4", screenID: 3)
        let operation = try! XCTUnwrap(args.firstIndex(of: "recordVideo"))
        let display = try! XCTUnwrap(args.firstIndex(of: "--display=3"))
        XCTAssertGreaterThan(display, operation, "\(args)")
    }

    func testNoDisplayFlagWhenNoScreenIsNamed() {
        let args = SimShell.recordVideoArguments(udid: "U", outputPath: "/tmp/v.mp4", screenID: nil)
        XCTAssertFalse(args.contains { $0.hasPrefix("--display") }, "\(args)")
    }

    /// The output path is the trailing positional; a flag appended after it
    /// would be read as the path.
    func testOutputPathStaysLast() {
        for screenID in [nil, 1, 3] {
            let args = SimShell.recordVideoArguments(
                udid: "U", outputPath: "/tmp/v.mp4", screenID: screenID)
            XCTAssertEqual(args.last, "/tmp/v.mp4", "\(args)")
        }
    }

    func testTheUDIDPrecedesTheOperation() {
        let args = SimShell.recordVideoArguments(udid: "U", outputPath: "/tmp/v.mp4", screenID: 1)
        XCTAssertEqual(Array(args.prefix(4)), ["simctl", "io", "U", "recordVideo"])
    }
}
