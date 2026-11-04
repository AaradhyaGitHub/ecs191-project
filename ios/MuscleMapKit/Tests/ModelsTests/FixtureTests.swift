import Foundation
import Testing
@testable import Models

/// The contract tests: every example in shared/fixtures (copied from API.md) must decode,
/// and what the app sends must match the shapes the server expects.
@Suite("API fixtures")
struct FixtureTests {
    static let fixtures = URL(filePath: #filePath)
        .deletingLastPathComponent() // ModelsTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // MuscleMapKit
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // repo root
        .appending(path: "shared/fixtures")

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: fixtures.appending(path: "\(name).json"))
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try APIJSON.decoder().decode(type, from: fixture(name))
    }

    static func json(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test("User decodes")
    func user() throws {
        let user = try Self.decode(User.self, "user")
        #expect(user.displayName == "Sasa")
        #expect(user.units == .lb)
        #expect(user.experience == .intermediate)
        #expect(user.bodyweightKg == 82.1)
    }

    @Test("AC-11 (#42): a new user decodes with no name and lb")
    func newUser() throws {
        let user = try Self.decode(User.self, "user_new")
        #expect(user.displayName == nil)
        #expect(user.units == .lb)
        #expect(user.bodyweightKg == nil)
        #expect(user.experience == nil)
    }

    @Test("A partial user update sends only the fields that are set")
    func userUpdate() throws {
        let update = UserUpdate(bodyweightKg: 81.5, units: .kg)
        let sent = try Self.json(APIJSON.encoder().encode(update))
        #expect(sent == (try Self.json(Self.fixture("user_update"))))
    }

    @Test("Exercise search decodes, muscles included")
    func exercises() throws {
        let list = try Self.decode(ExerciseList.self, "exercises_search")
        let bench = try #require(list.exercises.first)
        #expect(bench.loadType == .barbell)
        #expect(bench.aliases == ["bench", "BP"])
        #expect(bench.muscles.first == ExerciseMuscle(muscleId: "chest_sternal", role: .primary, weight: 1.0))
    }

    @Test("AC-10: Exercise decodes groups and primary_muscles from the search fixture")
    func exerciseGroups() throws {
        let list = try Self.decode(ExerciseList.self, "exercises_search")
        let bench = try #require(list.exercises.first { $0.id == "barbell_bench_press" })
        #expect(bench.groups == ["chest"])
        #expect(bench.primaryMuscles == ["Chest"])
        let deadlift = try #require(list.exercises.first { $0.id == "deadlift" })
        #expect(deadlift.groups == ["legs", "back"])
        #expect(deadlift.primaryMuscles == ["Glutes", "Lower back", "Hamstrings"])
    }

    @Test("AC-10: an older server's exercise without groups still decodes, with empty lists")
    func exerciseWithoutGroups() throws {
        let json = #"{"id": "x", "name": "X", "aliases": [], "load_type": "barbell", "muscles": []}"#
        let exercise = try APIJSON.decoder().decode(Exercise.self, from: Data(json.utf8))
        #expect(exercise.groups == [])
        #expect(exercise.primaryMuscles == [])
    }

    @Test("My exercises decode, including e1RM fields and the last set")
    func myExercises() throws {
        let list = try Self.decode(UserExerciseList.self, "exercises_mine")
        let pushUp = try #require(list.exercises.first)
        #expect(pushUp.id == "push_up")
        #expect(pushUp.useCount == 14)
        #expect(pushUp.lastSet?.reps == 20)
        #expect(pushUp.bestE1rmKg == nil)
    }

    @Test("Saved workouts decode with their muscle chips")
    func templates() throws {
        let list = try Self.decode(TemplateList.self, "templates")
        let push = try #require(list.templates.first)
        #expect(push.exercises.first?.restS == 180)
        #expect(push.topMuscles.map(\.muscleId) == ["chest", "delts", "triceps"])
        #expect(push.lastDoneAt != nil)
    }

    @Test("Workout history decodes")
    func workoutList() throws {
        let list = try Self.decode(WorkoutList.self, "workouts_list")
        #expect(list.workouts.first?.setCount == 31)
        #expect(list.workouts.first?.localDate == "2026-11-02")
    }

    @Test("A workout with Python-style timestamps (microseconds, +00:00) decodes")
    func workoutDetail() throws {
        let workout = try Self.decode(Workout.self, "workout_detail")
        #expect(workout.status == .finished)
        let expected = try #require(APIJSON.parseTimestamp("2026-11-02T17:02:00.123Z"))
        #expect(abs(workout.startedAt.timeIntervalSince(expected)) < 0.001)
        #expect(workout.sets.first?.timeSource == .restTimer)
    }

    @Test("The workout the app sends matches POST /workouts in API.md")
    func workoutRoundTrip() throws {
        let original = try Self.decode(Workout.self, "workout_post")
        let sent = try APIJSON.encoder().encode(original)
        #expect(try APIJSON.decoder().decode(Workout.self, from: sent) == original)

        let body = try Self.json(sent)
        #expect(body["started_at"] as? String == "2026-11-02T17:02:00Z")
        #expect(body["local_date"] as? String == "2026-11-02")
        #expect(body["status"] == nil, "status is the server's to set")
        let firstSet = try #require((body["sets"] as? [NSDictionary])?.first)
        #expect(firstSet["exercise_id"] as? String == "barbell_bench_press")
        #expect(firstSet["time_source"] as? String == "rest_timer")
    }

    @Test("The sign-in response decodes")
    func signIn() throws {
        let signIn = try Self.decode(SignIn.self, "auth_verify_response")
        #expect(signIn.userId == "5642800292954112")
        #expect(!signIn.token.isEmpty)
    }

    @Test("Phone-made IDs are lowercase UUIDs, so retries match exactly")
    func clientIDs() {
        let id = ClientID.make()
        #expect(id == id.lowercased())
        #expect(UUID(uuidString: id) != nil)
    }

    @Test("Timestamps are sent as whole-second UTC with Z")
    func timestampFormat() throws {
        let date = try #require(APIJSON.parseTimestamp("2026-11-02T17:02:00Z"))
        #expect(APIJSON.formatTimestamp(date) == "2026-11-02T17:02:00Z")
    }
}
