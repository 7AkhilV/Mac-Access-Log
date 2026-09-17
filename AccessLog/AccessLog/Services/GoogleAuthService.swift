import Foundation
import Security

struct ServiceAccountCredentials: Decodable {
    let clientEmail: String
    let privateKey: String
    let tokenURI: String

    enum CodingKeys: String, CodingKey {
        case clientEmail = "client_email"
        case privateKey = "private_key"
        case tokenURI = "token_uri"
    }
}

enum GoogleAuthError: LocalizedError {
    case missingCredentials
    case invalidKey(String)
    case tokenRequestFailed(String)
    case invalidTokenResponse

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Not signed in with Google, and no service-account credentials found."
        case .invalidKey(let detail):
            return "Could not parse the service account private key. \(detail)"
        case .tokenRequestFailed(let message):
            return "Google token request failed: \(message)"
        case .invalidTokenResponse:
            return "Invalid token response from Google."
        }
    }
}

/// Resolves a Google access token: prefers signed-in user OAuth, falls back to service account.
actor GoogleAuthService {
    private var cachedToken: String?
    private var expiry: Date = .distantPast

    func accessToken() async throws -> String {
        if KeychainStore.load() != nil {
            return try await GoogleOAuthService.shared.accessToken()
        }
        return try await serviceAccountAccessToken()
    }

    private func serviceAccountAccessToken() async throws -> String {
        if let cachedToken, expiry > Date().addingTimeInterval(60) {
            return cachedToken
        }

        let credentials = try loadCredentials()
        let assertion = try makeJWT(credentials: credentials)
        let token = try await exchangeToken(assertion: assertion, tokenURI: credentials.tokenURI)
        cachedToken = token.accessToken
        expiry = Date().addingTimeInterval(TimeInterval(token.expiresIn))
        return token.accessToken
    }

    private func loadCredentials() throws -> ServiceAccountCredentials {
        let url = AppPaths.credentialsURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw GoogleAuthError.missingCredentials
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ServiceAccountCredentials.self, from: data)
    }

    private func makeJWT(credentials: ServiceAccountCredentials) throws -> String {
        let header = #"{"alg":"RS256","typ":"JWT"}"#
        let now = Int(Date().timeIntervalSince1970)
        let payloadDict: [String: Any] = [
            "iss": credentials.clientEmail,
            "scope": "https://www.googleapis.com/auth/spreadsheets",
            "aud": credentials.tokenURI,
            "iat": now,
            "exp": now + 3600
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadDict, options: [])
        guard let payload = String(data: payloadData, encoding: .utf8) else {
            throw GoogleAuthError.invalidKey("JWT payload encoding failed.")
        }

        let signingInput = "\(base64URL(header)).\(base64URL(payload))"
        let signature = try signRSA(signingInput, pem: credentials.privateKey)
        return "\(signingInput).\(signature)"
    }

    private func exchangeToken(assertion: String, tokenURI: String) async throws -> TokenResponse {
        guard let url = URL(string: tokenURI) else {
            throw GoogleAuthError.tokenRequestFailed("Bad token URI")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            URLQueryItem(name: "assertion", value: assertion)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP error"
            throw GoogleAuthError.tokenRequestFailed(message)
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }

    private func base64URL(_ string: String) -> String {
        base64URL(Data(string.utf8))
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func signRSA(_ message: String, pem: String) throws -> String {
        let key = try makePrivateKey(from: pem)
        guard let messageData = message.data(using: .utf8) else {
            throw GoogleAuthError.invalidKey("Message encoding failed.")
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            messageData as CFData,
            &error
        ) as Data? else {
            let detail = error?.takeRetainedValue().localizedDescription ?? "signature failed"
            throw GoogleAuthError.invalidKey(detail)
        }

        return base64URL(signature)
    }

    private func makePrivateKey(from pem: String) throws -> SecKey {
        let normalized = normalizePEM(pem)

        if let pkcs1 = try? derViaOpenSSL(pem: normalized),
           let key = secKey(fromPKCS1: pkcs1) {
            return key
        }

        guard let pkcs8 = derFromPEMBody(normalized) else {
            throw GoogleAuthError.invalidKey("Base64 decode failed.")
        }

        if let pkcs1 = extractPKCS1FromPKCS8(pkcs8),
           let key = secKey(fromPKCS1: pkcs1) {
            return key
        }

        if let key = secKey(fromPKCS1: pkcs8) {
            return key
        }

        throw GoogleAuthError.invalidKey("SecKeyCreate failed (-50). Could not import RSA private key.")
    }

    private func normalizePEM(_ pem: String) -> String {
        pem
            .replacingOccurrences(of: "\\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func derFromPEMBody(_ pem: String) -> Data? {
        let body = pem
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("-----") }
            .joined()
            .replacingOccurrences(of: "\r", with: "")
        return Data(base64Encoded: body)
    }

    private func secKey(fromPKCS1 data: Data) -> SecKey? {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        var error: Unmanaged<CFError>?
        return SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error)
    }

    private func derViaOpenSSL(pem: String) throws -> Data {
        let dir = FileManager.default.temporaryDirectory
        let inFile = dir.appendingPathComponent("accesslog-sa-\(UUID().uuidString).pem")
        defer { try? FileManager.default.removeItem(at: inFile) }
        try pem.write(to: inFile, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = [
            "rsa",
            "-inform", "PEM",
            "-in", inFile.path,
            "-outform", "DER"
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let der = stdout.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0, !der.isEmpty else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw GoogleAuthError.invalidKey("openssl rsa failed: \(err)")
        }
        return der
    }

    private func extractPKCS1FromPKCS8(_ data: Data) -> Data? {
        var index = 0
        guard readTag(data, &index) == 0x30 else { return nil }
        _ = readLength(data, &index)

        guard readTag(data, &index) == 0x02 else { return nil }
        let versionLen = readLength(data, &index)
        guard versionLen >= 0, index + versionLen <= data.count else { return nil }
        index += versionLen

        guard readTag(data, &index) == 0x30 else { return nil }
        let algLen = readLength(data, &index)
        guard algLen >= 0, index + algLen <= data.count else { return nil }
        index += algLen

        guard readTag(data, &index) == 0x04 else { return nil }
        let keyLen = readLength(data, &index)
        guard keyLen > 0, index + keyLen <= data.count else { return nil }
        return data.subdata(in: index..<(index + keyLen))
    }

    private func readTag(_ data: Data, _ index: inout Int) -> UInt8? {
        guard index < data.count else { return nil }
        let tag = data[index]
        index += 1
        return tag
    }

    private func readLength(_ data: Data, _ index: inout Int) -> Int {
        guard index < data.count else { return -1 }
        let first = Int(data[index])
        index += 1
        if first & 0x80 == 0 {
            return first
        }
        let count = first & 0x7F
        guard count > 0, count <= 4, index + count <= data.count else { return -1 }
        var length = 0
        for _ in 0..<count {
            length = (length << 8) | Int(data[index])
            index += 1
        }
        return length
    }
}
