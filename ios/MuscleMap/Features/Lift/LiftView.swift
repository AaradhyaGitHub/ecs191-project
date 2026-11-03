import SwiftUI

/// Lift: create tiles, saved workouts, the active workout and set entry.
/// The first tab built for real; this is its starting point.
struct LiftView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Lift",
            systemImage: "dumbbell.fill",
            message: "Start a workout and log your sets here."
        )
    }
}

#Preview {
    LiftView().preferredColorScheme(.dark)
}
