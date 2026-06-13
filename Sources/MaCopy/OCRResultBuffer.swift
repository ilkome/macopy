import Foundation

/// Buffers OCR results and flushes them in a single batched DB write. Every `pool.write` wakes
/// the store's `ValueObservation`, which reconciles the full row projection; coalescing a
/// screenshot burst's N results into one write turns N store reconciles into ~1.
actor OCRResultBuffer {
    private var pending: [(UUID, String)] = []
    private var flushScheduled = false
    private let flushDelay: UInt64

    init(flushDelaySeconds: Double = 2) {
        self.flushDelay = UInt64(flushDelaySeconds * 1_000_000_000)
    }

    func add(id: UUID, text: String) {
        pending.append((id, text))
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { [flushDelay] in
            try? await Task.sleep(nanoseconds: flushDelay)
            self.flush()
        }
    }

    func flush() {
        flushScheduled = false
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll()
        // Rows deleted between buffering and flush simply match zero rows in the update.
        try? ClipboardItemRepository.batchUpdateOCR(batch)
    }
}
