import Foundation
import NetFS
import PaneKit
import Security

/// Connecting to an SMB share through the system's `NetFS`, with no system dialog:
/// the Connect to Server sheet asks for the name and password itself.
enum SMBMount {
    /// Mounts the share and returns where it appeared, or the system's error code.
    static func mount(_ address: SMBAddress, user: String?, password: String?) async -> Result<URL, MountFailure> {
        await Task.detached {
            var mountpoints: Unmanaged<CFArray>?
            let options = NSMutableDictionary()
            options[kNAUIOptionKey as String] = kNAUIOptionNoUI as String
            let status = NetFSMountURLSync(
                address.url as CFURL, nil,
                (user?.isEmpty == false ? user : nil) as CFString?,
                (password?.isEmpty == false ? password : nil) as CFString?,
                options as CFMutableDictionary, nil, &mountpoints)
            guard status == 0 else { return .failure(MountFailure(code: status)) }
            let paths = (mountpoints?.takeRetainedValue() as? [String]) ?? []
            guard let first = paths.first else { return .failure(MountFailure(code: 2)) }
            return .success(URL(fileURLWithPath: first, isDirectory: true))
        }.value
    }
}

/// A share's password, kept in the Keychain when the person asks for that.
enum PasswordKeychain {
    private static func query(server: String, account: String, proto: CFString) -> [String: Any] {
        [kSecClass as String: kSecClassInternetPassword, kSecAttrServer as String: server,
         kSecAttrAccount as String: account, kSecAttrProtocol as String: proto]
    }

    static func save(_ password: String, server: String, account: String, proto: CFString = kSecAttrProtocolSMB) {
        let base = query(server: server, account: account, proto: proto)
        let data = Data(password.utf8)
        if SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var item = base
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    static func password(server: String, account: String, proto: CFString = kSecAttrProtocolSMB) -> String? {
        var request = query(server: server, account: account, proto: proto)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
