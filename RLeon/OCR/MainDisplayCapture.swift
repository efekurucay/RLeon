import AppKit
import CoreGraphics

enum MainDisplayCapture {
    /// Safe on a background thread: CoreGraphics only (no AppKit `NSImage` here).
    static func captureMainDisplayCGImage() -> CGImage? {
        CGDisplayCreateImage(CGMainDisplayID())
    }

    /// Full main display image (for UI / main-thread use).
    static func captureMainDisplayImage() -> NSImage? {
        guard let cgImage = captureMainDisplayCGImage() else { return nil }
        let size = NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        return NSImage(cgImage: cgImage, size: size)
    }
}
