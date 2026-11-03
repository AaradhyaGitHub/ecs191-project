/// Switches for unfinished features.
enum FeatureFlags {
    /// The Camera tab (rep counting) is a stretch goal. It shows in Debug builds for the
    /// team, and stays hidden in Release builds, which is what testers get.
    #if DEBUG
    static let cameraTab = true
    #else
    static let cameraTab = false
    #endif
}
