// PNGDownscale.swift
//
// Re-encode a PNG so its longest side fits a pixel budget. Shared by the HTML
// reports (which embed every step screenshot and would otherwise ship each one
// at device resolution) and by `sipi screenshot --max-pixel`, where a reader
// that pays per image token wants a thumbnail rather than a 3x capture.
//
// ImageIO does the resampling; the result keeps the PNG container so every
// consumer that could read the original can read the copy.

import Foundation
import ImageIO

public enum PNGDownscale {
    /// Re-encode `data` as a PNG whose longest side is at most `maxPixel`, for a
    /// caller whose contract is the dimension: `screenshot --max-pixel`.
    ///
    /// Returns nil when the image cannot be read or is already within the
    /// limit — the caller keeps the original bytes. Unlike `downscaled`, a
    /// resized encoding that happens to be larger in bytes is still returned,
    /// because the ceiling asked for is in pixels.
    public static func resized(_ data: Data, maxPixel: Int) -> Data? {
        guard maxPixel > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              max(width, height) > maxPixel else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, thumb, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// `resized`, for a caller whose contract is the byte count: the HTML
    /// reports embed either this or the original, whichever is smaller.
    ///
    /// Returns nil when the image cannot be read, is already within the limit,
    /// or the re-encode did not actually come out smaller — every one of those
    /// cases means the caller should keep the original bytes.
    public static func downscaled(_ data: Data, maxPixel: Int) -> Data? {
        guard let shrunk = resized(data, maxPixel: maxPixel), shrunk.count < data.count else { return nil }
        return shrunk
    }

    /// The pixel dimensions ImageIO reads from `data`, or nil when it is not an
    /// image it can decode.
    public static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }
}
