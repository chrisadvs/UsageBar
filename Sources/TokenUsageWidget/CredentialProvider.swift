import Foundation

public protocol CredentialProvider {
    func getCookie() -> String?
    func saveCookie(_ cookie: String)
}

public class KeychainCredentialProvider: CredentialProvider {
    private let service = "claude.ai"
    private let account = "session_cookie"
    
    public init() {}
    
    public func getCookie() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    public func saveCookie(_ cookie: String) {
        guard let data = cookie.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        SecItemDelete(query as CFDictionary)
        
        var addQuery = query
        addQuery[kSecValueData as String] = data
        
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
