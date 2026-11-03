import Foundation

/// Per-build settings. Debug builds talk to the server on this Mac; Release builds
/// (what testers get) talk to App Engine.
enum AppConfig {
    #if DEBUG
    /// The local Flask server (README: "Run the server locally"). The simulator can reach
    /// localhost; a real phone needs this Mac's network address instead.
    static let apiBaseURL = URL(string: "http://localhost:5000")!
    #else
    /// Set to the App Engine URL after the first deploy (issue #10). `.invalid` never
    /// resolves, so a Release build fails clearly until then instead of hitting a wrong server.
    static let apiBaseURL = URL(string: "https://set-after-first-deploy.invalid")!
    #endif
}
