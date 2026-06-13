import Foundation
import Security
import CryptoKit

enum KeychainError: Error, CustomStringConvertible {
    case unexpectedData
    case status(OSStatus)
    case randomGenerationFailed(OSStatus)

    var description: String {
        switch self {
        case .unexpectedData: return "Keychain returned unexpected data"
        case .status(let s): return "Keychain status: \(s) (\(SecCopyErrorMessageString(s, nil).map { $0 as String } ?? "unknown"))"
        case .randomGenerationFailed(let s): return "SecRandomCopyBytes failed: \(s)"
        }
    }
}

enum Keychain {
    static let service = "dev.ilkome.MaCopy.database"
    static let account = "masterKey-v1"
    static let keyByteCount = 32

    // The master key never changes within a session, but it is read on every encrypted
    // image/thumbnail access (row scrolling). Memoize it so we pay the Keychain IPC at most
    // once instead of on every decrypt. Lock-guarded: reads come from the main actor and
    // from detached decode tasks.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedKey: SymmetricKey?

    static func getOrCreateMasterKey() throws -> SymmetricKey {
        cacheLock.lock()
        let memoized = cachedKey
        cacheLock.unlock()
        if let memoized { return memoized }

        // Fetch outside the lock to avoid holding it across Keychain IPC. A benign race where
        // two threads both fetch resolves to the same key.
        let key: SymmetricKey
        if let existing = try fetchKey() {
            key = SymmetricKey(data: existing)
        } else {
            let fresh = try generateRandomBytes(count: keyByteCount)
            try storeKey(fresh)
            key = SymmetricKey(data: fresh)
        }
        cacheLock.lock()
        cachedKey = key
        cacheLock.unlock()
        return key
    }

    static func deleteMasterKey() throws {
        cacheLock.lock()
        cachedKey = nil
        cacheLock.unlock()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private static func fetchKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == keyByteCount else {
                throw KeychainError.unexpectedData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.status(status)
        }
    }

    private static func storeKey(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
    }

    private static func generateRandomBytes(count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { ptr -> OSStatus in
            guard let base = ptr.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        guard status == errSecSuccess else {
            throw KeychainError.randomGenerationFailed(status)
        }
        return bytes
    }
}
