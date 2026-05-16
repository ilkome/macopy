import Foundation
import CryptoKit

enum FileCryptoError: Error, CustomStringConvertible {
    case encryptFailed
    case decryptFailed
    case ioFailed(underlying: Error)

    var description: String {
        switch self {
        case .encryptFailed: return "AES-GCM seal failed"
        case .decryptFailed: return "AES-GCM open failed (corrupt or wrong key)"
        case .ioFailed(let e): return "I/O failed: \(e)"
        }
    }
}

enum FileCrypto {
    static func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw FileCryptoError.encryptFailed
        }
        return combined
    }

    static func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    static func writeEncrypted(_ plaintext: Data, to url: URL, using key: SymmetricKey) throws {
        let ciphertext = try encrypt(plaintext, using: key)
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try ciphertext.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw FileCryptoError.ioFailed(underlying: error)
        }
    }

    static func readEncrypted(from url: URL, using key: SymmetricKey) throws -> Data {
        let ciphertext: Data
        do {
            ciphertext = try Data(contentsOf: url)
        } catch {
            throw FileCryptoError.ioFailed(underlying: error)
        }
        return try decrypt(ciphertext, using: key)
    }
}
