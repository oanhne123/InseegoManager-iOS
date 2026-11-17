import Foundation
import Security

enum KeychainStore {
    private static let service = "com.inseegomanager.ios"
    private static let ipKey = "inseego_last_ip"
    private static let savePassKey = "inseego_save_password"
    private static let passAccount = "admin_password"

    static var lastIp: String {
        get { UserDefaults.standard.string(forKey: ipKey) ?? "192.168.1.1" }
        set { UserDefaults.standard.set(newValue, forKey: ipKey) }
    }

    static var savePasswordEnabled: Bool {
        get { UserDefaults.standard.object(forKey: savePassKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: savePassKey) }
    }

    static func savePassword(_ password: String) {
        guard let data = password.data(using: .utf8) else { return }
        deletePassword()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
