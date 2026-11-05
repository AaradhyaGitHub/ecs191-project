import Foundation

/// Per-build settings. Debug builds on the Simulator talk to the server on this Mac.
/// Everything else (Debug on a real phone, and Release) talks to App Engine, because a
/// phone can't reach this Mac's localhost.
enum AppConfig {
    #if DEBUG && targetEnvironment(simulator)
    /// The local Flask server (README: "Run the server locally").
    static let apiBaseURL = URL(string: "http://localhost:5001")!
    #else
    /// The live server on App Engine (project musclemap-ecs191, region us-west2).
    /// Debug builds on a phone sign in with the shared, public test number.
    static let apiBaseURL = URL(string: "https://musclemap-ecs191.wl.r.appspot.com")!
    #endif
}
