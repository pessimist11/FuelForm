import XCTest
@testable import FuelForm

final class KeychainTests: XCTestCase {
    func testPrivateCredentialRoundTripUpdateAndRemoval() throws {
        // An isolated, synthetic item: never read or replace the user's service token.
        let account = "test-\(UUID().uuidString)"
        defer { try? ServiceKeychain.save("", account: account) }
        XCTAssertEqual(try ServiceKeychain.read(account: account), "")
        try ServiceKeychain.save("synthetic-test-value", account: account)
        XCTAssertEqual(try ServiceKeychain.read(account: account), "synthetic-test-value")
        try ServiceKeychain.save("updated-synthetic-value", account: account)
        XCTAssertEqual(try ServiceKeychain.read(account: account), "updated-synthetic-value")
        try ServiceKeychain.save("", account: account)
        XCTAssertEqual(try ServiceKeychain.read(account: account), "")
    }
}
