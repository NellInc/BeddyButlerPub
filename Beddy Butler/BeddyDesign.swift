import AppKit
import SwiftUI

enum BeddyPalette {
    static let night = Color(red: 6 / 255, green: 17 / 255, blue: 38 / 255)
    static let nightDeep = Color(red: 3 / 255, green: 9 / 255, blue: 22 / 255)
    static let nightLifted = Color(red: 7 / 255, green: 21 / 255, blue: 44 / 255)
    static let ink = Color(red: 246 / 255, green: 249 / 255, blue: 1)
    static let muted = Color(red: 174 / 255, green: 187 / 255, blue: 208 / 255)
    static let faint = Color(red: 120 / 255, green: 137 / 255, blue: 165 / 255)
    static let blue = Color(red: 128 / 255, green: 198 / 255, blue: 1)
    static let blueBright = Color(red: 169 / 255, green: 221 / 255, blue: 1)
    static let violet = Color(red: 158 / 255, green: 169 / 255, blue: 1)
    static let warm = Color(red: 242 / 255, green: 179 / 255, blue: 117 / 255)
    static let zombie = Color(red: 166 / 255, green: 209 / 255, blue: 138 / 255)
    static let success = Color(red: 166 / 255, green: 226 / 255, blue: 190 / 255)
    static let glass = Color(red: 15 / 255, green: 31 / 255, blue: 58 / 255).opacity(0.74)
    static let glassStrong = Color(red: 14 / 255, green: 29 / 255, blue: 54 / 255).opacity(0.90)
    static let line = Color.white.opacity(0.12)
    static let lineStrong = Color.white.opacity(0.20)
}

struct WindowMaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct BeddyStars: View {
    private let positions: [(CGFloat, CGFloat, CGFloat)] = [
        (0.08, 0.12, 2.2), (0.29, 0.07, 1.4), (0.48, 0.24, 1.8),
        (0.69, 0.11, 1.5), (0.91, 0.29, 2.0), (0.17, 0.72, 1.4),
        (0.82, 0.64, 1.2), (0.38, 0.48, 1.0),
    ]

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(positions.enumerated()), id: \.offset) { _, star in
                Circle()
                    .fill(BeddyPalette.blueBright.opacity(0.72))
                    .frame(width: star.2, height: star.2)
                    .shadow(color: BeddyPalette.blue.opacity(0.9), radius: 4)
                    .position(
                        x: geometry.size.width * star.0,
                        y: geometry.size.height * star.1
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

struct BeddyBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            WindowMaterialView()

            if reduceTransparency {
                BeddyPalette.nightDeep
            } else {
                LinearGradient(
                    colors: [BeddyPalette.nightLifted, BeddyPalette.night, BeddyPalette.nightDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [
                        Color(red: 44 / 255, green: 116 / 255, blue: 197 / 255).opacity(0.30),
                        .clear,
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 560
                )

                RadialGradient(
                    colors: [
                        Color(red: 85 / 255, green: 51 / 255, blue: 146 / 255).opacity(0.16),
                        .clear,
                    ],
                    center: .leading,
                    startRadius: 10,
                    endRadius: 620
                )

                BeddyStars()
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct BeddyCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    var emphasized = false
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.16), in: Circle())
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BeddyPalette.ink)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background {
            ZStack {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(BeddyPalette.night)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(BeddyPalette.glass)
                }

                if emphasized, !reduceTransparency {
                    LinearGradient(
                        colors: [tint.opacity(0.16), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    reduceTransparency ? BeddyPalette.lineStrong : BeddyPalette.line,
                    lineWidth: 1
                )
        }
        .shadow(
            color: reduceTransparency ? .clear : .black.opacity(0.34),
            radius: emphasized ? 20 : 14,
            x: 0,
            y: emphasized ? 10 : 7
        )
        .foregroundStyle(BeddyPalette.ink)
        .accessibilityElement(children: .contain)
    }
}

private struct GlassCapsuleModifier: ViewModifier {
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint.opacity(0.24)), in: Capsule())
        } else {
            content
                .background(.thinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(BeddyPalette.line, lineWidth: 1)
                }
        }
    }
}

struct BeddyPrimaryButtonStyle: ButtonStyle {
    let glow: Color

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(BeddyPalette.nightDeep)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .frame(minHeight: 36)
            .background {
                LinearGradient(
                    colors: [Color.white, Color(red: 216 / 255, green: 234 / 255, blue: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: glow.opacity(0.26), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.42)
    }
}

struct BeddySecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(BeddyPalette.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .frame(minHeight: 34)
            .background(Color.white.opacity(configuration.isPressed ? 0.11 : 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(BeddyPalette.line, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.38)
    }
}

private struct PrimaryGlassButtonModifier: ViewModifier {
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        content.buttonStyle(BeddyPrimaryButtonStyle(glow: tint))
    }
}

extension View {
    func glassCapsule(tint: Color) -> some View {
        modifier(GlassCapsuleModifier(tint: tint))
    }

    func primaryGlassButton(tint: Color = BeddyPalette.blue) -> some View {
        modifier(PrimaryGlassButtonModifier(tint: tint))
    }
}
