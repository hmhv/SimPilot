// PNGRotate.swift
//
// Turn a PNG by quarter turns. A framebuffer is captured the way the panel is
// mounted, not the way it is being held: iPhone Duo's inner screen is a portrait
// panel (2007x2853) that apps use in landscape, so its captures come out on
// their side. Turning them upright makes a capture match the space describe-ui
// frames are in (951x669 points).

import CoreGraphics
import Foundation
import ImageIO

public enum PNGRotate {
    /// `data` turned clockwise by `quarterTurns` (negative turns go the other
    /// way), or nil when it cannot be read or turned. Zero turns is nil too:
    /// the caller keeps the original bytes.
    public static func rotated(_ data: Data, quarterTurnsClockwise quarterTurns: Int) -> Data? {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let width = image.width, height = image.height
        let (outWidth, outHeight) = turns % 2 == 0 ? (width, height) : (height, width)
        guard let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: outWidth, height: outHeight, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Core Graphics has y pointing up, so a clockwise turn is a negative angle.
        switch turns {
        case 1:
            context.translateBy(x: 0, y: CGFloat(outHeight))
            context.rotate(by: -.pi / 2)
        case 2:
            context.translateBy(x: CGFloat(outWidth), y: CGFloat(outHeight))
            context.rotate(by: .pi)
        default:
            context.translateBy(x: CGFloat(outWidth), y: 0)
            context.rotate(by: .pi / 2)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let turned = context.makeImage() else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, turned, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
