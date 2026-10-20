import CoreGraphics
import ImageIO
import XCTest
@testable import SimCore

/// A Duo inner capture that is turned the wrong way still has the right size,
/// so only the pixels show which way it went.
final class PNGRotateTests: XCTestCase {

    /// One clockwise turn takes the left edge to the top.
    func testAClockwiseTurnPutsTheLeftEdgeOnTop() throws {
        let png = try XCTUnwrap(Self.png(pixels: [[255, 0, 0, 255], [0, 0, 255, 255]], width: 2, height: 1))
        let turned = try XCTUnwrap(PNGRotate.rotated(png, quarterTurnsClockwise: 1))
        let pixels = try Self.pixels(turned)
        XCTAssertEqual(pixels.width, 1)
        XCTAssertEqual(pixels.height, 2)
        XCTAssertEqual(pixels.rgba[0], [255, 0, 0, 255], "top is the old left (red)")
        XCTAssertEqual(pixels.rgba[1], [0, 0, 255, 255], "bottom is the old right (blue)")
    }

    private static func png(pixels: [[UInt8]], width: Int, height: Int) -> Data? {
        var bytes = pixels.flatMap { $0 }
        guard let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage() else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }

    private static func pixels(_ png: Data) throws -> (width: Int, height: Int, rgba: [[UInt8]]) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let rgba = stride(from: 0, to: bytes.count, by: 4).map { Array(bytes[$0..<$0 + 4]) }
        return (image.width, image.height, rgba)
    }
}
