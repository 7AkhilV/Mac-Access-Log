import Foundation

enum SyncStatus: String, Codable {
    case pending = "PENDING"
    case synced = "SYNCED"
}

struct AccessRecord: Identifiable, Equatable {
    let id: Int64
    var name: String
    var purpose: String
    var createdAt: Date
    var syncStatus: SyncStatus
    var syncedAt: Date?

    var dateString: String {
        Self.dateFormatter.string(from: createdAt)
    }

    var timeString: String {
        Self.timeFormatter.string(from: createdAt)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB_POSIX")
        f.timeZone = TrustedTimeService.ist
        f.dateFormat = "dd-MM-yyyy"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB_POSIX")
        f.timeZone = TrustedTimeService.ist
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
