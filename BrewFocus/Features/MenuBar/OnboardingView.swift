import SwiftUI

struct OnboardingView: View {
    let complete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                Circle()
                    .fill(BrewFocusStyle.espresso.opacity(0.12))
                    .frame(width: 62, height: 62)
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(BrewFocusStyle.espresso)
            }

            BrewFocusHeader(
                eyebrow: "Welcome to BrewFocus",
                title: "Focus, ordered simply.",
                subtitle: "Choose a coffee based on how much freedom you need."
            )

            VStack(alignment: .leading, spacing: 13) {
                onboardingPoint(
                    icon: "hand.raised.fill",
                    title: "A safe focus guard",
                    detail: "BrewFocus hides distracting apps. It never quits them or destroys unsaved work."
                )
                onboardingPoint(
                    icon: "macwindow.on.rectangle",
                    title: "Four distinct strengths",
                    detail: "Latte keeps every app available. Cappuccino blocks selected distractions. Americano and Espresso keep only essentials."
                )
                onboardingPoint(
                    icon: "moon.fill",
                    title: "Focus stays in your control",
                    detail: "BrewFocus cannot switch macOS Focus on. Use Control Center if you also want notifications silenced."
                )
                onboardingPoint(
                    icon: "lock.shield.fill",
                    title: "Private by default",
                    detail: "Sessions and cups stay locally on this Mac."
                )
            }

            Button(action: complete) {
                Label("Choose my first coffee", systemImage: "arrow.right")
            }
            .buttonStyle(PrimaryActionButtonStyle())
        }
    }

    private func onboardingPoint(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BrewFocusStyle.espresso)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
