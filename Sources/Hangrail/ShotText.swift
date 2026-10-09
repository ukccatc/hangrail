import AppKit
import Vision

/// On-device text recognition. Nothing leaves the Mac.
enum ShotText {
    static func recognize(_ url: URL, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let found = read(url)
            DispatchQueue.main.async { completion(found) }
        }
    }

    private static func read(_ url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
