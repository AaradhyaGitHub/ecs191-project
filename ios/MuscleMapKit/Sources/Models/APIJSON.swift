import Foundation

/// JSON settings shared by every API call (API.md "Conventions"):
/// snake_case keys on the wire, camelCase in Swift; ISO 8601 timestamps.
public enum APIJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseTimestamp(text) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Not an ISO 8601 timestamp: \(text)")
            }
            return date
        }
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatTimestamp(date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Accepts `2026-11-02T17:02:00Z`, `...00.123Z` and Python's `...00.123456+00:00`.
    public static func parseTimestamp(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601) { return date }
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let date = try? Date(text, strategy: withFraction) { return date }
        // Python can send 6 fractional digits; keep 3 and retry.
        let trimmed = text.replacingOccurrences(
            of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        return try? Date(trimmed, strategy: withFraction)
    }

    /// Always UTC with a `Z`, whole seconds: `2026-11-02T17:02:00Z`.
    public static func formatTimestamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}

/// IDs the phone makes (workouts, sets, saved workouts): lowercase UUID strings,
/// because Datastore keys are case-sensitive and a retry must match exactly.
public enum ClientID {
    public static func make() -> String {
        UUID().uuidString.lowercased()
    }
}
