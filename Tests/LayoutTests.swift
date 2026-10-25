import XCTest

/// The Connect cards grow with the window (#24).
final class LayoutTests: XCTestCase {
    func testCardsKeepTheirSizeAtTheMinimumWindow() {
        XCTAssertEqual(ConnectScreen.wingSize(forScreen: ConnectScreen.minimumScreenSize), ConnectScreen.minimumWingSize)
        XCTAssertEqual(ConnectScreen.wingSize(forScreen: CGSize(width: 800, height: 500)), ConnectScreen.minimumWingSize,
                       "never smaller than at the minimum size")
    }

    func testCardsGrowInProportionUpToTheCap() {
        let medium = ConnectScreen.wingSize(forScreen: CGSize(width: 1224, height: 864)) // 1.2×
        XCTAssertEqual(medium, CGSize(width: 300, height: 336))
        XCTAssertEqual(ConnectScreen.wingSize(forScreen: CGSize(width: 3000, height: 2000)), CGSize(width: 340, height: 381))
    }

    func testTheShorterSideLimitsGrowth() {
        // A wide but short window mustn't make the cards taller than the screen allows.
        XCTAssertEqual(ConnectScreen.wingSize(forScreen: CGSize(width: 2400, height: 720)), ConnectScreen.minimumWingSize)
    }
}
