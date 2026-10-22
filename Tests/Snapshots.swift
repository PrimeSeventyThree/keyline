import SwiftUI
import XCTest

/// Renders views to PNG files for design review. Skipped unless KEYLINE_SNAPSHOT_DIR is
/// set; scripts/snapshots.sh sets it.
@MainActor
final class Snapshots: XCTestCase {
    private var outputDirectory: URL!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["KEYLINE_SNAPSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("Set KEYLINE_SNAPSHOT_DIR to render snapshots")
        }
        outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    func testFlagContactSheet() throws {
        let codes = flagCodes()
        XCTAssertGreaterThan(codes.count, 240)
        let rows = stride(from: 0, to: codes.count, by: 18).map { Array(codes[$0..<min($0 + 18, codes.count)]) }
        // ImageRenderer doesn't lay out lazy grids, so build plain rows.
        let sheet = VStack(alignment: .leading, spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { code in
                        VStack(spacing: 2) {
                            Image(Country(code: code)!.flagAssetName, bundle: .keylineResources)
                                .resizable()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                            Text(code).font(.system(size: 10, design: .monospaced)).foregroundColor(.white)
                        }
                        .frame(width: 64)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.07, green: 0.13, blue: 0.12))
        try render(sheet, named: "flags")
    }

    // MARK: - Helpers

    /// Region codes macOS knows that have a flag in the compiled bundle. (The test process
    /// can't read the repo when it lives on an external volume, so ask the bundle.)
    private func flagCodes() -> [String] {
        Locale.Region.isoRegions.map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
            .filter { Bundle.keylineResources.image(forResource: "Flags/\($0.lowercased())") != nil }
            .sorted()
    }

    func render<V: View>(_ view: V, named name: String, scale: CGFloat = 2) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.nsImage, "rendering \(name) failed")
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }
}
