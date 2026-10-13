import XCTest
@testable import FuelForm

final class APIClientTests: XCTestCase {
    func testDevelopmentLANAddressesAndPublicHTTPBoundary() throws {
        for host in ["localhost", "127.0.0.1", "saki.local", "10.21.138.252", "172.16.0.1", "172.31.255.254", "192.168.1.2"] {
            #if DEBUG
            XCTAssertNoThrow(try APIClient(address: "http://\(host):8000", token: "synthetic"), host)
            #else
            XCTAssertThrowsError(try APIClient(address: "http://\(host):8000", token: "synthetic"), host)
            #endif
        }
        for host in ["example.com", "8.8.8.8", "11.0.0.1", "172.15.255.255", "172.32.0.1", "192.169.1.1", "10.0.0.256", "10.0.1", "0.0.0.0", "[::1]"] {
            XCTAssertThrowsError(try APIClient(address: "http://\(host):8000", token: "synthetic"), host)
        }
        XCTAssertNoThrow(try APIClient(address: "https://example.com", token: "synthetic"))
        for address in ["http://user:secret@10.0.0.1", "http://10.0.0.1?key=value", "http://10.0.0.1#fragment", "ftp://10.0.0.1"] {
            XCTAssertThrowsError(try APIClient(address: address, token: "synthetic"))
        }
    }
}
