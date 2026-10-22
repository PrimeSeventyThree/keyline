import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case connect, servers, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .connect: return String(localized: "section-connect", defaultValue: "Connect")
        case .servers: return String(localized: "section-servers", defaultValue: "Servers")
        case .settings: return String(localized: "section-settings", defaultValue: "Settings")
        }
    }

    var icon: String {
        switch self {
        case .connect: return "power"
        case .servers: return "globe"
        case .settings: return "gearshape"
        }
    }
}

/// The window frame: a slim sidebar and the selected screen on the themed background.
struct MainWindow<Content: View>: View {
    @Binding var section: MainSection
    var isConnected: Bool
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(section: $section, isConnected: isConnected)
                .padding(.vertical, 18)
                .padding(.leading, 16)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}

struct Sidebar: View {
    @Binding var section: MainSection
    var isConnected: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Image(systemName: "key.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.black.opacity(0.85))
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent))
                    .shadow(color: Theme.accent.opacity(0.5), radius: 10)
            }
            .padding(.bottom, 18)
            .accessibilityHidden(true)

            ForEach(MainSection.allCases) { item in
                Button { section = item } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.icon).font(.system(size: 17, weight: .medium))
                        Text(item.title).font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(item == section ? Theme.accent : Theme.textSecondary)
                    .frame(width: 70, height: 58)
                    .background(RoundedRectangle(cornerRadius: 12).fill(item == section ? Theme.accent.opacity(0.12) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == section ? .isSelected : [])
            }
            Spacer()
            Circle()
                .fill(isConnected ? Theme.accent : Theme.textTertiary)
                .frame(width: 8, height: 8)
                .shadow(color: isConnected ? Theme.accent : .clear, radius: 5)
                .padding(.bottom, 6)
                .accessibilityLabel(Text(isConnected
                    ? String(localized: "status-connected", defaultValue: "Connected")
                    : String(localized: "status-disconnected", defaultValue: "Disconnected")))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 7)
        .frame(width: 84)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.22)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.surfaceStroke))
    }
}
