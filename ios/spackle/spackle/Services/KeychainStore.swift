import Foundation
import Security

final class KeychainStore {
    private let service = "app.aisatsu.spackle"
    private let account = "provider_api_key"
    private let variants: [[String: Any]] = [
        [kSecUseDataProtectionKeychain as String: true],
        [:]
    ]

    func getAPIKey() -> String {
        for extra in variants {
            var q: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            for (k, v) in extra {
                q[k] = v
            }
            var item: CFTypeRef?
            let status = SecItemCopyMatching(q as CFDictionary, &item)
            if status == errSecSuccess, let data = item as? Data {
                return String(data: data, encoding: .utf8) ?? ""
            }
        }
        return ""
    }

    func setAPIKey(_ value: String) {
        let data = Data(value.utf8)
        for extra in variants {
            var q: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            for (k, v) in extra {
                q[k] = v
            }

            let attrs: [String: Any] = [kSecValueData as String: data]
            let update = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
            if update == errSecSuccess {
                return
            }
            if update != errSecItemNotFound {
                continue
            }

            var add: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data
            ]
            for (k, v) in extra {
                add[k] = v
            }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus == errSecSuccess || addStatus == errSecDuplicateItem {
                return
            }
        }
    }
}
