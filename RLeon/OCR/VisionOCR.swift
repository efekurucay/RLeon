import AppKit
import CoreGraphics
import Vision

/// High-quality path: `accurate`, full resolution (`minimumTextHeight == 0`), current `revision`,
/// language correction, merge observations in reading order, pick best candidate per region.
enum VisionOCR {
    static func recognizeText(
        from image: NSImage,
        languages: [String] = ["en-US", "tr-TR"]
    ) throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "VisionOCR", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create CGImage."])
        }
        return try recognizeText(from: cgImage, languages: languages)
    }

    /// Direct `CGImage` entry (safe on a background thread; no `NSImage` required).
    static func recognizeText(
        from cgImage: CGImage,
        languages: [String] = ["en-US", "tr-TR"]
    ) throws -> String {
        var resultText = ""
        var recognitionError: Error?

        let request = VNRecognizeTextRequest { request, error in
            if let error {
                recognitionError = error
                return
            }
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            resultText = Self.joinedText(from: observations)
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0
        request.revision = VNRecognizeTextRequest.currentRevision
        request.automaticallyDetectsLanguage = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        if let recognitionError {
            throw recognitionError
        }
        return resultText
    }

    /// Sort observations in reading order (top-to-bottom, left-to-right);
    /// for each region, take the highest-confidence string from `topCandidates`.
    private static func joinedText(from observations: [VNRecognizedTextObservation]) -> String {
        let sorted = observations.sorted { a, b in
            let dy = abs(a.boundingBox.midY - b.boundingBox.midY)
            if dy > 0.02 {
                return a.boundingBox.midY > b.boundingBox.midY
            }
            return a.boundingBox.minX < b.boundingBox.minX
        }

        return sorted.compactMap { observation in
            let candidates = observation.topCandidates(8)
            return candidates.max(by: { $0.confidence < $1.confidence })?.string
        }
        .joined(separator: "\n")
    }
}
