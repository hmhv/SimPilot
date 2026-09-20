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

// MARK: - Hinge angle stream

/// `devicectl device motion hinge-angle` has no one-shot mode: it streams for a
/// minute and `--session-timeout` does not cut the session short enough to
/// produce a JSON document. So the angle is scraped off the first text line of
/// the stream, and that line's shape is a contract.
final class HingeAngleParseTests: XCTestCase {

    /// Verbatim from `xcrun devicectl device motion hinge-angle` against an
    /// iPhone Duo simulator on Xcode 27.1.
    private let stream = """
    Hinge angle monitoring started. 60 seconds remaining:
    • +0.000s : Angle:130.0°  Mech:130.0°  Velocity:+0.0°/s  AngleValid:Y  VelocityValid:N  Range:0-180°

    """

    func testReadsTheFirstAngleSample() {
        XCTAssertEqual(DeviceCtl.parseHingeAngle(stream), 130.0)
    }

    /// `Mech:` carries the same number and appears on the same line; the reading
    /// must come from `Angle:`, not from whichever matches first by accident.
    func testPrefersAngleOverMech() {
        let disagreeing = "• +0.000s : Angle:0.0°  Mech:12.5°  Velocity:+0.0°/s\n"
        XCTAssertEqual(DeviceCtl.parseHingeAngle(disagreeing), 0.0)
    }

    /// A shut Duo reads exactly 0, which must not be confused with "no reading".
    func testZeroIsAReading() {
        XCTAssertEqual(DeviceCtl.parseHingeAngle("• +0.000s : Angle:0.0°  Mech:0.0°\n"), 0.0)
    }

    /// devicectl right-aligns the number in a fixed column, so anything under
    /// 100° arrives padded. Verbatim from a shut Duo — this exact line parsed as
    /// "no reading" until the padding was skipped, which made `fold-state`
    /// report a null angle for every pose except wide open.
    func testPaddedAngleIsRead() {
        let padded = "• +0.000s : Angle:  0.0°  Mech:  0.0°  Velocity:+0.0°/s  AngleValid:Y  VelocityValid:N  Range:0-180°\n"
        XCTAssertEqual(DeviceCtl.parseHingeAngle(padded), 0.0)
        XCTAssertEqual(DeviceCtl.parseHingeAngle("• +0.000s : Angle: 45.5°  Mech: 45.5°\n"), 45.5)
    }

    /// A read can land in the middle of the number. The caller stops at the
    /// first reading it gets and kills the stream, so a prefix is never
    /// corrected: `Angle:13` out of a chunk about to continue `0.0°` would be
    /// reported as 13°, and the harness would restore the device to 13° instead
    /// of 130°. Only text before the last newline is complete.
    func testAHalfArrivedLineIsNotAReading() {
        XCTAssertNil(DeviceCtl.parseHingeAngle("• +0.000s : Angle:13"))
        XCTAssertNil(DeviceCtl.parseHingeAngle("• +0.000s : Angle:  4"))
        XCTAssertNil(DeviceCtl.parseHingeAngle(
            "Hinge angle monitoring started. 60 seconds remaining:\n• +0.000s : Angle:13"))
    }

    /// …and the next chunk completing that line yields the real value.
    func testTheSameLineReadsOnceItIsComplete() {
        XCTAssertEqual(DeviceCtl.parseHingeAngle("• +0.000s : Angle:130.0°  Mech:130.0°\n"), 130.0)
    }

    /// The banner arrives before the first sample; a partial read must not be
    /// mistaken for an answer.
    func testBannerAloneIsNotAnAnswer() {
        XCTAssertNil(DeviceCtl.parseHingeAngle("Hinge angle monitoring started. 60 seconds remaining:\n"))
        XCTAssertNil(DeviceCtl.parseHingeAngle(""))
    }

    func testDeviceWithoutAHingeYieldsNothing() {
        XCTAssertNil(DeviceCtl.parseHingeAngle("Hinge angle monitoring is not available on this device.\n"))
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
    /// uncertain band made a fold to exactly 80° or 85° skip waiting for the
    /// handover it was about to cause, so the next step read the outgoing
    /// screen.
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
        XCTAssertNil(HingeControl.impliedRole(atAngle: 81))
        XCTAssertNil(HingeControl.impliedRole(atAngle: 84))
        XCTAssertNil(HingeControl.impliedRole(atAngle: 82.5))
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
