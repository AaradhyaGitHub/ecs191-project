import SwiftUI
import Networking

@main
struct MuscleMapApp: App {
    /// The one API client the app shares; the sign-in token lives in the Keychain.
    private let apiClient = APIClient(baseURL: AppConfig.apiBaseURL, tokens: KeychainTokenStore())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.apiClient, apiClient)
        }
    }
}

extension EnvironmentValues {
    /// The shared API client. The default (used by previews) keeps its token in memory only.
    @Entry var apiClient = APIClient(baseURL: AppConfig.apiBaseURL)
}
