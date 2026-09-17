import Foundation

enum SheetsSyncError: LocalizedError {
    case missingConfig
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            return "config.json is missing spreadsheetId. Place config in Application Support/AccessLog/."
        case .httpError(let code, let body):
            return "Google Sheets API error (\(code)): \(body)"
        }
    }
}

actor SheetsSyncService {
    private let auth = GoogleAuthService()
    private let database = DatabaseService.shared

    /// Verifies service-account auth and that the configured spreadsheet/tab are reachable.
    func testConnection() async throws -> String {
        let config = try ConfigStore.load()
        guard !config.spreadsheetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SheetsSyncError.missingConfig
        }

        let token = try await auth.accessToken()
        let urlString = "https://sheets.googleapis.com/v4/spreadsheets/\(config.spreadsheetId)?fields=properties.title,sheets.properties.title"
        guard let url = URL(string: urlString) else {
            throw SheetsSyncError.httpError(0, "Invalid spreadsheet URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SheetsSyncError.httpError(0, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw SheetsSyncError.httpError(http.statusCode, message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let properties = json["properties"] as? [String: Any],
              let title = properties["title"] as? String else {
            return "Connected to Google Sheets."
        }

        let tabNames: [String] = {
            guard let sheets = json["sheets"] as? [[String: Any]] else { return [] }
            return sheets.compactMap { sheet in
                (sheet["properties"] as? [String: Any])?["title"] as? String
            }
        }()

        if !tabNames.contains(config.sheetName) {
            let available = tabNames.isEmpty ? "(none)" : tabNames.joined(separator: ", ")
            throw SheetsSyncError.httpError(
                404,
                "Connected to \"\(title)\", but tab \"\(config.sheetName)\" was not found. Available tabs: \(available)"
            )
        }

        return "Connected to \"\(title)\" / tab \"\(config.sheetName)\"."
    }

    /// Creates a new spreadsheet owned by the signed-in user and writes header row.
    func createAccessLogSpreadsheet(title: String = "Access Log") async throws -> AppConfig {
        let token = try await auth.accessToken()

        var createRequest = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets")!)
        createRequest.httpMethod = "POST"
        createRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let createBody: [String: Any] = [
            "properties": ["title": title],
            "sheets": [[
                "properties": ["title": "Access Logs"]
            ]]
        ]
        createRequest.httpBody = try JSONSerialization.data(withJSONObject: createBody)

        let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)
        guard let createHTTP = createResponse as? HTTPURLResponse, (200..<300).contains(createHTTP.statusCode) else {
            throw SheetsSyncError.httpError(
                (createResponse as? HTTPURLResponse)?.statusCode ?? 0,
                String(data: createData, encoding: .utf8) ?? ""
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: createData) as? [String: Any],
              let spreadsheetId = json["spreadsheetId"] as? String else {
            throw SheetsSyncError.httpError(0, "Spreadsheet created but ID missing.")
        }

        let sheetName = "Access Logs"
        let range = "\(sheetName)!A1:E1"
        let encodedRange = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.union(CharacterSet(charactersIn: "!"))) ?? range
        var valuesURL = URLComponents(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/\(encodedRange)")
        valuesURL?.queryItems = [URLQueryItem(name: "valueInputOption", value: "RAW")]
        guard let putURL = valuesURL?.url else {
            throw SheetsSyncError.httpError(0, "Invalid values URL")
        }

        var putRequest = URLRequest(url: putURL)
        putRequest.httpMethod = "PUT"
        putRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        putRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        putRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "values": [["ID", "Name", "Purpose", "Date", "Time"]]
        ])

        let (putData, putResponse) = try await URLSession.shared.data(for: putRequest)
        guard let putHTTP = putResponse as? HTTPURLResponse, (200..<300).contains(putHTTP.statusCode) else {
            throw SheetsSyncError.httpError(
                (putResponse as? HTTPURLResponse)?.statusCode ?? 0,
                String(data: putData, encoding: .utf8) ?? ""
            )
        }

        let config = AppConfig(spreadsheetId: spreadsheetId, sheetName: sheetName)
        try ConfigStore.save(config)
        return config
    }

    func syncPending() async throws -> Int {
        let config = try ConfigStore.load()
        guard !config.spreadsheetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SheetsSyncError.missingConfig
        }

        let pending = try database.pendingRecords()
        guard !pending.isEmpty else { return 0 }

        let token = try await auth.accessToken()
        var syncedCount = 0

        for record in pending {
            try await append(record: record, config: config, token: token)
            try database.markSynced(id: record.id)
            syncedCount += 1
        }

        return syncedCount
    }

    private func append(record: AccessRecord, config: AppConfig, token: String) async throws {
        let range = "\(config.sheetName)!A:E"
        // Encode the whole A1 range (spaces, :, etc.) the way Sheets API expects.
        let encodedRange = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.union(CharacterSet(charactersIn: "!")))
            ?? range
        var components = URLComponents(string: "https://sheets.googleapis.com/v4/spreadsheets/\(config.spreadsheetId)/values/\(encodedRange):append")
        components?.queryItems = [
            // RAW keeps "HH:mm:ss" as text so Sheets does not convert it to a day-fraction number.
            URLQueryItem(name: "valueInputOption", value: "RAW"),
            URLQueryItem(name: "insertDataOption", value: "INSERT_ROWS")
        ]

        guard let url = components?.url else {
            throw SheetsSyncError.httpError(0, "Invalid Sheets URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "values": [[
                "\(record.id)",
                record.name,
                record.purpose,
                record.dateString,
                record.timeString
            ]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SheetsSyncError.httpError(0, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw SheetsSyncError.httpError(http.statusCode, message)
        }
    }
}

enum ConfigStore {
    static func load() throws -> AppConfig {
        let url = AppPaths.configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try save(.default)
            return .default
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    static func save(_ config: AppConfig) throws {
        let data = try JSONEncoder().encode(config)
        try data.write(to: AppPaths.configURL, options: .atomic)
    }
}
