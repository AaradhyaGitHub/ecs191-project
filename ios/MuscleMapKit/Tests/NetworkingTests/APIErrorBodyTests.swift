import Foundation
import Testing
@testable import Networking

@Suite("API error body")
struct APIErrorBodyTests {
    private func decode(_ json: String) throws -> APIErrorBody {
        try JSONDecoder().decode(APIErrorBody.self, from: Data(json.utf8))
    }

    @Test("Decodes the API.md error shape")
    func decodesKnownCode() throws {
        let body = try decode(#"{"error": {"code": "not_found", "message": "No workout with that id."}}"#)
        #expect(body.error.code == .notFound)
        #expect(body.error.message == "No workout with that id.")
    }

    @Test("An unknown code decodes as .unknown instead of failing")
    func unknownCode() throws {
        let body = try decode(#"{"error": {"code": "rate_limited", "message": "Slow down."}}"#)
        #expect(body.error.code == .unknown)
    }
}
