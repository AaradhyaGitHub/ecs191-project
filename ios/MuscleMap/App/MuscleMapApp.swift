import SwiftUI
import Networking
import LiftCore

@main
struct MuscleMapApp: App {
    /// The one API client the app shares; the sign-in token lives in the Keychain.
    private let apiClient: APIClient
    /// The open workout and the outbox, kept on the phone (plan: specs/log-workout.llm.md).
    @State private var session: LiftSession
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let apiClient = APIClient(baseURL: AppConfig.apiBaseURL, tokens: KeychainTokenStore())
        let (storage, isTemporary) = Self.makeStorage()
        self.apiClient = apiClient
        _session = State(initialValue: LiftSession(
            storage: storage, outbox: WorkoutOutbox(storage: storage, sender: apiClient),
            storageIsTemporary: isTemporary))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.apiClient, apiClient)
                .environment(session)
                .task {
                    await signInForDevelopment()
                    await session.outbox.sendPending()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await session.outbox.sendPending() } }
                }
        }
    }

    /// The phone's store, and whether it is a stand-in in memory.
    /// If the store on disk can't open, Debug builds stop at once with the reason, so a developer
    /// sees a model mismatch. Release builds keep this run's workouts in memory, and Lift says
    /// "Workouts can't be saved on this phone right now."
    private static func makeStorage() -> (SwiftDataWorkoutStorage, isTemporary: Bool) {
        do {
            return (try SwiftDataWorkoutStorage(), false)
        } catch {
            #if DEBUG
            fatalError("The workout store on this device can't open: \(error)")
            #else
            // In-memory storage needs no disk, so this does not fail in practice.
            return (try! SwiftDataWorkoutStorage(inMemory: true), true)
            #endif
        }
    }

    /// Debug builds sign in with the course test number when there's no token (D-9).
    /// Release builds keep finished workouts in the outbox until sign-in screens exist.
    private func signInForDevelopment() async {
        #if DEBUG
        guard !apiClient.isSignedIn else { return }
        do {
            try await apiClient.startSignIn(phoneNumber: APIClient.testPhoneNumber)
            try await apiClient.verifySignIn(phoneNumber: APIClient.testPhoneNumber, code: APIClient.testCode)
        } catch {
            // The server may be down; the next launch tries again.
        }
        #endif
    }
}

extension EnvironmentValues {
    /// The shared API client. The default (used by previews) keeps its token in memory only.
    @Entry var apiClient = APIClient(baseURL: AppConfig.apiBaseURL)
}
