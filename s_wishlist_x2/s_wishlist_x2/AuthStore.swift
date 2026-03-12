import Foundation
import Combine

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published var isBusy = false

    private let storageKey = "s_wishlist_x2.auth_session"

    init() {
        loadStoredSession()
    }

    var isAuthenticated: Bool {
        guard let session = session else { return false }
        return !session.isExpired
    }

    var email: String? {
        guard isAuthenticated else { return nil }
        return session?.email
    }

    var ownerHeaders: [String: String]? {
        guard let session, isAuthenticated else { return nil }
        return [
            "x-owner-email": session.email,
            "authorization": "Bearer \(session.accessToken)"
        ]
    }

    var actorHeaders: [String: String]? {
        guard let email = email else { return nil }
        return ["x-actor-email": email]
    }

    func signOut() {
        session = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    func signIn(email: String, password: String) async throws {
        isBusy = true
        defer { isBusy = false }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            throw NetworkError.server(status: 422, message: "Email and password are required.")
        }

        guard let signInURL = URL(string: "/auth/v1/token?grant_type=password", relativeTo: AppConfig.supabaseURL)?.absoluteURL else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: signInURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "authorization")

        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": normalizedEmail,
            "password": password
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        if !(200...299).contains(http.statusCode) {
            throw NetworkError.server(status: http.statusCode, message: parseSupabaseError(data: data))
        }

        let decoded = try JSONDecoder().decode(SupabaseAuthPayload.self, from: data)
        guard let accessToken = decoded.accessToken,
              let user = decoded.user,
              let userEmail = user.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !userEmail.isEmpty else {
            throw NetworkError.server(status: 401, message: "Sign in failed. Missing session data.")
        }

        let expiresAt = decoded.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        let next = AuthSession(
            email: userEmail,
            userId: user.id,
            accessToken: accessToken,
            refreshToken: decoded.refreshToken,
            expiresAt: expiresAt
        )

        store(session: next)
    }

    func signUp(email: String, password: String) async throws -> String {
        isBusy = true
        defer { isBusy = false }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            throw NetworkError.server(status: 422, message: "Email and password are required.")
        }

        var request = URLRequest(url: AppConfig.supabaseURL.appending(path: "/auth/v1/signup"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "authorization")

        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": normalizedEmail,
            "password": password
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        if !(200...299).contains(http.statusCode) {
            throw NetworkError.server(status: http.statusCode, message: parseSupabaseError(data: data))
        }

        let payload = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] ?? [:]

        let sessionObject = payload["session"] as? [String: Any]
        let topUserObject = payload["user"] as? [String: Any]
        let userObject = (sessionObject?["user"] as? [String: Any]) ?? topUserObject

        let accessToken = (payload["access_token"] as? String) ?? (sessionObject?["access_token"] as? String)
        let refreshToken = (payload["refresh_token"] as? String) ?? (sessionObject?["refresh_token"] as? String)
        let expiresIn = (payload["expires_in"] as? Int) ?? (sessionObject?["expires_in"] as? Int)
        let userId = userObject?["id"] as? String
        let userEmail = (userObject?["email"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let accessToken = accessToken,
           let userId = userId,
           let userEmail = userEmail,
           !userEmail.isEmpty {
            let expiresAt = expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
            let next = AuthSession(
                email: userEmail,
                userId: userId,
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt
            )
            store(session: next)
            return "Account created."
        }

        return "Check your email to confirm your account before signing in."
    }

    func requestPasswordReset(email: String) async throws -> String {
        isBusy = true
        defer { isBusy = false }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else {
            throw NetworkError.server(status: 422, message: "Email is required.")
        }

        var request = URLRequest(url: AppConfig.supabaseURL.appending(path: "/auth/v1/recover"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "authorization")

        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": normalizedEmail
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        if !(200...299).contains(http.statusCode) {
            throw NetworkError.server(status: http.statusCode, message: parseSupabaseError(data: data))
        }

        return "If an account exists for this email, reset instructions were sent."
    }

    private func parseSupabaseError(data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(SupabaseErrorPayload.self, from: data) {
            if let description = decoded.errorDescription, !description.isEmpty {
                return normalizeSupabaseError(description)
            }
            if let message = decoded.msg, !message.isEmpty {
                return normalizeSupabaseError(message)
            }
            if let message = decoded.message, !message.isEmpty {
                return normalizeSupabaseError(message)
            }
            if let error = decoded.error, !error.isEmpty {
                return normalizeSupabaseError(error)
            }
        }

        return "Authentication request failed."
    }

    private func normalizeSupabaseError(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("invalid login credentials") {
            return "Email or password is incorrect."
        }
        if lower.contains("email not confirmed") {
            return "Check your email to confirm your account before signing in."
        }
        if lower.contains("user already registered") {
            return "An account with this email already exists."
        }
        return raw
    }

    private func store(session: AuthSession) {
        self.session = session
        if let encoded = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func loadStoredSession() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            session = nil
            return
        }

        if stored.isExpired {
            session = nil
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }

        session = stored
    }
}

private struct SupabaseAuthPayload: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: SupabaseUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

private struct SupabaseUser: Decodable {
    let id: String
    let email: String?
}

private struct SupabaseErrorPayload: Decodable {
    let msg: String?
    let message: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case msg
        case message
        case error
        case errorDescription = "error_description"
    }
}
