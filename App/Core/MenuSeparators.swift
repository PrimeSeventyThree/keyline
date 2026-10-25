import AppKit

extension NSMenu {
    /// Removes separators at the start or end of each submenu and repeated ones, which SwiftUI
    /// leaves behind when menu groups are replaced with nothing.
    func removeRedundantSeparators() {
        for submenu in items.compactMap(\.submenu) {
            var previousWasSeparator = true // drops leading separators
            for item in submenu.items {
                if item.isSeparatorItem, previousWasSeparator {
                    submenu.removeItem(item)
                } else {
                    previousWasSeparator = item.isSeparatorItem
                }
            }
            while let last = submenu.items.last, last.isSeparatorItem { submenu.removeItem(last) }
        }
    }
}
