import SwiftUI

/// Goals: frequency, volume, strength, balance and style goals. Placeholder for now.
struct GoalsView: View {
    var body: some View {
        PlaceholderScreen(
            title: "Goals",
            systemImage: "target",
            message: "Set frequency, volume and strength goals here."
        )
    }
}

#Preview {
    GoalsView().preferredColorScheme(.dark)
}
