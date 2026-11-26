import Foundation
import Observation
import CryptoKit

struct Session: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Double
    var userId: String
    var email: String?
}

struct AuthError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Talks to the same Supabase project as the website, over plain HTTPS.
@MainActor
@Observable
final class Account {
    static let callbackScheme = "adnanstudy"
    static let callbackURL = "adnanstudy://auth-callback"

    private(set) var session: Session?
    @ObservationIgnored private var appleNonce: String?

    init() {
        if let d = Keychain.load("session"), let s = try? JSONDecoder().decode(Session.self, from: d) {
            session = s
        }
    }

    var displayName: String {
        guard let s = session else { return "" }
        if let e = s.email, !e.isEmpty, !e.hasSuffix("privaterelay.appleid.com") { return e }
        return "Apple ID"
    }

    private func store(_ s: Session?) {
        session = s
        if let s, let d = try? JSONEncoder().encode(s) { Keychain.save(d, for: "session") }
        else { Keychain.delete("session") }
    }

    // MARK: requests

    private func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Any? = nil, auth: Bool = false, extraHeaders: [String: String] = [:]) async throws -> (Data, Int) {
        var comps = URLComponents(url: Remote.supabase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue(Remote.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let token = try await validToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (d, r) = try await URLSession.shared.data(for: req)
        return (d, (r as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func message(from data: Data) -> String {
        if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for k in ["error_description", "msg", "message", "error"] {
                if let m = o[k] as? String, !m.isEmpty { return m }
            }
        }
        return "Something went wrong. Try again."
    }

    private func sessionFrom(_ data: Data) throws -> Session {
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = o["access_token"] as? String,
              let refresh = o["refresh_token"] as? String,
              let user = o["user"] as? [String: Any],
              let uid = user["id"] as? String
        else { throw AuthError(message: "Check your email to confirm your account, then sign in.") }
        let expiresIn = (o["expires_in"] as? Double) ?? 3600
        return Session(accessToken: access, refreshToken: refresh,
                       expiresAt: Date().timeIntervalSince1970 + expiresIn,
                       userId: uid, email: user["email"] as? String)
    }

    private func tokenGrant(_ grant: String, body: [String: Any]) async throws -> Session {
        let (d, code) = try await request("auth/v1/token", method: "POST", query: [URLQueryItem(name: "grant_type", value: grant)], body: body)
        guard code == 200 else { throw AuthError(message: message(from: d)) }
        return try sessionFrom(d)
    }

    /// Refreshes the access token a minute before it expires.
    func validToken() async throws -> String? {
        guard let s = session else { return nil }
        if s.expiresAt - 60 > Date().timeIntervalSince1970 { return s.accessToken }
        do {
            let fresh = try await tokenGrant("refresh_token", body: ["refresh_token": s.refreshToken])
            store(fresh)
            return fresh.accessToken
        } catch {
            store(nil)
            return nil
        }
    }

    // MARK: sign in

    func signIn(email: String, password: String) async throws {
        store(try await tokenGrant("password", body: ["email": email, "password": password]))
    }

    func signUp(email: String, password: String) async throws {
        let (d, code) = try await request("auth/v1/signup", method: "POST", body: ["email": email, "password": password])
        guard code == 200 else { throw AuthError(message: message(from: d)) }
        store(try sessionFrom(d))
    }

    /// Returns the hashed nonce to hand to Apple. The raw one goes to Supabase afterwards.
    func newAppleNonce() -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let raw = String((0..<32).map { _ in chars[Int.random(in: 0..<chars.count)] })
        appleNonce = raw
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func signInWithApple(idToken: String) async throws {
        var body: [String: Any] = ["provider": "apple", "id_token": idToken]
        if let n = appleNonce { body["nonce"] = n }
        store(try await tokenGrant("id_token", body: body))
    }

    /// URL that starts Google or Facebook sign in in a browser sheet.
    func oauthURL(provider: String) -> URL {
        var c = URLComponents(url: Remote.supabase.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "provider", value: provider), URLQueryItem(name: "redirect_to", value: Account.callbackURL)]
        if provider == "facebook" { items.append(URLQueryItem(name: "scopes", value: "email")) }
        c.queryItems = items
        return c.url!
    }

    /// Reads the tokens Supabase puts in the callback URL fragment.
    func finishOAuth(callback: URL) async throws {
        let frag = callback.fragment ?? callback.query ?? ""
        var p: [String: String] = [:]
        for pair in frag.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { p[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
        }
        if let err = p["error_description"] ?? p["error"] { throw AuthError(message: err.replacingOccurrences(of: "+", with: " ")) }
        guard let access = p["access_token"], let refresh = p["refresh_token"] else {
            throw AuthError(message: "Sign in didn't finish. Try again.")
        }
        var s = Session(accessToken: access, refreshToken: refresh,
                        expiresAt: Date().timeIntervalSince1970 + (Double(p["expires_in"] ?? "") ?? 3600),
                        userId: "", email: nil)
        store(s)
        let (d, code) = try await request("auth/v1/user", auth: true)
        if code == 200, let u = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            s.userId = u["id"] as? String ?? ""
            s.email = u["email"] as? String
            store(s)
        }
        if s.userId.isEmpty { store(nil); throw AuthError(message: "Sign in didn't finish. Try again.") }
    }

    func signOut() async {
        _ = try? await request("auth/v1/logout", method: "POST", auth: true)
        store(nil)
    }

    /// Deletes the account and everything saved with it (needs the delete_user database function).
    func deleteAccount() async throws {
        let (d, code) = try await request("rest/v1/rpc/delete_user", method: "POST", body: [String: Any](), auth: true)
        guard (200..<300).contains(code) else { throw AuthError(message: message(from: d)) }
        store(nil)
    }

    // MARK: study data

    func fetchUserData() async -> UserData? {
        guard let s = session else { return nil }
        let res = try? await request("rest/v1/user_data", query: [
            URLQueryItem(name: "user_id", value: "eq.\(s.userId)"),
            URLQueryItem(name: "select", value: "data"),
        ], auth: true)
        guard let res, res.1 == 200 else { return nil }
        struct Row: Decodable { let data: UserData? }
        let rows = (try? JSONDecoder().decode([Row].self, from: res.0)) ?? []
        return rows.first?.data ?? UserData()
    }

    func saveUserData(_ u: UserData) async {
        guard let s = session, let enc = try? JSONEncoder().encode(u),
              let obj = try? JSONSerialization.jsonObject(with: enc) else { return }
        let row: [String: Any] = [
            "user_id": s.userId,
            "data": obj,
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]
        _ = try? await request("rest/v1/user_data", method: "POST", body: [row], auth: true,
                               extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"])
    }
}
