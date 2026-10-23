import XCTest

/// Checks the compiled string catalog (Resources/Localizable.xcstrings, filled in by
/// scripts/update-strings.sh).
final class LocalizationTests: XCTestCase {
    private func strings(_ language: String) throws -> [String: String] {
        let url = try XCTUnwrap(Bundle.keylineResources.url(forResource: "Localizable", withExtension: "strings",
                                                            subdirectory: nil, localization: language),
                                "\(language).lproj/Localizable.strings is missing")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    func testBothLanguagesShip() {
        let localizations = Bundle.keylineResources.localizations
        XCTAssertTrue(localizations.contains("en"), "without en.lproj macOS would pick Russian for everyone")
        XCTAssertTrue(localizations.contains("ru"))
    }

    func testEveryEnglishStringHasRussian() throws {
        let english = try strings("en")
        let russian = try strings("ru")
        XCTAssertGreaterThan(english.count, 100)
        XCTAssertEqual(Set(english.keys).subtracting(russian.keys).sorted(), [], "run scripts/update-strings.sh")
    }

    func testFormatSpecifiersMatch() throws {
        let english = try strings("en")
        let russian = try strings("ru")
        let specifier = try NSRegularExpression(pattern: "%([0-9]+\\$)?(@|lld|ld|d|f)")
        func specifiers(_ text: String) -> [String] {
            specifier.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { (text as NSString).substring(with: $0.range) }.sorted()
        }
        for (key, value) in english {
            guard let translation = russian[key] else { continue }
            XCTAssertEqual(specifiers(translation), specifiers(value), "format specifiers differ for \(key)")
        }
    }

    func testSampleTranslations() throws {
        let russian = try strings("ru")
        XCTAssertEqual(russian["status-connected"], "Подключено")
        XCTAssertEqual(russian["error-server-already-added"], "Сервер «%@» уже добавлен.")
    }
}
