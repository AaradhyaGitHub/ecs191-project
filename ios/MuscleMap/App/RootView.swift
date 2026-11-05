import SwiftUI

/// The four tabs, each with icon and label. Lift is the first tab built for real;
/// Camera is behind `FeatureFlags.cameraTab`.
struct RootView: View {
    var showsCameraTab = FeatureFlags.cameraTab

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tabBarStyle()
            // Body: the MuscleLab page (anatomy figure + workout stats), imported from the Map prototype.
            MuscleLabScreen()
                .tabItem { Label("Body", systemImage: "figure.strengthtraining.traditional") }
                .tabBarStyle()
            LiftView()
                .tabItem { Label("Lift", systemImage: "dumbbell.fill") }
                .tabBarStyle()
            GoalsView()
                .tabItem { Label("Goals", systemImage: "target") }
                .tabBarStyle()
            if showsCameraTab {
                CameraView()
                    .tabItem { Label("Camera", systemImage: "camera.viewfinder") }
                    .tabBarStyle()
            }
        }
        .tint(Theme.Colors.accent)
        .preferredColorScheme(.dark)
    }
}

private extension View {
    /// Tab bar on the app background, as in the mockups.
    func tabBarStyle() -> some View {
        toolbarBackground(Theme.Colors.background, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
}

#Preview("All tabs") {
    RootView(showsCameraTab: true)
}

#Preview("Testers (no Camera)") {
    RootView(showsCameraTab: false)
}
