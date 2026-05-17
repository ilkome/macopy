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

    static func getOrCreateMasterKey() throws -> SymmetricKey {
        if let existing = try fetchKey() {
            return SymmetricKey(data: existing)
        }
        let fresh = try generateRandomBytes(count: keyByteCount)
        try storeKey(fresh)
        return SymmetricKey(data: fresh)
    }

    static func deleteMasterKey() throws {
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
