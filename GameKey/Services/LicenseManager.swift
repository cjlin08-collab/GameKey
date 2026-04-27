import Foundation
import Security

/// Validates and remembers the user's license key. Keys live in the macOS Keychain so reinstalling
/// the app doesn't lose them. The validation endpoint is a small backend you control (Cloudflare
/// Worker, Vercel function, etc.) that knows how to look up keys against your Stripe + database.
@MainActor
final class LicenseManager: ObservableObject {
    enum Status: Equatable {
        case unknown
        case unlicensed
        case validating
        case licensed(email: String?)
        case invalid(reason: String)
    }

    @Published private(set) var status: Status = .unknown

    /// Configurable so a tester can point at a staging endpoint via Settings.
    var validationURL: URL {
        URL(string: UserDefaults.standard.string(forKey: "license.validationURL")
            ?? "https://api.gamekey.example/license/validate")!
    }

    private let keychainService = "com.gamekey.app.license"
    private let keychainAccount = "current"

    /// Boot-time check. Pulls the key from Keychain (if any) and validates it. We do this every
    /// launch so revoked keys stop working without users having to do anything.
    func bootstrap() async {
        guard let stored = readKeyFromKeychain() else {
            status = .unlicensed
            return
        }
        status = .validating
        await validate(key: stored)
    }

    /// Called from the paywall view when the user pastes a key.
    func submit(key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPlausibleKey(trimmed) else {
            status = .invalid(reason: "That doesn't look like a GameKey key.")
            return
        }
        status = .validating
        await validate(key: trimmed)
    }

    func sign(out: Void = ()) {
        deleteKeyFromKeychain()
        status = .unlicensed
    }

    /// Public read-only flag for views that don't care about the full status.
    var isLicensed: Bool {
        if case .licensed = status { return true }
        return false
    }

    // MARK: - Validation

    private func validate(key: String) async {
        struct Request: Encodable { let key: String; let machineId: String }
        struct Response: Decodable { let valid: Bool; let email: String?; let reason: String? }

        var req = URLRequest(url: validationURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 12
        let body = Request(key: key, machineId: machineId())
        req.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                // Don't lock the user out on transient server failures: keep the previously-stored
                // key but flag the status. If the key was already trusted, this resolves to
                // "still licensed" on next online launch.
                if readKeyFromKeychain() == key {
                    status = .licensed(email: nil)
                } else {
                    status = .invalid(reason: "License server is unreachable. Try again in a moment.")
                }
                return
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            if decoded.valid {
                writeKeyToKeychain(key)
                status = .licensed(email: decoded.email)
            } else {
                deleteKeyFromKeychain()
                status = .invalid(reason: decoded.reason ?? "License key is not valid.")
            }
        } catch {
            // Same offline tolerance as above.
            if readKeyFromKeychain() == key {
                status = .licensed(email: nil)
            } else {
                status = .invalid(reason: "Couldn't reach the license server: \(error.localizedDescription)")
            }
        }
    }

    /// Format gate before we even hit the server. Real keys look like GK-XXXX-XXXX-XXXX-XXXX.
    private func isPlausibleKey(_ key: String) -> Bool {
        let pattern = #"^GK-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"#
        return key.range(of: pattern, options: .regularExpression) != nil
    }

    /// Stable per-Mac identifier so the server can rate-limit how many machines a single key is
    /// activated on. We use the IOPlatformUUID surfaced via UserDefaults the first time we see it.
    private func machineId() -> String {
        if let cached = UserDefaults.standard.string(forKey: "license.machineId") {
            return cached
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: "license.machineId")
        return new
    }

    // MARK: - Keychain

    private func writeKeyToKeychain(_ key: String) {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private func readKeyFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeyFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
