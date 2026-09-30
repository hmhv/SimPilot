import CoreGraphics
import ImageIO
import XCTest
@testable import SimCore

final class ContactSheetTests: XCTestCase {
    private func png(width: Int, height: Int, gray: CGFloat) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    /// The red channel at (x, y), y counted from the top of `png`.
    private func red(in png: Data, x: Int, y: Int) throws -> UInt8 {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // Bitmap memory runs top row first.
        return try XCTUnwrap(ctx.data).load(fromByteOffset: y * image.width * 4 + x * 4, as: UInt8.self)
    }

    /// Every capture is scaled to the requested height, and a check missing from
    /// one variant leaves its slot empty instead of shifting the columns.
    func testGridScalesCapturesAndKeepsColumnsAligned() throws {
        let light = ContactSheet.Cell(caption: ["iphone-light", "001_a"], png: png(width: 100, height: 200, gray: 1))
        let dark = ContactSheet.Cell(caption: ["iphone-dark", "001_a"], png: png(width: 100, height: 200, gray: 0))
        let sheet = try XCTUnwrap(ContactSheet.compose([[light, dark], [nil, dark]], height: 100))
        let size = try XCTUnwrap(PNGDownscale.pixelSize(of: sheet))
        let gap = ContactSheet.gap, strip = ContactSheet.captionStrip
        XCTAssertEqual(size.width, 50 + 50 + gap * 3)
        XCTAssertEqual(size.height, (strip + 100 + gap) * 2 + gap)

        // Centres of the four capture slots, top row first.
        let left = gap + 25, right = gap + 50 + gap + 25
        let top = gap + strip + 50, bottom = gap + (strip + 100 + gap) + strip + 50
        XCTAssertEqual(try red(in: sheet, x: left, y: top), 255, "row 1, column 1 is the light capture")
        XCTAssertEqual(try red(in: sheet, x: right, y: top), 0, "row 1, column 2 is the dark capture")
        XCTAssertEqual(try red(in: sheet, x: right, y: bottom), 0, "the dark capture stays in column 2")
        let empty = try red(in: sheet, x: left, y: bottom)
        XCTAssertTrue((90...170).contains(empty), "the missing slot shows the grey background, got \(empty)")
    }

    func testNothingDecodableComposesNothing() {
        XCTAssertNil(ContactSheet.compose([[ContactSheet.Cell(caption: ["x"], png: Data("nope".utf8))]], height: 100))
        XCTAssertNil(ContactSheet.compose([], height: 100))
    }
}
