import Foundation
import Testing
import Models
@testable import LiftCore

/// The picker's search timing (Issue #44, S1). Written by implementer (not test-writer).
/// The pause is injected, so no test waits real time.
@Suite("Picker search timing")
@MainActor
struct PickerSearchTests {
    nonisolated static let library = [
        Exercise(id: "barbell_bench_press", name: "Bench Press", loadType: .barbell),
        Exercise(id: "back_squat", name: "Back Squat", loadType: .barbell),
        Exercise(id: "push_up", name: "Push-up", loadType: .bodyweight),
    ]

    /// Answers a search with the library filtered by name. A query in `held` waits until
    /// `release(_:)`, so a test can make an old reply arrive late.
    final class StubSource: ExerciseSource, @unchecked Sendable {
        private let lock = NSLock()
        private var queries: [String?] = []
        private var gates: [String: CheckedContinuation<Void, Never>] = [:]
        private let held: Set<String>

        init(held: Set<String> = []) { self.held = held }

        var isSignedIn: Bool { true }
        var received: [String?] { lock.withLock { queries } }

        func searchExercises(_ query: String?, group: String?) async throws -> [Exercise] {
            lock.withLock { queries.append(query) }
            if let query, held.contains(query) {
                await withCheckedContinuation { continuation in
                    lock.withLock { gates[query] = continuation }
                }
            }
            guard let text = query?.lowercased() else { return PickerSearchTests.library }
            return PickerSearchTests.library.filter { $0.name.lowercased().contains(text) }
        }

        func isWaiting(_ query: String) -> Bool { lock.withLock { gates[query] != nil } }

        func release(_ query: String) {
            lock.withLock { gates.removeValue(forKey: query) }?.resume()
        }

        func myExercises() async throws -> [UserExercise] { [] }
    }

    /// Records each pause and returns at once.
    final class Pauses: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Duration] = []
        var recorded: [Duration] { lock.withLock { values } }
        func sleep(_ duration: Duration) async throws { lock.withLock { values.append(duration) } }
    }

    /// Lets other tasks run until `condition` holds (or gives up, so a failure doesn't hang).
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() {
            await Task.yield()
        }
    }

    @Test("Quick keystrokes send one request, with the last text, after the pause")
    func quickKeystrokes() async {
        let source = StubSource()
        let pauses = Pauses()
        let search = ExerciseSearch(source: source, sleep: pauses.sleep)
        for text in ["b", "be", "ben", "benc", "bench"] {
            search.search(text, group: nil, after: ExerciseSearch.typingDelay)
        }
        await search.settle()
        #expect(source.received == ["bench"])
        #expect(search.results.map(\.id) == ["barbell_bench_press"])
        #expect(search.state == .loaded)
        #expect(pauses.recorded.allSatisfy { $0 == .milliseconds(300) })
    }

    @Test("A slow reply for old text that arrives after a newer reply doesn't replace it")
    func slowOldReply() async {
        let source = StubSource(held: ["b"])
        let search = ExerciseSearch(source: source, sleep: { _ in })
        search.search("b", group: nil, after: .zero)
        await waitUntil { source.isWaiting("b") }
        #expect(source.isWaiting("b"))

        search.search("push", group: nil, after: .zero)
        await waitUntil { search.state == .loaded }
        #expect(search.results.map(\.id) == ["push_up"])

        source.release("b")
        await search.settle()
        #expect(source.received == ["b", "push"])
        #expect(search.results.map(\.id) == ["push_up"], "the late reply for 'b' is dropped")
        #expect(search.resultsText == "push")
        #expect(search.state == .loaded)
    }

    @Test("A blank query loads the whole library", arguments: ["", "   "])
    func blankQuery(text: String) async {
        let source = StubSource()
        let search = ExerciseSearch(source: source, sleep: { _ in })
        search.search(text, group: nil, after: ExerciseSearch.typingDelay)
        await search.settle()
        #expect(source.received == [nil])
        #expect(search.results == Self.library)
        #expect(search.resultsText == "")
        #expect(search.state == .loaded)
    }
}
