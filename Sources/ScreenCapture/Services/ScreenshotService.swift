import AppKit
import ImageIO
import ScreenCaptureKit

enum ScreenshotService {
    static func capture(target: CaptureTarget, showsCursor: Bool) async throws -> CGImage {
        let config = SCStreamConfiguration()
        config.width = Int(target.nativePixelSize.width.rounded())
        config.height = Int(target.nativePixelSize.height.rounded())
        config.showsCursor = showsCursor
        config.captureResolution = .best
        config.scalesToFit = true
        config.preservesAspectRatio = true
        config.colorSpaceName = CGColorSpace.sRGB
        if let rect = target.sourceRect { config.sourceRect = rect }
        return try await SCScreenshotManager.captureImage(contentFilter: target.filter, configuration: config)
    }

    /// Encodes and writes the image. Call off the main thread.
    nonisolated static func write(_ image: CGImage, to url: URL, format: ImageFormat) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var properties: [CFString: Any] = [:]
        if format != .png {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.9
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// PNG data for the clipboard. `NSImage` alone would put uncompressed TIFF there, which is huge and
    /// makes web apps (e.g. Google Chat) show a low-res preview until zoomed.
    nonisolated static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    @MainActor
    static func copyToPasteboard(_ image: CGImage) {
        NSPasteboard.general.clearContents()
        if let png = pngData(image) {
            NSPasteboard.general.setData(png, forType: .png)
        } else {
            NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: .zero)])
        }
    }
}
