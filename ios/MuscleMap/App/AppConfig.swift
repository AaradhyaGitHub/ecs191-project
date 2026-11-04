import Foundation

/// Per-build settings. Debug builds talk to the server on this Mac; Release builds
/// (what testers get) talk to App Engine.
enum AppConfig {
    #if DEBUG
    /// The local Flask server (README: "Run the server locally"). The simulator can reach
    /// localhost; a real phone needs this Mac's network address instead.
    static let apiBaseURL = URL(string: "http://localhost:5001")!
    #else
    /// The live server on App Engine (project musclemap-ecs191, region us-west2).
    static let apiBaseURL = URL(string: "https://musclemap-ecs191.wl.r.appspot.com")!
    #endif
}
