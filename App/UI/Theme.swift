import SwiftUI

/// Keyline's colours and type. Dark-first, with a green accent (from the reference design).
enum Theme {
    static let accent = Color(red: 0.24, green: 0.86, blue: 0.56)          // #3DDB8F
    static let accentDeep = Color(red: 0.10, green: 0.55, blue: 0.36)      // #1A8C5C
    static let warning = Color(red: 0.98, green: 0.69, blue: 0.25)
    static let danger = Color(red: 0.96, green: 0.36, blue: 0.40)
    static let latency = Color(red: 0.98, green: 0.45, blue: 0.35)
    static let upload = Color(red: 0.25, green: 0.78, blue: 0.95)

    static let backgroundTop = Color(red: 0.06, green: 0.15, blue: 0.13)
    static let backgroundBottom = Color(red: 0.03, green: 0.08, blue: 0.07)
    static let surface = Color.white.opacity(0.045)
    static let surfaceStroke = Color.white.opacity(0.08)
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.36)

    static let cornerRadius: CGFloat = 14

    static var background: some View {
        ZStack {
            LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [accent.opacity(0.10), .clear], center: .center, startRadius: 10, endRadius: 520)
        }
    }
}

/// A rounded translucent panel used for cards and lists.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.surfaceStroke, lineWidth: 1))
    }
}

/// A primary (filled accent) or secondary (outlined) button.
struct KeylineButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundColor(kind == .primary ? Color.black.opacity(0.85) : (kind == .destructive ? Theme.danger : Theme.textPrimary))
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(kind == .primary ? Theme.accent : Color.white.opacity(configuration.isPressed ? 0.12 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(kind == .primary ? .clear : Theme.surfaceStroke))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// A switch drawn in SwiftUI, so it matches the theme (and renders in snapshots).
struct KeylineToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                Spacer(minLength: 12)
                Capsule()
                    .fill(configuration.isOn ? Theme.accent : Color.white.opacity(0.16))
                    .frame(width: 38, height: 22)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).padding(2.5).shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    }
                    .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
    }
}

/// True while rendering design snapshots, where AppKit-backed controls such as text fields
/// can't be drawn and are replaced by look-alike stand-ins.
private struct SnapshotRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSnapshotRendering: Bool {
        get { self[SnapshotRenderingKey.self] }
        set { self[SnapshotRenderingKey.self] = newValue }
    }
}
