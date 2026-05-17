import Foundation

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
