import AppKit
import XCTest

final class CountryLookupTests: XCTestCase {
    /// A small table in the bundled format: 0.0.0.0 ZZ, 1.0.0.0 AU, 1.0.1.0 CN, 8.8.8.0 US, 8.8.9.0 ZZ.
    private let lookup = CountryLookup(table: Data(hex: "00000000 5a5a 01000000 4155 01000100 434e 08080800 5553 08080900 5a5a"))

    func testFindsTheRangeContainingAnAddress() {
        XCTAssertEqual(lookup.countryCode(forIPv4: "1.0.0.0"), "AU")
        XCTAssertEqual(lookup.countryCode(forIPv4: "1.0.0.255"), "AU")
        XCTAssertEqual(lookup.countryCode(forIPv4: "1.0.1.0"), "CN")
        XCTAssertEqual(lookup.countryCode(forIPv4: "8.8.8.8"), "US")
        XCTAssertEqual(lookup.countryCode(forIPv4: "8.8.8.255"), "US")
    }

    func testUnknownRangesAndBadInput() {
        XCTAssertNil(lookup.countryCode(forIPv4: "0.1.2.3"), "ZZ means unknown")
        XCTAssertNil(lookup.countryCode(forIPv4: "8.8.9.0"))
        XCTAssertNil(lookup.countryCode(forIPv4: "255.255.255.255"))
        XCTAssertNil(lookup.countryCode(forIPv4: "not an address"))
        XCTAssertNil(lookup.countryCode(forIPv4: "2001:4860:4860::8888"), "IPv6 is not in the table yet")
        XCTAssertNil(CountryLookup(table: Data()).countryCode(forIPv4: "8.8.8.8"))
    }

    func testIPLiteralHostsSkipDNS() {
        XCTAssertEqual(lookup.countryCode(forHost: "8.8.8.8"), "US")
    }

    func testBundledTable() throws {
        let bundled = try XCTUnwrap(CountryLookup(), "GeoIP/ipv4-country.bin is missing from the bundle")
        XCTAssertEqual(bundled.countryCode(forIPv4: "8.8.8.8"), "US")
        XCTAssertNil(bundled.countryCode(forIPv4: "10.0.0.1"), "private ranges have no country")
    }

    func testBundledTableIsWellFormed() throws {
        let url = try XCTUnwrap(Bundle.keylineResources.url(forResource: "ipv4-country", withExtension: "bin"))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count % 6, 0)
        XCTAssertGreaterThan(data.count / 6, 100_000)
        var previous: UInt32?
        for offset in stride(from: 0, to: data.count, by: 6) {
            let start = data[offset..<offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            if let previous { XCTAssertGreaterThan(start, previous, "records must be sorted"); if start <= previous { break } }
            previous = start
        }
    }

    func testFirstHopHosts() {
        XCTAssertEqual(CountryLookup.host(ofFirstHop: "example.com:4321"), "example.com")
        XCTAssertEqual(CountryLookup.host(ofFirstHop: "34.95.18.248:6328"), "34.95.18.248")
        XCTAssertEqual(CountryLookup.host(ofFirstHop: "[2001:db8::1]:443"), "2001:db8::1")
        XCTAssertEqual(CountryLookup.host(ofFirstHop: "example.com"), "example.com")
        XCTAssertNil(CountryLookup.host(ofFirstHop: ""))
    }
}

final class CountryTests: XCTestCase {
    func testCodesAreNormalised() {
        XCTAssertEqual(Country(code: "ca")?.code, "CA")
        XCTAssertEqual(Country(code: "ca")?.flagAssetName, "Flags/ca")
        XCTAssertNil(Country(code: "CAN"))
        XCTAssertNil(Country(code: "1A"))
    }

    func testNamesFollowTheLanguage() {
        let canada = Country(code: "CA")!
        XCTAssertEqual(canada.name(locale: Locale(identifier: "en")), "Canada")
        XCTAssertEqual(canada.name(locale: Locale(identifier: "ru")), "Канада")
    }

    /// Every country the bundled table can return needs a flag. (macOS also knows a few
    /// reserved codes such as AC or TA that never appear in IP data; those fall back to a globe.)
    func testEveryCountryInTheTableHasAFlag() throws {
        let url = try XCTUnwrap(Bundle.keylineResources.url(forResource: "ipv4-country", withExtension: "bin"))
        let data = try Data(contentsOf: url)
        let codes = Set(stride(from: 0, to: data.count, by: 6).map {
            String(decoding: data[$0 + 4..<$0 + 6], as: UTF8.self)
        }).subtracting(["ZZ"])
        XCTAssertGreaterThan(codes.count, 200)

        let missing = codes.sorted()
            .compactMap(Country.init(code:))
            .filter { Bundle.keylineResources.image(forResource: $0.flagAssetName) == nil }
            .map(\.code)
        XCTAssertEqual(missing, [], "countries without a flag asset")
    }
}

@MainActor
final class ServerCountryTests: XCTestCase {
    private struct FakeResolver: CountryResolving {
        let codes: [String: String]
        func countryCode(forHost host: String) -> String? { codes[host] }
    }

    private func makeRepository(_ codes: [String: String], storage: InMemoryServerListStorage = .init()) -> ServerRepository {
        ServerRepository(storage: storage, secrets: InMemorySecretStore(), configService: FakeConfigService(),
                         countryResolver: FakeResolver(codes: codes))
    }

    func testDetectsTheCountryWhenAdded() async throws {
        let repository = makeRepository(["example.com": "CA"])
        let server = try await repository.add(accessKey: testStaticKey)
        await repository.refreshCountry(forServer: server.id)
        XCTAssertEqual(repository.server(withID: server.id)?.detectedCountryCode, "CA")
        XCTAssertEqual(repository.server(withID: server.id)?.country?.code, "CA")
    }

    func testOverrideWinsAndCanBeCleared() async throws {
        let repository = makeRepository(["example.com": "CA"])
        let server = try await repository.add(accessKey: testStaticKey)
        await repository.refreshCountry(forServer: server.id)

        repository.setCountryOverride(id: server.id, countryCode: "us")
        XCTAssertEqual(repository.server(withID: server.id)?.country?.code, "US")
        repository.setCountryOverride(id: server.id, countryCode: nil)
        XCTAssertEqual(repository.server(withID: server.id)?.country?.code, "CA")
    }

    func testUnknownAddressesHaveNoCountry() async throws {
        let repository = makeRepository([:])
        let server = try await repository.add(accessKey: "ssconf://config.example.com/key")
        await repository.refreshCountry(forServer: server.id)
        XCTAssertNil(repository.server(withID: server.id)?.country, "dynamic servers have no address until they connect")
    }

    func testListsSavedBeforeCountriesStillLoad() throws {
        let json = #"{"version":1,"servers":[{"id":"1","name":"Old","kind":"static","address":"example.com:4321"}]}"#
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("servers.json")
        try Data(json.utf8).write(to: file)

        let servers = try FileServerListStorage(fileURL: file).load()
        XCTAssertEqual(servers.first?.name, "Old")
        XCTAssertNil(servers.first?.country)
    }
}

private extension Data {
    /// Data from hex digits; spaces are ignored.
    init(hex: String) {
        let digits = hex.filter { !$0.isWhitespace }
        self.init(stride(from: 0, to: digits.count, by: 2).map {
            let start = digits.index(digits.startIndex, offsetBy: $0)
            return UInt8(digits[start..<digits.index(start, offsetBy: 2)], radix: 16)!
        })
    }
}
