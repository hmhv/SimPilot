// PNGDownscaleTests.swift
//
// Locks the two contracts on one resampler: `resized` honours a pixel ceiling
// whatever the byte count does (the screenshot --max-pixel promise), and
// `downscaled` additionally refuses a re-encode that is not smaller (the report
// embedding promise).

import XCTest
import CoreGraphics
import ImageIO
@testable import SimCore

final class PNGDownscaleTests: XCTestCase {

    /// A PNG of the given size. `noisy` fills it with per-pixel noise so the
    /// encoding is large; otherwise a flat colour, which compresses to almost
    /// nothing at any size.
    private func png(width: Int, height: Int, noisy: Bool) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        if noisy {
            var rng = SystemRandomNumberGenerator()
            let buffer = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            for i in 0..<(context.bytesPerRow * height) { buffer[i] = UInt8.random(in: 0...255, using: &rng) }
        } else {
            context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let image = try XCTUnwrap(context.makeImage())
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    func testResizedRespectsTheCeilingOnTheLongSide() throws {
        let data = try png(width: 300, height: 120, noisy: true)
        let out = try XCTUnwrap(PNGDownscale.resized(data, maxPixel: 100))
        let size = try XCTUnwrap(PNGDownscale.pixelSize(of: out))
        XCTAssertEqual(size.width, 100)
        XCTAssertLessThanOrEqual(size.height, 40)
    }

    func testResizedLeavesAnImageWithinTheCeilingAlone() throws {
        let data = try png(width: 80, height: 60, noisy: true)
        XCTAssertNil(PNGDownscale.resized(data, maxPixel: 100))
        XCTAssertNil(PNGDownscale.resized(data, maxPixel: 80), "equal to the ceiling is within it")
        XCTAssertNil(PNGDownscale.resized(Data("not a png".utf8), maxPixel: 100))
        XCTAssertNil(PNGDownscale.resized(data, maxPixel: 0))
    }

    func testResizedHonoursTheCeilingEvenWhenBytesDoNotShrink() throws {
        // A flat image is a few hundred bytes at any size; resampling it can
        // come out no smaller. The dimension promise still holds.
        let data = try png(width: 400, height: 400, noisy: false)
        let out = try XCTUnwrap(PNGDownscale.resized(data, maxPixel: 50),
                                "a dimension ceiling is met regardless of the byte count")
        let size = try XCTUnwrap(PNGDownscale.pixelSize(of: out))
        XCTAssertEqual(max(size.width, size.height), 50)
    }

    func testDownscaledOnlyReturnsASmallerEncoding() throws {
        let noisy = try png(width: 400, height: 400, noisy: true)
        let shrunk = try XCTUnwrap(PNGDownscale.downscaled(noisy, maxPixel: 100))
        XCTAssertLessThan(shrunk.count, noisy.count)

        // Whatever `resized` does to a flat image, `downscaled` never hands back
        // more bytes than it was given.
        let flat = try png(width: 400, height: 400, noisy: false)
        if let out = PNGDownscale.downscaled(flat, maxPixel: 50) {
            XCTAssertLessThan(out.count, flat.count)
        }
    }
}
