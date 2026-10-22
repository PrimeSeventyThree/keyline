import SwiftUI

/// What the UI shows about a server.
struct ServerSummary: Identifiable, Equatable {
    let id: String
    var name: String
    var country: Country?
    var address: String
    var isDynamic: Bool

    init(_ server: Server) {
        self.init(id: server.id, name: server.name, country: server.country,
                  address: server.address, isDynamic: server.kind == .dynamic)
    }

    init(id: String, name: String, country: Country?, address: String, isDynamic: Bool) {
        self.id = id
        self.name = name
        self.country = country
        self.address = address
        self.isDynamic = isDynamic
    }

    /// The country name, or a neutral label when it's unknown.
    var placeName: String {
        country?.name() ?? String(localized: "server-location-unknown", defaultValue: "Unknown location")
    }
}

/// A server's round flag avatar, or a globe when the country is unknown.
struct FlagAvatar: View {
    let country: Country?
    var size: CGFloat = 44
    var isSelected = false

    var body: some View {
        ZStack {
            if let country, Bundle.keylineResources.image(forResource: country.flagAssetName) != nil {
                Image(country.flagAssetName, bundle: .keylineResources)
                    .resizable()
                    .interpolation(.high)
            } else {
                Circle().fill(Color.white.opacity(0.08))
                Image(systemName: "globe")
                    .font(.system(size: size * 0.46, weight: .light))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
        .padding(isSelected ? 4 : 0)
        .overlay(Circle().stroke(Theme.accent, lineWidth: isSelected ? 2.5 : 0))
        .shadow(color: isSelected ? Theme.accent.opacity(0.45) : .clear, radius: 12)
        .accessibilityLabel(Text(country?.name() ?? String(localized: "server-location-unknown", defaultValue: "Unknown location")))
    }
}

/// A smooth line chart of recent samples, filled softly underneath.
struct Sparkline: View {
    let samples: [Double]
    var colors: [Color] = [Theme.upload, Theme.accent]

    var body: some View {
        GeometryReader { geometry in
            let points = Self.points(samples, in: geometry.size)
            ZStack {
                Self.path(points, closingTo: geometry.size.height)
                    .fill(LinearGradient(colors: [colors.last!.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                Self.path(points, closingTo: nil)
                    .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    static func points(_ samples: [Double], in size: CGSize) -> [CGPoint] {
        guard samples.count > 1 else { return [] }
        let maxValue = max(samples.max() ?? 0, 1)
        let step = size.width / CGFloat(samples.count - 1)
        let inset: CGFloat = 3
        return samples.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step,
                    y: inset + (size.height - 2 * inset) * (1 - CGFloat(value / maxValue)))
        }
    }

    /// A curve through `points`; when `closingTo` is set, closed along that baseline for filling.
    static func path(_ points: [CGPoint], closingTo baseline: CGFloat?) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for (previous, point) in zip(points, points.dropFirst()) {
                let midX = (previous.x + point.x) / 2
                path.addCurve(to: point, control1: CGPoint(x: midX, y: previous.y), control2: CGPoint(x: midX, y: point.y))
            }
            if let baseline, let last = points.last {
                path.addLine(to: CGPoint(x: last.x, y: baseline))
                path.addLine(to: CGPoint(x: first.x, y: baseline))
                path.closeSubpath()
            }
        }
    }
}

/// Formats values for the stats cards.
enum StatsFormat {
    /// "47.3 Mbps", "820 kbps": network speeds in bits per second, like most speed tests.
    static func speed(bytesPerSecond: Double) -> (value: String, unit: String) {
        let bits = bytesPerSecond * 8
        switch bits {
        case 1_000_000_000...: return (String(format: "%.1f", bits / 1_000_000_000), "Gbps")
        case 1_000_000...: return (String(format: "%.1f", bits / 1_000_000), "Mbps")
        case 1_000...: return (String(format: "%.0f", bits / 1_000), "kbps")
        default: return (String(format: "%.0f", bits), "bps")
        }
    }

    /// "00:45:29": elapsed time since connecting, hours not capped at 24.
    static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    /// "1.2 GB" for session totals.
    static func bytes(_ count: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false // "0 bytes", not "Zero KB"
        return formatter.string(fromByteCount: Int64(clamping: count))
    }
}
