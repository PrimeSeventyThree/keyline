import AppKit
import XCTest

final class MenuSeparatorsTests: XCTestCase {
    func testRemovesLeadingTrailingAndRepeatedSeparators() {
        let edit = NSMenu(title: "Edit")
        for title in ["---", "Undo", "---", "---", "Copy", "---", "---", "AutoFill", "---"] {
            edit.addItem(title == "---" ? .separator() : NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        }
        let main = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)

        main.removeRedundantSeparators()
        XCTAssertEqual(edit.items.map { $0.isSeparatorItem ? "---" : $0.title }, ["Undo", "---", "Copy", "---", "AutoFill"])
    }

    func testLeavesAMenuOfOnlySeparatorsEmpty() {
        let view = NSMenu(title: "View")
        view.addItem(.separator())
        let main = NSMenu()
        let item = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        item.submenu = view
        main.addItem(item)
        main.removeRedundantSeparators()
        XCTAssertEqual(view.items.count, 0)
    }
}
