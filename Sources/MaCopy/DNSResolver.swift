import Darwin
import Foundation

enum DNSResolver {
    static func resolveAll(host: String, timeout: TimeInterval = 3) async -> [IPClassifier.IPAddress] {
        await withTaskGroup(of: Optional<[IPClassifier.IPAddress]>.self) { group in
            group.addTask { await resolveBlocking(host: host) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            var result: [IPClassifier.IPAddress] = []
            for await value in group {
                group.cancelAll()
                result = value ?? []
                break
            }
            return result
        }
    }

    private static func resolveBlocking(host: String) async -> [IPClassifier.IPAddress] {
        await withCheckedContinuation { (cont: CheckedContinuation<[IPClassifier.IPAddress], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                hints.ai_flags = AI_ADDRCONFIG

                var res: UnsafeMutablePointer<addrinfo>?
                let status = host.withCString { hostPtr in
                    getaddrinfo(hostPtr, nil, &hints, &res)
                }
                guard status == 0, let head = res else {
                    cont.resume(returning: [])
                    return
                }
                defer { freeaddrinfo(head) }

                var addresses: [IPClassifier.IPAddress] = []
                var cur: UnsafeMutablePointer<addrinfo>? = head
                while let p = cur {
                    let info = p.pointee
                    if let addrPtr = info.ai_addr {
                        if info.ai_family == AF_INET {
                            addrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                                let host = UInt32(bigEndian: sin.pointee.sin_addr.s_addr)
                                addresses.append(.v4(host))
                            }
                        } else if info.ai_family == AF_INET6 {
                            addrPtr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
                                var v6 = sin6.pointee.sin6_addr
                                var bytes = [UInt8](repeating: 0, count: 16)
                                withUnsafePointer(to: &v6) { ptr in
                                    ptr.withMemoryRebound(to: UInt8.self, capacity: 16) { byte in
                                        for i in 0..<16 { bytes[i] = byte[i] }
                                    }
                                }
                                addresses.append(.v6(bytes))
                            }
                        }
                    }
                    cur = info.ai_next
                }
                cont.resume(returning: addresses)
            }
        }
    }
}
