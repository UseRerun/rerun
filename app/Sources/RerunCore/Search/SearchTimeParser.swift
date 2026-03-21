import Foundation

public enum SearchTimeParser {
    public static func parseSince(_ value: String, now: Date = Date()) -> String? {
        let pattern = /^(\d+)([mhdw])$/
        if let match = value.wholeMatch(of: pattern) {
            guard let amount = UInt64(String(match.1)) else { return nil }

            let unitSeconds: UInt64
            switch match.2 {
            case "m": unitSeconds = 60
            case "h": unitSeconds = 3600
            case "d": unitSeconds = 86400
            case "w": unitSeconds = 604800
            default: return nil
            }

            let (totalSeconds, overflow) = amount.multipliedReportingOverflow(by: unitSeconds)
            guard !overflow else { return nil }

            return canonicalISO8601(Date(timeInterval: -TimeInterval(totalSeconds), since: now))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateFormatter.date(from: value) {
            return canonicalISO8601(date)
        }

        if let date = parseISO8601(value) {
            return canonicalISO8601(date)
        }

        return nil
    }

    private static func canonicalISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: value)
    }
}
