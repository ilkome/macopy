import Foundation

final class BoundedURLSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maxBytes: Int
    private let maxRedirects: Int
    private let originalHost: String?

    private let lock = NSLock()
    private var accumulator = Data()
    private var receivedBytes: Int = 0
    private var redirectCount: Int = 0
    private var savedResponse: URLResponse?
    private var continuation: CheckedContinuation<(Data, URLResponse)?, Never>?
    private var didResolve = false

    init(maxBytes: Int, maxRedirects: Int = 5, originalHost: String?) {
        self.maxBytes = maxBytes
        self.maxRedirects = maxRedirects
        self.originalHost = originalHost?.lowercased()
        super.init()
    }

    func fetch(request: URLRequest, session: URLSession) async -> (Data, URLResponse)? {
        await withCheckedContinuation { (cont: CheckedContinuation<(Data, URLResponse)?, Never>) in
            lock.lock()
            continuation = cont
            lock.unlock()
            session.dataTask(with: request).resume()
        }
    }

    private func resolve(_ result: (Data, URLResponse)?) {
        lock.lock()
        if didResolve {
            lock.unlock()
            return
        }
        didResolve = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: result)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        if response.expectedContentLength > Int64(maxBytes) {
            completionHandler(.cancel)
            return
        }
        lock.lock()
        savedResponse = response
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        lock.lock()
        receivedBytes += data.count
        let exceeded = receivedBytes > maxBytes
        if !exceeded {
            accumulator.append(data)
        }
        lock.unlock()
        if exceeded {
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        lock.lock()
        redirectCount += 1
        let count = redirectCount
        lock.unlock()

        if count > maxRedirects {
            completionHandler(nil)
            return
        }
        guard let url = request.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else {
            completionHandler(nil)
            return
        }

        let original = originalHost
        let crossOrigin = host.lowercased() != original
        Task.detached {
            let decision = await URLSafetyGate.validateResolved(host: host)
            guard decision == .allow else {
                completionHandler(nil)
                return
            }
            var sanitized = request
            if crossOrigin {
                sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
                sanitized.setValue(nil, forHTTPHeaderField: "Cookie")
            }
            completionHandler(sanitized)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        lock.lock()
        let data = accumulator
        let response = savedResponse
        lock.unlock()

        if error != nil {
            resolve(nil)
            return
        }
        guard let response else {
            resolve(nil)
            return
        }
        resolve((data, response))
    }
}
