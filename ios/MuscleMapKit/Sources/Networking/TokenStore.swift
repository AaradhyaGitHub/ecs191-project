import Foundation
import Security

/// Where the sign-in token lives. The app uses the Keychain, never UserDefaults (CLAUDE.md).
public protocol TokenStore: Sendable {
    func token() -> String?
    func save(_ token: String) throws
    func clear() throws
}

/// For tests and previews.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    public init(_ token: String? = nil) { value = token }

    public func token() -> String? { lock.withLock { value } }
    public func save(_ token: String) throws { lock.withLock { value = token } }
    public func clear() throws { lock.withLock { value = nil } }
}

/// The real store: one generic-password item in the Keychain.
public struct KeychainTokenStore: TokenStore {
    public struct Failure: Error, Equatable { public let status: OSStatus }

    private let service: String
    private let account = "api-token"

    public init(service: String = "edu.ucdavis.ecs191.MuscleMap") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func token() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) throws {
        try clear()
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    public func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
