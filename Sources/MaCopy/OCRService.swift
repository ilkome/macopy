import Foundation
import ImageIO
import SwiftData
import Vision

actor OCRService {
    static let shared = OCRService()

    func process(itemId: UUID, imagePath: String) async {
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
