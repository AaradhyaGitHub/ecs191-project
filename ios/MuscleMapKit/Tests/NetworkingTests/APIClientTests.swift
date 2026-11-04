import Foundation
import Testing
import Models
@testable import Networking

/// A fake server: each test sets what it answers, and records the request it got.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var reply = Reply(status: 200, body: Data())
    nonisolated(unsafe) private static var error: URLError?
    nonisolated(unsafe) private(set) static var lastRequest: URLRequest?
    nonisolated(unsafe) private(set) static var lastBody: Data?

    static func answer(_ status: Int, _ body: String = "") {
        lock.withLock { reply = Reply(status: status, body: Data(body.utf8)); error = nil }
    }

    static func fail(_ code: URLError.Code) {
        lock.withLock { error = URLError(code) }
    }

    static var request: URLRequest? { lock.withLock { lastRequest } }
    static var body: Data? { lock.withLock { lastBody } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (reply, error) = Self.lock.withLock { () -> (Reply, URLError?) in
            Self.lastRequest = request
            Self.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.read)
            return (Self.reply, Self.error)
        }
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@Suite("API client", .serialized)
struct APIClientTests {
    let client: APIClient

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        client = APIClient(baseURL: URL(string: "http://localhost:5000")!,
                           session: URLSession(configuration: config),
                           tokens: InMemoryTokenStore("secret-token"))
    }

    @Test("Health calls /api/v1/health without a token")
    func health() async throws {
        StubURLProtocol.answer(200, #"{"status": "ok"}"#)
        let health = try await client.health()
        #expect(health.status == "ok")
        let request = try #require(StubURLProtocol.request)
        #expect(request.url?.absoluteString == "http://localhost:5000/api/v1/health")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Search sends q and the bearer token, and unwraps the list")
    func search() async throws {
        StubURLProtocol.answer(200, #"{"exercises": [{"id": "barbell_bench_press", "name": "Bench Press", "aliases": [], "load_type": "barbell", "muscles": []}]}"#)
        let results = try await client.searchExercises("bench")
        #expect(results.map(\.id) == ["barbell_bench_press"])
        let request = try #require(StubURLProtocol.request)
        #expect(request.url?.query == "q=bench")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
    }

    @Test("An empty search asks for the whole library (no q)")
    func emptySearch() async throws {
        StubURLProtocol.answer(200, #"{"exercises": []}"#)
        _ = try await client.searchExercises("")
        #expect(StubURLProtocol.request?.url?.query == nil)
    }

    private static let emptyList = #"{"exercises": []}"#

    private func searchQuery(_ text: String?, group: String?) async throws -> [String: String]? {
        StubURLProtocol.answer(200, Self.emptyList)
        _ = try await client.searchExercises(text, group: group)
        let url = try #require(StubURLProtocol.request?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        return items.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.name, $0.value ?? "") }) }
    }

    @Test("AC-15: search sends q and group together")
    func searchSendsBoth() async throws {
        let query = try await searchQuery("bench", group: "chest")
        #expect(query == ["q": "bench", "group": "chest"])
        #expect(StubURLProtocol.request?.url?.path == "/api/v1/exercises")
    }

    @Test("AC-15: search sends only group when the text is nil")
    func searchGroupOnly() async throws {
        let query = try await searchQuery(nil, group: "legs")
        #expect(query == ["group": "legs"])
    }

    @Test("AC-15: a blank q is not sent", arguments: ["", "   "])
    func searchBlankText(text: String) async throws {
        let query = try await searchQuery(text, group: nil)
        #expect(query == nil)
    }

    @Test("AC-15: a blank q is not sent, but the group still is")
    func searchBlankTextWithGroup() async throws {
        let query = try await searchQuery("  ", group: "core")
        #expect(query == ["group": "core"])
    }

    @Test("AC-15: no text and no group sends no query at all")
    func searchNoQuery() async throws {
        let query = try await searchQuery(nil, group: nil)
        #expect(query == nil)
    }

    @Test("AC-15: my exercises calls /exercises/mine with the token and decodes the list")
    func myExercisesSendsToken() async throws {
        StubURLProtocol.answer(200, #"{"exercises": [{"exercise_id": "push_up", "use_count": 14, "last_used_at": "2026-11-01T18:10:00Z", "last_set": null}]}"#)
        let mine = try await client.myExercises()
        #expect(mine.map(\.exerciseId) == ["push_up"])
        let request = try #require(StubURLProtocol.request)
        #expect(request.url?.path == "/api/v1/exercises/mine")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
    }

    @Test("The server's error shape becomes APIError.server")
    func serverError() async throws {
        StubURLProtocol.answer(404, #"{"error": {"code": "not_found", "message": "No workout with that id."}}"#)
        await #expect(throws: APIError.server(status: 404, code: .notFound, message: "No workout with that id.")) {
            _ = try await client.workout(id: "missing")
        }
    }

    @Test("A non-JSON error page becomes unexpectedStatus")
    func unexpectedStatus() async throws {
        StubURLProtocol.answer(502, "<html>Bad Gateway</html>")
        await #expect(throws: APIError.unexpectedStatus(502)) {
            _ = try await client.templates()
        }
    }

    @Test("No connection becomes a transport error")
    func transport() async throws {
        StubURLProtocol.fail(.notConnectedToInternet)
        await #expect(throws: APIError.transport(.notConnectedToInternet)) {
            _ = try await client.health()
        }
    }

    @Test("Saving a workout succeeds on 201 and on a repeat's 200", arguments: [201, 200])
    func saveWorkout(status: Int) async throws {
        let workout = Workout(id: "6f1c2b1e-4b7a-4c3e-9d2a-0a1b2c3d4e5f", name: "Push 1",
                              startedAt: Date(timeIntervalSince1970: 1_793_034_120),
                              timezone: "America/Los_Angeles", localDate: "2026-11-02")
        let reply = String(decoding: try APIJSON.encoder().encode(workout), as: UTF8.self)
        StubURLProtocol.answer(status, reply)

        let saved = try await client.saveWorkout(workout)
        #expect(saved.id == workout.id)
        let request = try #require(StubURLProtocol.request)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/v1/workouts")
        let sent = try #require(StubURLProtocol.body)
        #expect(String(decoding: sent, as: UTF8.self).contains(#""local_date":"2026-11-02""#))
    }

    @Test("History pages back with limit and before")
    func workoutsPaging() async throws {
        StubURLProtocol.answer(200, #"{"workouts": []}"#)
        let before = try #require(APIJSON.parseTimestamp("2026-10-01T00:00:00Z"))
        _ = try await client.workouts(limit: 20, before: before)
        let query = try #require(StubURLProtocol.request?.url?.query)
        #expect(query == "limit=20&before=2026-10-01T00:00:00Z")
    }

    @Test("Deleting a saved workout accepts an empty 204")
    func deleteTemplate() async throws {
        StubURLProtocol.answer(204)
        try await client.deleteTemplate(id: "tpl_push1")
        #expect(StubURLProtocol.request?.httpMethod == "DELETE")
        #expect(StubURLProtocol.request?.url?.path == "/api/v1/templates/tpl_push1")
    }

    @Test("Starting sign-in posts the phone number without a token")
    func startSignIn() async throws {
        StubURLProtocol.answer(200, #"{"sent": true}"#)
        try await client.startSignIn(phoneNumber: APIClient.testPhoneNumber)
        let request = try #require(StubURLProtocol.request)
        #expect(request.url?.path == "/api/v1/auth/sms/start")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let sent = String(decoding: try #require(StubURLProtocol.body), as: UTF8.self)
        #expect(sent == #"{"phone_number":"+15305550000"}"#)
    }

    @Test("Verifying saves the token, so later requests are signed in")
    func verifySavesToken() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let tokens = InMemoryTokenStore()
        let fresh = APIClient(baseURL: URL(string: "http://localhost:5000")!,
                              session: URLSession(configuration: config), tokens: tokens)
        #expect(!fresh.isSignedIn)

        StubURLProtocol.answer(200, #"{"token": "example-session-token-not-real", "user_id": "5642800292954112"}"#)
        let signIn = try await fresh.verifySignIn(phoneNumber: APIClient.testPhoneNumber, code: APIClient.testCode)
        #expect(signIn.userId == "5642800292954112")
        #expect(tokens.token() == "example-session-token-not-real")
        #expect(fresh.isSignedIn)

        StubURLProtocol.answer(200, #"{"exercises": []}"#)
        _ = try await fresh.myExercises()
        #expect(StubURLProtocol.request?.value(forHTTPHeaderField: "Authorization") == "Bearer example-session-token-not-real")
    }

    @Test("A wrong code surfaces as unauthorized and saves nothing")
    func wrongCode() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let tokens = InMemoryTokenStore()
        let fresh = APIClient(baseURL: URL(string: "http://localhost:5000")!,
                              session: URLSession(configuration: config), tokens: tokens)
        StubURLProtocol.answer(401, #"{"error": {"code": "unauthorized", "message": "Invalid or expired code"}}"#)
        await #expect(throws: APIError.server(status: 401, code: .unauthorized, message: "Invalid or expired code")) {
            try await fresh.verifySignIn(phoneNumber: APIClient.testPhoneNumber, code: "000000")
        }
        #expect(tokens.token() == nil)
    }

    @Test("A body that doesn't match the model becomes a decoding error")
    func decodingError() async throws {
        StubURLProtocol.answer(200, #"{"unexpected": true}"#)
        await #expect {
            _ = try await client.me()
        } throws: { error in
            if case APIError.decoding = error { return true }
            return false
        }
    }
}
