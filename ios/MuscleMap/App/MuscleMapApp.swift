import SwiftUI
import Networking
import LiftCore
import UserNotifications

@main
struct MuscleMapApp: App {
    /// The one API client the app shares; the sign-in token lives in the Keychain.
    private let apiClient: APIClient
    /// The open workout and the outbox, kept on the phone (plan: specs/log-workout.llm.md).
    @State private var session: LiftSession
    /// The rest countdown's beeps, taps and notices, on any screen (#67).
    private let restAlerts = RestAlertController()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let apiClient = APIClient(baseURL: AppConfig.apiBaseURL, tokens: KeychainTokenStore())
        let (storage, isTemporary) = Self.makeStorage()
        self.apiClient = apiClient
        _session = State(initialValue: LiftSession(
            storage: storage, outbox: WorkoutOutbox(storage: storage, sender: apiClient),
            storageIsTemporary: isTemporary))
        // Set at launch, so a rest notice that arrives while the app is open stays hidden.
        UNUserNotificationCenter.current().delegate = restAlerts
    }

    var body: some Scene {
        WindowGroup {
            // Welcome, sign-in and onboarding until the account is set up, then the tabs (#64).
            LaunchGate(onSignedIn: { await session.outbox.sendPending() }) {
                RootView()
            }
            .environment(\.apiClient, apiClient)
            .environment(session)
            .task { await session.outbox.sendPending() }
            .onChange(of: scenePhase) { _, phase in
                restAlerts.scenePhaseChanged(phase)
                if phase == .active { Task { await session.outbox.sendPending() } }
            }
            .onChange(of: session.active?.restTimer.endsAt, initial: true) { _, endsAt in
                restAlerts.update(endsAt: endsAt)
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
}

extension EnvironmentValues {
    /// The shared API client. The default (used by previews) keeps its token in memory only.
    @Entry var apiClient = APIClient(baseURL: AppConfig.apiBaseURL)
}
