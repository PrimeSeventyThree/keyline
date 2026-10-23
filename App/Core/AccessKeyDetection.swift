import Foundation

/// Recognises access keys in text from the clipboard or a link.
enum AccessKeyDetection {
    /// `text` trimmed, if it looks like an access key (ss:// or ssconf://). Whether it is
    /// valid is checked when adding.
    static func candidate(in text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.contains("\n") else { return nil }
        let lowercased = trimmed.lowercased()
        return lowercased.hasPrefix("ss://") || lowercased.hasPrefix("ssconf://") ? trimmed : nil
    }
}

/// Offers an access key copied to the clipboard once: remembers the clipboard's change
/// count, so the same copy isn't offered every time Keyline comes to the front.
@MainActor
final class ClipboardWatcher {
    private var lastChangeCount: Int?

    /// A new access key on the clipboard that hasn't been added yet, or nil.
    func newAccessKey(changeCount: Int, text: String?, isAlreadyAdded: (String) -> Bool) -> String? {
        guard changeCount != lastChangeCount else { return nil }
        lastChangeCount = changeCount
        guard let key = AccessKeyDetection.candidate(in: text), !isAlreadyAdded(key) else { return nil }
        return key
    }
}
