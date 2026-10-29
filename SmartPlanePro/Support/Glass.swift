import SwiftUI

enum Theme {
    /// TobyRich-style fresh green.
    static let accent = Color(red: 0.33, green: 0.86, blue: 0.52)
    static let danger = Color(red: 1.0, green: 0.26, blue: 0.28)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.2)
    static let sky = [Color(red: 0.05, green: 0.16, blue: 0.38), Color(red: 0.22, green: 0.52, blue: 0.86), Color(red: 0.62, green: 0.82, blue: 0.98)]
    static let ground = [Color(red: 0.36, green: 0.62, blue: 0.24), Color(red: 0.12, green: 0.30, blue: 0.12), Color(red: 0.04, green: 0.12, blue: 0.06)]

    static func batteryColor(_ percent: Int?) -> Color {
        guard let percent else { return .secondary }
        switch percent {
        case ..<15: return danger
        case ..<35: return warning
        default: return accent
        }
    }
}

// MARK: - Liquid Glass with graceful fallback (iOS 18 → material)

extension View {
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 26, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self.glassEffect(GlassFactory.make(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background(tint.map { $0.opacity(0.25) } ?? .clear, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
        }
    }

    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(GlassFactory.make(tint: tint, interactive: interactive), in: Capsule())
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .background(tint.map { $0.opacity(0.25) } ?? .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
        }
    }

    @ViewBuilder
    func glassCircle(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(GlassFactory.make(tint: tint, interactive: interactive), in: Circle())
        } else {
            self
                .background(.ultraThinMaterial, in: Circle())
                .background(tint.map { $0.opacity(0.3) } ?? .clear, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
        }
    }

    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }

    /// Card used across list-like screens.
    func card(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: 24)
    }
}

@available(iOS 26.0, *)
enum GlassFactory {
    static func make(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.55)) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// Groups glass shapes so they blend / morph together on iOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Animated aurora background for non-cockpit screens.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let base = scheme == .dark ? Color(red: 0.02, green: 0.05, blue: 0.09) : Color(red: 0.93, green: 0.96, blue: 0.98)
                canvas.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
                let blobs: [(Color, Double, Double, Double)] = [
                    (Theme.accent, 0.25, 0.2, 0.11),
                    (Color(red: 0.2, green: 0.5, blue: 1.0), 0.8, 0.35, 0.07),
                    (Color(red: 0.0, green: 0.8, blue: 0.8), 0.45, 0.85, 0.09),
                ]
                for (index, blob) in blobs.enumerated() {
                    let phase = t * blob.3 + Double(index) * 2.1
                    let center = CGPoint(
                        x: size.width * (blob.1 + 0.12 * sin(phase)),
                        y: size.height * (blob.2 + 0.08 * cos(phase * 1.3))
                    )
                    let radius = max(size.width, size.height) * 0.45
                    canvas.fill(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                        with: .radialGradient(
                            Gradient(colors: [blob.0.opacity(scheme == .dark ? 0.35 : 0.28), .clear]),
                            center: center, startRadius: 0, endRadius: radius
                        )
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct SignalBars: View {
    let rssi: Int?
    var body: some View {
        let bars = rssi?.rssiBars ?? 0
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < bars ? Color.primary : Color.primary.opacity(0.2))
                    .frame(width: 4, height: CGFloat(5 + index * 3))
            }
        }
        .accessibilityLabel("Signal \(bars) von 4")
    }
}

struct Chip: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}
