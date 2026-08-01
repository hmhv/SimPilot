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
