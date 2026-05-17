import Foundation

enum SafeFetcher {
    static func fetch(
        url: URL,
        maxBytes: Int,
        accept: String? = nil,
        timeout: TimeInterval = 10
    ) async -> (Data, HTTPURLResponse)? {
        guard await URLSafetyGate.validateResolved(host: url.host) == .allow else { return nil }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = max(timeout, 10)
        config.timeoutIntervalForResource = 30
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.waitsForConnectivity = false
        config.tlsMinimumSupportedProtocolVersion = .TLSv12

        let delegate = BoundedURLSessionDelegate(
            maxBytes: maxBytes,
            originalHost: url.host
        )
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        if let accept {
            request.setValue(accept, forHTTPHeaderField: "Accept")
        }

        guard let (data, response) = await delegate.fetch(request: request, session: session),
              let http = response as? HTTPURLResponse,
              (200..<400).contains(http.statusCode)
        else { return nil }
        return (data, http)
    }
}
