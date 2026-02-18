import Foundation
import Security

final class KeychainStore {
    private let service = "app.aisatsu.spackle"
    private let account = "provider_api_key"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func getAPIKey() -> String {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return ""
    }

    func setAPIKey(_ value: String) {
        let data = Data(value.utf8)
        let attrs: [String: Any] = [kSecValueData as String: data]
        let update = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        if update == errSecSuccess { return }

        var add = baseQuery
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
}
