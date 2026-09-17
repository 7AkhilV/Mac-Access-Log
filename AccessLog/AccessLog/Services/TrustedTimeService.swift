import Foundation

/// Resolves a trustworthy wall-clock time.
/// On boot the Mac clock is often wrong until Wi‑Fi/NTP syncs, so we prefer
/// network time (HTTP Date) and fall back to the device clock only offline.
enum TrustedTimeService {
    static let ist = TimeZone(identifier: "Asia/Kolkata")!

    /// Returns network time when reachable, otherwise `Date()`.
    static func now() async -> (date: Date, fromNetwork: Bool) {
        if let networkDate = await fetchNetworkDate() {
            return (networkDate, true)
        }
        return (Date(), false)
    }

    private static func fetchNetworkDate() async -> Date? {
        // google.com is already used by Sheets sync; HEAD gives a reliable Date header.
        guard let url = URL(string: "https://www.google.com") else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  let dateValue = http.value(forHTTPHeaderField: "Date") else {
                return nil
            }
            return httpDateFormatter.date(from: dateValue)
        } catch {
            return nil
        }
    }

    private static let httpDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
        return f
    }()
}
