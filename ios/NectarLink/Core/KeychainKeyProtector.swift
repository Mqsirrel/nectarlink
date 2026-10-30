// SPDX-License-Identifier: MPL-2.0

import CryptoKit
import Foundation
import Security

/// Encrypts the core's Ed25519 device identity key at rest using a 256-bit
/// symmetric key stored in the iOS Keychain (`AfterFirstUnlockThisDeviceOnly`)
/// and authenticated AES-GCM-256 (`CryptoKit.AES.GCM`).
public final class KeychainKeyProtector: KeyProtector, @unchecked Sendable {
    private let service = "app.nectarlink.ios.identity"
    private let account = "device-key-wrapping-key-v1"
    private let lock = NSLock()

    public init() {}

    public func protect(plaintext: Data) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        let key = try loadOrCreateKey()
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else {
                throw NectarlinkError.Storage(reason: "AES-GCM combined representation unavailable")
            }
            return combined
        } catch let error as NectarlinkError {
            throw error
        } catch {
            throw NectarlinkError.Storage(reason: "AES-GCM seal failed: \(error.localizedDescription)")
        }
    }

    public func unprotect(ciphertext: Data) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        let key = try loadOrCreateKey()
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key)
        } catch let error as NectarlinkError {
            throw error
        } catch {
            throw NectarlinkError.Storage(reason: "AES-GCM open failed: \(error.localizedDescription)")
        }
    }

    private func loadOrCreateKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        if status != errSecItemNotFound && status != errSecSuccess {
            throw NectarlinkError.Storage(reason: "Keychain read failed (OSStatus \(status))")
        }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        // Remove any corrupt/stale entry before inserting.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NectarlinkError.Storage(reason: "Keychain write failed (OSStatus \(addStatus))")
        }
        return newKey
    }
}
