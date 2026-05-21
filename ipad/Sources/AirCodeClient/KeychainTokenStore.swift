import Foundation
import Security

public protocol TokenStore: AnyObject {
    func load() -> ConnectionSettings?
    func save(_ settings: ConnectionSettings)
}

public final class KeychainTokenStore: TokenStore {
    private let service = "dev.aircode.connection"
    private let account = "default"

    public init() {}

    public func load() -> ConnectionSettings? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let settings = try? JSONDecoder().decode(ConnectionSettings.self, from: data) else {
            return nil
        }
        return settings
    }

    public func save(_ settings: ConnectionSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        let query = baseQuery()
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
