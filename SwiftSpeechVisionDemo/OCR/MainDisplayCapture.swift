import AppKit
import CoreGraphics

enum MainDisplayCapture {
    /// Arka plan iş parçacığında güvenli: AppKit `NSImage` kullanmaz (sadece CoreGraphics).
    static func captureMainDisplayCGImage() -> CGImage? {
        CGDisplayCreateImage(CGMainDisplayID())
    }

    /// Ana ekranın tam görüntüsü (UI / ana iş parçacığı için).
    static func captureMainDisplayImage() -> NSImage? {
        guard let cgImage = captureMainDisplayCGImage() else { return nil }
        let size = NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        return NSImage(cgImage: cgImage, size: size)
    }
}
