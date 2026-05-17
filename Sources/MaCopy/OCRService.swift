import Foundation
import ImageIO
import os
import Vision

enum OCRService {
    private static let limiter = OCRConcurrencyLimiter(maxConcurrent: 2)
    private static let privacyLogger = Logger(subsystem: "dev.ilkome.MaCopy", category: "privacy.filter")
    private static let backfillFlag = "ocrSecretBackfill_v1_done"

    static func backfillRedactionsOnceIfNeeded(filterSecrets: Bool) async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: backfillFlag) { return }
        guard filterSecrets else { return }

        let items: [ClipboardItemRecord]
        do {
            items = try ClipboardRepository.itemsWithOCR()
        } catch {
            return
        }

        let pairs: [(UUID, String)] = items.compactMap { item in
            guard let text = item.ocrText, !text.isEmpty else { return nil }
            guard let kind = SecretDetector.detect(in: text) else { return nil }
            return (item.id, SecretDetector.redactedSentinel(for: kind))
        }

        if !pairs.isEmpty {
            do {
                try ClipboardRepository.batchUpdateOCR(pairs)
            } catch {
                return
            }
        }

        privacyLogger.info("ocr-backfill: scanned=\(items.count, privacy: .public) redacted=\(pairs.count, privacy: .public)")
        defaults.set(true, forKey: backfillFlag)
    }

    static func process(itemId: UUID, imagePath: String, filterSecrets: Bool) async {
        await limiter.acquire()
        await performOCR(itemId: itemId, imagePath: imagePath, filterSecrets: filterSecrets)
        await limiter.release()
    }

    static func sanitizedOCRText(_ recognized: String, filterSecrets: Bool) -> (text: String, redactedKind: SecretKind?) {
        guard filterSecrets, let kind = SecretDetector.detect(in: recognized) else {
            return (recognized, nil)
        }
        return (SecretDetector.redactedSentinel(for: kind), kind)
    }

    private static func performOCR(itemId: UUID, imagePath: String, filterSecrets: Bool) async {
        guard let data = try? ImageStore.read(filename: imagePath),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return }

        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["ru-RU", "en-US"]
        req.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([req]) } catch { return }

        let recognized = (req.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        guard !recognized.isEmpty else { return }

        guard (try? ClipboardRepository.findItem(byID: itemId)) != nil else { return }

        let result = sanitizedOCRText(recognized, filterSecrets: filterSecrets)
        if let kind = result.redactedKind {
            privacyLogger.info("ocr-redacted: \(kind.rawValue, privacy: .public)")
        }

        try? ClipboardRepository.updateOCR(id: itemId, text: result.text)
    }
}
