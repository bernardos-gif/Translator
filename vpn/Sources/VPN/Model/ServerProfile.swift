import Foundation
import Security

/// How to reach the user's server over SSH. The password, if any, lives in the Keychain.
struct ServerProfile: Codable, Equatable {
    enum Auth: String, Codable, CaseIterable, Identifiable {
        case password, key
        var id: String { rawValue }
    }

    var host: String
    var user: String = "root"
    var port: Int = 22
    var auth: Auth = .password
    var keyPath: String = ""

    var isRoot: Bool { user == "root" }
    var keychainAccount: String { "\(user)@\(host):\(port)" }

    private static let defaultsKey = "serverProfile"

    static func load() -> ServerProfile? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(ServerProfile.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

enum Keychain {
    private static let service = "app.vpn.mac.ssh"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func password(for account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setPassword(_ password: String, for account: String) {
        delete(account)
        var query = baseQuery(account)
        query[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
