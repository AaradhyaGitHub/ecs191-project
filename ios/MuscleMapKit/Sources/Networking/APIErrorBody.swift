import Foundation

/// The server's error shape (API.md "Errors"): {"error": {"code": "...", "message": "..."}}.
public struct APIErrorBody: Decodable, Equatable, Sendable {
    public struct Detail: Decodable, Equatable, Sendable {
        public let code: APIErrorCode
        public let message: String
    }

    public let error: Detail
}

/// The fixed list of codes in API.md. Anything else decodes as `.unknown`, so a newer
/// server can't crash an older app.
public enum APIErrorCode: String, Decodable, Equatable, Sendable {
    case badRequest = "bad_request"
    case unauthorized
    case forbidden
    case notFound = "not_found"
    case conflict
    case `internal`
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = APIErrorCode(rawValue: raw) ?? .unknown
    }
}
