import Foundation
import ImageIO
import SwiftData
import Vision

actor OCRConcurrencyLimiter {
    private let maxConcurrent: Int
    private var inUse: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func acquire() async {
        if inUse < maxConcurrent {
            inUse += 1
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            inUse -= 1
        }
    }
}

enum OCRService {
    private static let limiter = OCRConcurrencyLimiter(maxConcurrent: 2)

    static func process(itemId: UUID, imagePath: String) async {
        await limiter.acquire()
        await performOCR(itemId: itemId, imagePath: imagePath)
        await limiter.release()
    }

    private static func performOCR(itemId: UUID, imagePath: String) async {
        let fileURL = Storage.imageURL(for: imagePath)
        guard let data = try? Data(contentsOf: fileURL),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return }

        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["ru-RU", "en-US"]
        req.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([req]) } catch { return }

        let text = (req.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        guard !text.isEmpty else { return }

        await MainActor.run {
            let ctx = Storage.container.mainContext
            let id = itemId
            let predicate = #Predicate<ClipboardItem> { $0.id == id }
            var fetch = FetchDescriptor<ClipboardItem>(predicate: predicate)
            fetch.fetchLimit = 1
            if let item = try? ctx.fetch(fetch).first {
                item.ocrText = text
                try? ctx.save()
            }
        }
    }
}
