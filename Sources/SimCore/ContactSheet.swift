// ContactSheet.swift
//
// Lay a verify session's captures out as a grid in one PNG — a row per check, a
// column per variant — so a reader that pays per image and per turn looks at a
// few images instead of one per variant. `sipi verify-session sheet` writes them.
// A sheet is for looking, not evidence: the full-size captures stay where
// `verify-session capture` wrote them.

import CoreGraphics
import CoreText
import Foundation
import ImageIO

public enum ContactSheet {
    /// One cell: the two caption lines drawn above it (a column as narrow as a
    /// phone capture has no room for both on one), and the capture's PNG bytes.
    public struct Cell {
        public let caption: [String]
        public let png: Data
        public init(caption: [String], png: Data) {
            self.caption = caption
            self.png = png
        }
    }

    static let gap = 12
    static let lineHeight = 22
    static let captionStrip = 2 * lineHeight + 8

    /// Compose `rows` into one PNG, every capture scaled to `height` pixels tall.
    /// A nil cell leaves its slot empty so a check missing from one variant does
    /// not shift the columns. Returns nil when nothing decodes.
    public static func compose(_ rows: [[Cell?]], height: Int) -> Data? {
        guard height > 0 else { return nil }
        let images: [[(caption: [String], image: CGImage)?]] = rows.map { row in
            row.map { cell in
                guard let cell,
                      let source = CGImageSourceCreateWithData(cell.png as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      image.height > 0 else { return nil }
                return (cell.caption, image)
            }
        }
        let columns = images.map(\.count).max() ?? 0
        guard columns > 0, images.contains(where: { $0.contains { $0 != nil } }) else { return nil }

        func scaledWidth(_ image: CGImage) -> Int {
            max(1, Int((Double(image.width) * Double(height) / Double(image.height)).rounded()))
        }
        // Each column is as wide as its widest capture, so a column stays aligned
        // down the sheet even when a row lacks that variant.
        var columnWidths = Array(repeating: 0, count: columns)
        for row in images {
            for (index, cell) in row.enumerated() {
                if let cell { columnWidths[index] = max(columnWidths[index], scaledWidth(cell.image)) }
            }
        }
        for index in columnWidths.indices where columnWidths[index] == 0 {
            columnWidths[index] = height / 2
        }
        let rowHeight = captionStrip + height + gap
        let width = columnWidths.reduce(0, +) + gap * (columns + 1)
        let totalHeight = rowHeight * images.count + gap

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: totalHeight, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Mid grey, so both a light and a dark capture show where their edges are.
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: totalHeight))
        ctx.interpolationQuality = .high

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 17, nil)
        let textAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ]
        for (rowIndex, row) in images.enumerated() {
            // CoreGraphics puts the origin bottom-left; rows are laid out top-down.
            let top = totalHeight - gap - rowIndex * rowHeight
            var x = gap
            for (index, cell) in row.enumerated() {
                defer { x += columnWidths[index] + gap }
                guard let cell else { continue }
                let stripRect = CGRect(x: x, y: top - captionStrip, width: columnWidths[index], height: captionStrip)
                ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
                ctx.fill(stripRect)
                ctx.saveGState()
                ctx.clip(to: stripRect)
                for (lineIndex, text) in cell.caption.prefix(2).enumerated() {
                    let line = CTLineCreateWithAttributedString(
                        NSAttributedString(string: text, attributes: textAttributes))
                    ctx.textPosition = CGPoint(x: x + 8, y: top - 4 - lineHeight * (lineIndex + 1) + 6)
                    CTLineDraw(line, ctx)
                }
                ctx.restoreGState()
                ctx.draw(cell.image, in: CGRect(x: x, y: top - captionStrip - height,
                                                width: scaledWidth(cell.image), height: height))
            }
        }
        guard let image = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
