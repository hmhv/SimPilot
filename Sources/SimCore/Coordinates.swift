// Coordinates.swift
//
// Coordinate-unit standardization. The driver layer works exclusively in
// normalized 0...1 of the screen. CLI inputs
// arrive either already normalized (`--norm`, the default) or as logical pixels
// (`--pixel`), and MUST be converted into the same internal 0...1 representation
// before any tap/swipe/touch/describe-point. Without this, "pixel coordinates
// fed as normalized -> top-left tap" is a latent bug; the same convention is
// applied to tap, swipe, AND describe-point so they cannot diverge.
//
// Pure Foundation: no SimBridge, no private frameworks.

import Foundation

/// How a CLI coordinate pair is expressed before it is converted to the internal
/// normalized 0...1 space.
public enum CoordinateUnit: String, Sendable, CaseIterable {
    /// Already normalized 0...1 of the screen (the internal representation).
    case norm
    /// Logical screen pixels (points). Converted with the screen size.
    case pixel
}

/// The screen size used to convert pixel coordinates into normalized 0...1. This
/// is the logical point size of the screen (the describe-ui root frame's
/// width/height), the same space `axe tap --x --y` works in.
public struct ScreenSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// Errors raised while validating / converting coordinate inputs (Gate 4).
public enum CoordinateError: Error, CustomStringConvertible, Equatable {
    case normalizedOutOfRange(axis: String, value: Double)
    case negativePixel(axis: String, value: Double)
    case missingScreenSize
    case invalidScreenSize(width: Double, height: Double)
    case pixelOutOfBounds(axis: String, value: Double, extent: Double)

    public var description: String {
        switch self {
        case .normalizedOutOfRange(let axis, let value):
            return "Normalized \(axis)=\(value) is out of range. With --norm, coordinates must be 0...1; pass --pixel for pixel coordinates."
        case .negativePixel(let axis, let value):
            return "Pixel \(axis)=\(value) must be non-negative."
        case .missingScreenSize:
            return "Could not determine the screen size to convert pixel coordinates. Make sure the simulator is booted and showing UI."
        case .invalidScreenSize(let width, let height):
            return "Screen size (\(width)x\(height)) has no positive extent; cannot convert pixel coordinates."
        case .pixelOutOfBounds(let axis, let value, let extent):
            return "Pixel \(axis)=\(value) is outside the screen extent (\(extent)). Pixel coordinates must lie within the screen; pass --norm for normalized 0...1."
        }
    }
}

public enum CoordinateConverter {
    /// Convert a CLI coordinate pair into the internal normalized 0...1 Point.
    ///
    /// - `unit == .norm`: `x`/`y` must already be 0...1 (validated). `screen` is
    ///   ignored. This is the internal representation.
    /// - `unit == .pixel`: `x`/`y` are logical pixels; `screen` is required and
    ///   must have a positive extent. The result is `(x/width, y/height)`,
    ///   validated to land within the screen so a pixel value can never be
    ///   silently reinterpreted as a top-left normalized tap (Gate 4).
    public static func normalize(
        x: Double,
        y: Double,
        unit: CoordinateUnit,
        screen: ScreenSize?
    ) throws -> Point {
        switch unit {
        case .norm:
            guard x >= 0, x <= 1 else {
                throw CoordinateError.normalizedOutOfRange(axis: "x", value: x)
            }
            guard y >= 0, y <= 1 else {
                throw CoordinateError.normalizedOutOfRange(axis: "y", value: y)
            }
            return Point(x: x, y: y)

        case .pixel:
            guard x >= 0 else { throw CoordinateError.negativePixel(axis: "x", value: x) }
            guard y >= 0 else { throw CoordinateError.negativePixel(axis: "y", value: y) }
            guard let screen else { throw CoordinateError.missingScreenSize }
            guard screen.width > 0, screen.height > 0 else {
                throw CoordinateError.invalidScreenSize(width: screen.width, height: screen.height)
            }
            guard x <= screen.width else {
                throw CoordinateError.pixelOutOfBounds(axis: "x", value: x, extent: screen.width)
            }
            guard y <= screen.height else {
                throw CoordinateError.pixelOutOfBounds(axis: "y", value: y, extent: screen.height)
            }
            return Point(x: x / screen.width, y: y / screen.height)
        }
    }
}
