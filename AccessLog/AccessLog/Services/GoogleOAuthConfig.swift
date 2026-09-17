import Foundation

struct GoogleOAuthConfig: Decodable {
    let clientId: String
    let clientSecret: String
    let authURI: String
    let tokenURI: String

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case authURI = "auth_uri"
        case tokenURI = "token_uri"
    }

    static let shared: GoogleOAuthConfig = {
        // Prefer bundled GoogleOAuth.json (local, gitignored). Fall back to example only for structure checks.
        let bundle = Bundle.main
        let url = bundle.url(forResource: "GoogleOAuth", withExtension: "json")
            ?? bundle.url(forResource: "GoogleOAuth.example", withExtension: "json")

        guard let url,
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(GoogleOAuthConfig.self, from: data),
              !config.clientId.contains("YOUR_CLIENT_ID"),
              !config.clientSecret.contains("YOUR_CLIENT_SECRET") else {
            fatalError("""
            Missing Google OAuth config.
            Copy AccessLog/Resources/GoogleOAuth.example.json → GoogleOAuth.json
            and fill in your Desktop OAuth client_id and client_secret.
            Do not commit GoogleOAuth.json.
            """)
        }
        return config
    }()

    static let scopes = [
        "https://www.googleapis.com/auth/spreadsheets",
        "https://www.googleapis.com/auth/drive.file",
        "https://www.googleapis.com/auth/userinfo.email"
    ].joined(separator: " ")
}
