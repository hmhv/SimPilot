// OrientationMath.swift
//
// Adapted for SimPilot from AXe (https://github.com/cameroncooke/AXe),
// origin: Sources/AXeCore/OrientationCoordinateMath.swift — MIT License
// (Copyright (c) 2025 Cameron Cooke; see THIRD_PARTY_LICENSES.md).
//
// Logical <-> physical coordinate translation used by taps/gestures when the
// simulator is rotated. The HID injector always works in the device's PHYSICAL
// (portrait, unrotated) coordinate space, while describe-ui frames and the
// resolver work in the LOGICAL space of the CURRENT UI orientation. When the
// simulator is rotated to landscape, a logical (x, y) read off the tree must be
// rotated into physical coordinates before it is injected, or the tap lands in
// the wrong place.
//
// Pure Foundation: no SimBridge, no private frameworks. The native orientation
// READ that feeds this (SimulatorKit.SimDeviceScreen.uiOrientation) lives in
// SimBridge / SimNative; this file is the framework-agnostic math.

import Foundation

public enum OrientationMath {
    /// Translate a LOGICAL point in the current UI orientation into the device's
    /// PHYSICAL (portrait, unrotated) coordinate space. `portraitWidth`/
    /// `portraitHeight` are the device's physical screen extents in the SAME unit
    /// as `x`/`y` (logical points, or normalized 0...1). For portrait the point
    /// passes through unchanged; the rotations match iOS's UI orientation enum
    /// (UIOrientation 1...4):
    ///   .portrait            (1) — identity.
    ///   .portraitUpsideDown  (2) — 180°.
    ///   .landscapeLeft       (3) — home button on the right; logical x runs along
    ///                              the physical height.
    ///   .landscapeRight      (4) — home button on the left; mirror of (3).
    public static func translateToPhysical(
        x: Double,
        y: Double,
        orientation: UIOrientation,
        portraitWidth: Double,
        portraitHeight: Double
    ) -> Point {
        switch orientation {
        case .portrait:
            return Point(x: x, y: y)

        case .portraitUpsideDown:
            return Point(x: portraitWidth - x, y: portraitHeight - y)

        case .landscapeLeft:
            return Point(x: y, y: portraitHeight - x)

        case .landscapeRight:
            return Point(x: portraitWidth - y, y: x)
        }
    }

    /// The PHYSICAL (portrait, unrotated framebuffer) extent that corresponds to a
    /// LOGICAL extent reported by describe-ui in the current orientation. In
    /// portrait/upside-down the logical and physical axes line up, so the extent
    /// passes through; in either landscape the logical width/height are the
    /// physical height/width (the framebuffer stays portrait while the UI rotates
    /// 90°). Empirically confirmed live: describe-ui reports 852x393 in landscape
    /// while the framebuffer / HID injection space stays 393x852 portrait.
    public static func physicalExtent(
        logicalWidth: Double,
        logicalHeight: Double,
        orientation: UIOrientation
    ) -> (width: Double, height: Double) {
        switch orientation {
        case .portrait, .portraitUpsideDown:
            return (logicalWidth, logicalHeight)
        case .landscapeLeft, .landscapeRight:
            return (logicalHeight, logicalWidth)
        }
    }

    /// Translate a NORMALIZED 0...1 logical point (a fraction of the CURRENT
    /// orientation's logical screen) into a NORMALIZED 0...1 point in the device's
    /// PHYSICAL (portrait framebuffer) space — exactly what the HID injector and
    /// the APT `objectAtPoint` hit-test consume. This is `translateToPhysical`
    /// expressed for the normalized→normalized case: the normalized logical point
    /// is first scaled to logical points by `logicalWidth`/`logicalHeight`,
    /// rotated/flipped into the portrait framebuffer, then renormalized by the
    /// physical extent. Portrait is a pass-through (identity).
    ///
    /// Live-verified (landscape-left, iPhone 16, iOS 26.4, Safari): the Safari
    /// address bar at landscape-logical center (426, 32) of an 852x393 tree maps
    /// to physical-normalized (~0.081, 0.5) — a tap there activates it and
    /// `objectAtPoint` there returns it.
    public static func normalizedToPhysical(
        normalizedX nx: Double,
        normalizedY ny: Double,
        orientation: UIOrientation,
        logicalWidth: Double,
        logicalHeight: Double
    ) -> Point {
        if orientation == .portrait { return Point(x: nx, y: ny) }

        // Logical normalized -> logical points in the current orientation.
        let lx = nx * logicalWidth
        let ly = ny * logicalHeight

        let physical = physicalExtent(
            logicalWidth: logicalWidth,
            logicalHeight: logicalHeight,
            orientation: orientation
        )

        // Rotate/flip logical points into the portrait framebuffer.
        let p = translateToPhysical(
            x: lx, y: ly, orientation: orientation,
            portraitWidth: physical.width, portraitHeight: physical.height
        )

        // Renormalize by the physical extent. Guard a degenerate extent.
        guard physical.width > 0, physical.height > 0 else { return Point(x: nx, y: ny) }
        return Point(x: p.x / physical.width, y: p.y / physical.height)
    }

    /// Map a point from the logical (letterboxed) layout into the physical screen
    /// rect. Used when a landscape-only app is presented scaled + centered inside
    /// a portrait physical screen: `scale`/`offsetX`/`offsetY` come from
    /// `letterboxParameters`.
    public static func letterboxToPhysical(
        x: Double,
        y: Double,
        scale: Double,
        offsetX: Double,
        offsetY: Double
    ) -> Point {
        Point(x: offsetX + x * scale, y: offsetY + y * scale)
    }

    /// Aspect-fit parameters for placing a logical rect inside a physical rect:
    /// the uniform `scale` plus the centering `offsetX`/`offsetY`. Returns a unit
    /// scale and zero offsets when either logical extent is non-positive (no
    /// usable letterbox).
    public static func letterboxParameters(
        logicalWidth: Double,
        logicalHeight: Double,
        physicalWidth: Double,
        physicalHeight: Double
    ) -> (scale: Double, offsetX: Double, offsetY: Double) {
        guard logicalWidth > 0, logicalHeight > 0 else { return (1, 0, 0) }
        let scale = min(physicalWidth / logicalWidth, physicalHeight / logicalHeight)
        let offsetX = (physicalWidth - logicalWidth * scale) / 2
        let offsetY = (physicalHeight - logicalHeight * scale) / 2
        return (scale, offsetX, offsetY)
    }
}
