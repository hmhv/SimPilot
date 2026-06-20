// AccessibilityElement.swift
//
// Adapted for SimPilot from AXe (https://github.com/cameroncooke/AXe),
// origin: Sources/AXe/Utilities/AccessibilityElement.swift — MIT License
// (Copyright (c) 2025 Cameron Cooke; see THIRD_PARTY_LICENSES.md).
//
// AXe defines a private `AccessibilityElement` Decodable type with its own
// field set. SimPilot already has an equivalent value type, SimCore.AXNode
// (the describe-ui contract model), so this port reproduces AXe's element
// classification helpers — actionable / slider-like / switch-like detection,
// trimmed normalizers, flattening — as extensions on AXNode rather than
// duplicating the model. The classification logic and the actionable-type set
// are lifted verbatim from AXe; only the property accessors are retargeted to
// AXNode's field names.

import Foundation

extension AXNode {
    /// AXe's set of accessibility types treated as actionable (tappable). Lifted
    /// verbatim from AccessibilityElement.actionableTypes.
    static let actionableTypes: Set<String> = [
        "Button",
        "Cell",
        "CheckBox",
        "Link",
        "MenuItem",
        "PopUpButton",
        "RadioButton",
        "SecureTextField",
        "SegmentedControl",
        "Slider",
        "Switch",
        "Tab",
        "TabBarButton",
        "TextField",
        "Toggle"
    ]

    /// AXNode does not model AXe's separate `AXIdentifier`; SimCore's describe-ui
    /// contract only emits `AXUniqueId`. `normalizedUniqueId` falls back to it.
    var normalizedLabel: String? {
        Self.trimmed(AXLabel)
    }

    var normalizedUniqueId: String? {
        normalizedStableUniqueId
    }

    var normalizedStableUniqueId: String? {
        Self.trimmed(AXUniqueId)
    }

    var normalizedValue: String? {
        Self.trimmed(AXValue)
    }

    var isActionable: Bool {
        isSwitchLikeControl || isSliderLikeControl || type.map(Self.actionableTypes.contains) == true
    }

    var isSliderLikeControl: Bool {
        if type == "Slider" {
            return true
        }
        if role == "AXSlider" || subrole == "AXSlider" {
            return true
        }
        if let roleDescription = Self.trimmed(role_description)?.lowercased(),
           roleDescription.contains("slider") {
            return true
        }
        return false
    }

    var isSwitchLikeControl: Bool {
        if type == "Switch" || type == "Toggle" {
            return true
        }
        if role == "AXSwitch" || subrole == "AXSwitch" {
            return true
        }
        if let roleDescription = Self.trimmed(role_description)?.lowercased(),
           roleDescription.contains("switch") || roleDescription.contains("toggle") {
            return true
        }
        return false
    }

    /// Depth-first flatten of self + all descendants.
    func flattened() -> [AXNode] {
        var result: [AXNode] = [self]
        if let children {
            result.append(contentsOf: children.flatMap { $0.flattened() })
        }
        return result
    }

    func switchLikeDescendantsIncludingSelf() -> [AXNode] {
        flattened().filter(\.isSwitchLikeControl)
    }

    static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
