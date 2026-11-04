import Foundation
import Models

/// What can go wrong talking to the server. Screens show one error state, keyed on this.
public enum APIError: Error, Equatable, Sendable {
    /// The server answered with API.md's error shape.
    case server(status: Int, code: APIErrorCode, message: String)
    /// A non-2xx status without the error shape (e.g. a proxy page).
    case unexpectedStatus(Int)
    /// The body didn't match the model.
    case decoding(String)
    /// No connection, timeout, DNS, etc.
    case transport(URLError.Code)
}

/// One async client, one method per endpoint in API.md.
/// The base URL comes from the app's build configuration (Debug: localhost; Release: App Engine).
public struct APIClient: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let tokens: any TokenStore

    /// - Parameter baseURL: the server root, e.g. `http://localhost:5000`; `/api/v1` is added here.
    public init(baseURL: URL, session: URLSession = .shared, tokens: any TokenStore = InMemoryTokenStore()) {
        self.baseURL = baseURL
        self.session = session
        self.tokens = tokens
    }

    // MARK: Endpoints

    public func health() async throws -> Health {
        try await send("GET", "/health", authorized: false)
    }

    public func me() async throws -> User {
        try await send("GET", "/users/me")
    }

    /// Partial update: only the fields set in `update` are sent.
    public func updateMe(_ update: UserUpdate) async throws -> User {
        try await send("PUT", "/users/me", body: update)
    }

    /// Search by name or alias; `nil` or empty returns the whole library.
    public func searchExercises(_ query: String? = nil) async throws -> [Exercise] {
        let items = query.flatMap { $0.isEmpty ? nil : [URLQueryItem(name: "q", value: $0)] } ?? []
        let list: ExerciseList = try await send("GET", "/exercises", query: items)
        return list.exercises
    }

    public func myExercises() async throws -> [UserExercise] {
        let list: UserExerciseList = try await send("GET", "/exercises/mine")
        return list.exercises
    }

    public func templates() async throws -> [Template] {
        let list: TemplateList = try await send("GET", "/templates")
        return list.templates
    }

    public func createTemplate(_ template: TemplateInput) async throws -> Template {
        try await send("POST", "/templates", body: template)
    }

    public func updateTemplate(_ template: TemplateInput) async throws -> Template {
        try await send("PUT", "/templates/\(template.id)", body: template)
    }

    public func deleteTemplate(id: String) async throws {
        _ = try await data("DELETE", "/templates/\(id)", body: Optional<Empty>.none)
    }

    /// Saves a finished workout. Safe to retry: the server answers 201 the first time and
    /// 200 with the same body for a repeat, and both count as success.
    public func saveWorkout(_ workout: Workout) async throws -> Workout {
        try await send("POST", "/workouts", body: workout)
    }

    /// Newest first. `before` pages back through history (API.md).
    public func workouts(limit: Int = 20, before: Date? = nil) async throws -> [WorkoutSummary] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let before {
            items.append(URLQueryItem(name: "before", value: APIJSON.formatTimestamp(before)))
        }
        let list: WorkoutList = try await send("GET", "/workouts", query: items)
        return list.workouts
    }

    public func workout(id: String) async throws -> Workout {
        try await send("GET", "/workouts/\(id)")
    }

    // MARK: Plumbing

    private struct Empty: Encodable {}

    private func send<Response: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], authorized: Bool = true
    ) async throws -> Response {
        try await send(method, path, query: query, body: Optional<Empty>.none, authorized: authorized)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Body?,
        authorized: Bool = true
    ) async throws -> Response {
        let data = try await data(method, path, query: query, body: body, authorized: authorized)
        do {
            return try APIJSON.decoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func data<Body: Encodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Body?,
        authorized: Bool = true
    ) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appending(path: "api/v1").appending(path: path),
            resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try APIJSON.encoder().encode(body)
        }
        if authorized, let token = tokens.token() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.transport(error.code)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
                throw APIError.server(status: status, code: body.error.code, message: body.error.message)
            }
            throw APIError.unexpectedStatus(status)
        }
        return data
    }
}
