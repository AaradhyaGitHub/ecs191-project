import Foundation
import Testing
import Networking
@testable import GoalsCore

/// Review fix S-4: the fallback error text depends on what the user was doing.
@MainActor
@Suite("Goals error text")
struct GoalsErrorTextTests {
    struct Odd: Error {}

    @Test("S-4: an unknown error while loading says the goals couldn't load")
    func loadFallback() {
        #expect(GoalsScreenModel.message(for: Odd()) == "Couldn't load your goals.")
        #expect(GoalsScreenModel.message(for: Odd(), during: .load) == "Couldn't load your goals.")
    }

    @Test("S-4: an unknown error while saving or deleting asks to try again",
          arguments: [GoalsScreenModel.Action.save, .delete])
    func writeFallback(action: GoalsScreenModel.Action) {
        #expect(GoalsScreenModel.message(for: Odd(), during: action) == "Something went wrong. Try again.")
        #expect(GoalsScreenModel.message(for: APIError.unexpectedStatus(502), during: action)
                == "Something went wrong. Try again.")
    }

    @Test("S-4: the server's message and the offline text are kept for writes",
          arguments: [GoalsScreenModel.Action.save, .delete])
    func knownErrorsUnchanged(action: GoalsScreenModel.Action) {
        let conflict = APIError.server(status: 409, code: .conflict, message: "You can have at most 3 active goals.")
        #expect(GoalsScreenModel.message(for: conflict, during: action) == "You can have at most 3 active goals.")
        #expect(GoalsScreenModel.message(for: APIError.transport(.notConnectedToInternet), during: action)
                == "Can't reach the server.")
    }
}
