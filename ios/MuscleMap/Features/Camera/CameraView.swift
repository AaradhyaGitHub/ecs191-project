import SwiftUI

/// Camera: record a set and count reps (stretch goal). Hidden from testers by
/// `FeatureFlags.cameraTab`.
struct CameraView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Camera",
            systemImage: "camera.viewfinder",
            message: "Record a set and count reps. Coming later."
        )
    }
}

#Preview {
    CameraView().preferredColorScheme(.dark)
}
