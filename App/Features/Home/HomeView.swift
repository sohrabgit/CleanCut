import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: Tokens.Spacing.l) {
                Spacer()
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.accent)
                VStack(spacing: Tokens.Spacing.xs) {
                    Text("Studio-quality product photos")
                        .font(.title2.bold())
                    Text("Remove the background, add a real shadow, export for every marketplace — all on your device.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding(Tokens.Spacing.l)
            .navigationTitle("CleanCut")
        }
    }
}

#Preview {
    HomeView()
}
