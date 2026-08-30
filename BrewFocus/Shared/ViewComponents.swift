import SwiftUI

struct BrewFocusHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String?
    let accent: Color

    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        accent: Color = BrewFocusStyle.espresso
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(accent)
            Text(title)
                .font(.title2.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    let accent: Color

    init(accent: Color = BrewFocusStyle.espresso) {
        self.accent = accent
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                accent.opacity(configuration.isPressed ? 0.78 : 1),
                in: RoundedRectangle(cornerRadius: 11)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct WarmCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }
}

extension View {
    func warmCard() -> some View {
        modifier(WarmCardModifier())
    }
}
