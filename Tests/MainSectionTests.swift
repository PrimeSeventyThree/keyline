import XCTest

/// keyline://show links, which the menu bar item uses to reopen the main window (#19).
final class MainSectionTests: XCTestCase {
    func testShowURLRoundTrips() {
        for section in MainSection.allCases {
            XCTAssertEqual(MainSection(showURL: section.showURL), section)
        }
        XCTAssertEqual(MainSection.settings.showURL.absoluteString, "keyline://show/settings")
    }

    func testShowWithoutSectionIsConnect() {
        XCTAssertEqual(MainSection(showURL: URL(string: "keyline://show")!), .connect)
        XCTAssertEqual(MainSection(showURL: URL(string: "keyline://show/")!), .connect)
    }

    func testOtherLinksAreNotShowLinks() {
        XCTAssertNil(MainSection(showURL: URL(string: "keyline://show/nowhere")!))
        XCTAssertNil(MainSection(showURL: URL(string: "keyline://other/settings")!))
        XCTAssertNil(MainSection(showURL: URL(string: "ss://Y2hhY2hhMjA@example.com:4321/")!))
    }
}
