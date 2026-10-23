import SwiftUI

/// The dotted world map behind the Connect screen: a faint texture in the accent colour.
/// (scripts/make-world-map.sh builds it.)
struct WorldMapView: View {
    /// The map image's width / height: 360° of longitude over 142° of latitude.
    static let aspectRatio: CGFloat = 360 / 142

    var body: some View {
        Image("WorldMap", bundle: .keylineResources)
            .resizable()
            .renderingMode(.template)
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .foregroundColor(Theme.accent.opacity(0.11))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
