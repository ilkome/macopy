import Foundation
import CryptoKit

enum ImageStoreError: Error, CustomStringConvertible {
    case keyUnavailable(underlying: Error)
    case crypto(underlying: Error)
    case io(underlying: Error)

    var description: String {
        switch self {
        case .keyUnavailable(let e): return "Master key unavailable: \(e)"
        case .crypto(let e): return "Crypto failed: \(e)"
        case .io(let e): return "I/O failed: \(e)"
        }
    }
}

enum ImageStore {
    static let encryptedSuffix = ".enc"

    private static func masterKey() throws -> SymmetricKey {
        do {
            return try Keychain.getOrCreateMasterKey()
        } catch {
            throw ImageStoreError.keyUnavailable(underlying: error)
        }
    }

    static func encryptedURL(for filename: String) -> URL {
        Storage.imageURL(for: filename + encryptedSuffix)
    }

    static func write(_ data: Data, filename: String) throws {
        let key = try masterKey()
        let url = encryptedURL(for: filename)
        do {
            try FileCrypto.writeEncrypted(data, to: url, using: key)
        } catch {
            throw ImageStoreError.crypto(underlying: error)
        }
    }

    static func read(filename: String) throws -> Data {
        let key = try masterKey()
        let url = encryptedURL(for: filename)
        do {
            return try FileCrypto.readEncrypted(from: url, using: key)
        } catch {
            throw ImageStoreError.crypto(underlying: error)
        }
    }

    static func delete(filename: String) {
        try? FileManager.default.removeItem(at: encryptedURL(for: filename))
    }

    static func exists(filename: String) -> Bool {
        FileManager.default.fileExists(atPath: encryptedURL(for: filename).path)
    }

    /// Decrypts the file to a temporary plain-text URL for consumers (e.g. QuickLook)
    /// that require a path. The file lives in `NSTemporaryDirectory()` and is overwritten
    /// on repeat calls for the same filename.
    static func tempPlaintextURL(for filename: String) throws -> URL {
        let data = try read(filename: filename)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaCopy-preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ImageStoreError.io(underlying: error)
        }
        return url
    }
}
