import Foundation
import AppKit

enum GoogleOAuthError: LocalizedError {
    case missingRefreshToken
    case tokenExchangeFailed(String)
    case notSignedIn
    case userInfoFailed

    var errorDescription: String? {
        switch self {
        case .missingRefreshToken:
            return "Google sign-in did not return a refresh token. Try signing in again."
        case .tokenExchangeFailed(let message):
            return "Google token error: \(message)"
        case .notSignedIn:
            return "Not signed in with Google."
        case .userInfoFailed:
            return "Could not read Google account email."
        }
    }
}

actor GoogleOAuthService {
    static let shared = GoogleOAuthService()

    private var cachedAccessToken: String?
    private var cachedExpiry: Date = .distantPast

    nonisolated static var isSignedIn: Bool {
        guard let token = KeychainStore.load()?.refreshToken else { return false }
        return !token.isEmpty
    }

    nonisolated static var signedInEmail: String? {
        KeychainStore.load()?.email
    }

    func accessToken() async throws -> String {
        if let cachedAccessToken, cachedExpiry > Date().addingTimeInterval(60) {
            return cachedAccessToken
        }

        guard var tokens = KeychainStore.load() else {
            throw GoogleOAuthError.notSignedIn
        }

        if tokens.expiry > Date().addingTimeInterval(60) {
            cachedAccessToken = tokens.accessToken
            cachedExpiry = tokens.expiry
            return tokens.accessToken
        }

        let refreshed = try await refresh(tokens.refreshToken)
        tokens.accessToken = refreshed.accessToken
        tokens.expiry = Date().addingTimeInterval(TimeInterval(refreshed.expiresIn))
        if let newRefresh = refreshed.refreshToken, !newRefresh.isEmpty {
            tokens.refreshToken = newRefresh
        }
        try KeychainStore.save(tokens)
        cachedAccessToken = tokens.accessToken
        cachedExpiry = tokens.expiry
        return tokens.accessToken
    }

    func signIn() async throws -> String {
        let config = GoogleOAuthConfig.shared
        let server = LoopbackHTTPServer()
        let redirectURL = try server.start()
        defer { server.stop() }

        var components = URLComponents(string: config.authURI)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true")
        ]

        guard let authURL = components.url else {
            throw GoogleOAuthError.tokenExchangeFailed("Bad auth URL")
        }

        await MainActor.run {
            NSWorkspace.shared.open(authURL)
        }

        let code = try await server.waitForCode()
        let tokenResponse = try await exchangeCode(code, redirectURI: redirectURL.absoluteString)

        guard let refresh = tokenResponse.refreshToken, !refresh.isEmpty else {
            throw GoogleOAuthError.missingRefreshToken
        }

        let email = try await fetchEmail(accessToken: tokenResponse.accessToken)
        let tokens = KeychainStore.Tokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: refresh,
            expiry: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
            email: email
        )
        try KeychainStore.save(tokens)

        cachedAccessToken = tokens.accessToken
        cachedExpiry = tokens.expiry
        return email
    }

    func signOut() {
        cachedAccessToken = nil
        cachedExpiry = .distantPast
        KeychainStore.clear()
    }

    private func exchangeCode(_ code: String, redirectURI: String) async throws -> TokenResponse {
        let config = GoogleOAuthConfig.shared
        var request = URLRequest(url: URL(string: config.tokenURI)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "client_secret", value: config.clientSecret),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code")
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleOAuthError.tokenExchangeFailed(String(data: data, encoding: .utf8) ?? "HTTP error")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func refresh(_ refreshToken: String) async throws -> TokenResponse {
        let config = GoogleOAuthConfig.shared
        var request = URLRequest(url: URL(string: config.tokenURI)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "client_secret", value: config.clientSecret),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP error"
            if message.contains("invalid_grant") {
                signOut()
            }
            throw GoogleOAuthError.tokenExchangeFailed(message)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func fetchEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else {
            throw GoogleOAuthError.userInfoFailed
        }
        return email
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }
}
