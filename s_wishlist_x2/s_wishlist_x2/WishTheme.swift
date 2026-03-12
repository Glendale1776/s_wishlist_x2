import SwiftUI

enum WishTheme {
    static let background = Color(red: 0.917, green: 0.957, blue: 1.0)
    static let headerBlue = Color(red: 0.086, green: 0.247, blue: 0.624)
    static let accentBlue = Color(red: 0.149, green: 0.388, blue: 0.922)
    static let accentSky = Color(red: 0.055, green: 0.647, blue: 0.914)
    static let accentRose = Color(red: 0.925, green: 0.282, blue: 0.6)
    static let accentWarm = Color(red: 0.961, green: 0.62, blue: 0.043)

    static let mainGradient = LinearGradient(
        colors: [accentBlue, accentSky],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let coolGradient = LinearGradient(
        colors: [Color(red: 0.486, green: 0.227, blue: 0.933), accentBlue],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let warmGradient = LinearGradient(
        colors: [accentRose, accentWarm],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let heroGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.953, blue: 0.78), Color(red: 0.878, green: 0.949, blue: 0.996), Color(red: 0.988, green: 0.906, blue: 0.953)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let pageHorizontalPadding: CGFloat = 16
    static let pageVerticalPadding: CGFloat = 12
    static let contentMaxWidth: CGFloat = 760
}

enum WishButtonVariant {
    case main
    case cool
    case warm
    case neutral
}

struct WishPillButtonStyle: ButtonStyle {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .body) private var buttonFontSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body) private var buttonVerticalPadding: CGFloat = 11
    @ScaledMetric(relativeTo: .body) private var buttonHorizontalPadding: CGFloat = 18

    let variant: WishButtonVariant

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: buttonFontSize, weight: .semibold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .padding(.vertical, buttonVerticalPadding)
            .padding(.horizontal, buttonHorizontalPadding)
            .frame(minHeight: horizontalSizeClass == .regular ? 50 : 44)
            .foregroundStyle(variant == .neutral ? WishTheme.headerBlue : Color.white)
            .background(
                Group {
                    switch variant {
                    case .main:
                        WishTheme.mainGradient
                    case .cool:
                        WishTheme.coolGradient
                    case .warm:
                        WishTheme.warmGradient
                    case .neutral:
                        Color.white
                    }
                }
            )
            .overlay(
                Capsule().stroke(borderColor, lineWidth: 1)
            )
            .clipShape(Capsule())
            .shadow(color: shadowColor.opacity(0.35), radius: configuration.isPressed ? 1 : 3, x: configuration.isPressed ? 1 : 3, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    private var borderColor: Color {
        switch variant {
        case .main:
            return Color(red: 0.114, green: 0.306, blue: 0.847)
        case .cool:
            return Color(red: 0.118, green: 0.251, blue: 0.686)
        case .warm:
            return Color(red: 0.925, green: 0.282, blue: 0.6)
        case .neutral:
            return Color(red: 0.82, green: 0.83, blue: 0.86)
        }
    }

    private var shadowColor: Color {
        switch variant {
        case .main:
            return WishTheme.accentBlue
        case .cool:
            return Color(red: 0.145, green: 0.388, blue: 0.922)
        case .warm:
            return WishTheme.accentRose
        case .neutral:
            return Color.black
        }
    }
}

extension View {
    func wishCardStyle() -> some View {
        self
            .padding(18)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(red: 0.88, green: 0.89, blue: 0.91), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    func wishPageLayout(maxWidth: CGFloat = WishTheme.contentMaxWidth) -> some View {
        self
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, WishTheme.pageHorizontalPadding)
            .padding(.vertical, WishTheme.pageVerticalPadding)
    }
}
