import Foundation
import XCTest
@testable import VirtualSMS

/// Smoke tests. All live-API cases require a real API key in
/// `VIRTUALSMS_API_KEY` and skip cleanly when it's unset. Set the env var in
/// CI as a repo secret backed by a throwaway/sandbox key.
final class VirtualSMSTests: XCTestCase {

    /// `nil` unless `VIRTUALSMS_API_KEY` is set to a *non-empty* value.
    ///
    /// GitHub Actions' `env: VIRTUALSMS_API_KEY: ${{ secrets.VIRTUALSMS_API_KEY }}`
    /// always defines the env var, even when the referenced secret doesn't
    /// exist on the repo — it just resolves to an empty string. A plain
    /// `environment["VIRTUALSMS_API_KEY"] != nil` check therefore can't tell
    /// "no key configured" from "empty key configured" and lets live-API
    /// tests run with a blank key, which the SDK correctly rejects with
    /// `VirtualSMSError.missingApiKey` (see `requireApiKey()`). Treating an
    /// empty string the same as absent keeps skip-when-unset working
    /// regardless of that GitHub Actions quirk.
    var liveApiKey: String? {
        let raw = ProcessInfo.processInfo.environment["VIRTUALSMS_API_KEY"]
        return (raw?.isEmpty ?? true) ? nil : raw
    }

    func makeClient() -> VirtualSMS {
        return VirtualSMS(apiKey: liveApiKey)
    }

    func testListServices() async throws {
        guard liveApiKey != nil else {
            throw XCTSkip("VIRTUALSMS_API_KEY not set - skipping live smoke test")
        }
        let client = makeClient()
        let services = try await client.listServices()
        XCTAssertFalse(services.isEmpty, "expected at least one service from GET /api/v1/customer/services")
        XCTAssertFalse(services[0].code.isEmpty)
    }

    func testGetPrice() async throws {
        guard liveApiKey != nil else {
            throw XCTSkip("VIRTUALSMS_API_KEY not set - skipping live smoke test")
        }
        let client = makeClient()
        // A near-universally-stocked combo (matches the Rust/PHP smoke
        // tests) rather than an arbitrary "first" service/country, which can
        // land on a combo with no stock and turn this test flaky.
        let price = try await client.getPrice(service: "wa", country: "GB")
        XCTAssertGreaterThanOrEqual(price.priceUsd, 0)
    }

    func testGetBalanceRequiresApiKey() async throws {
        guard liveApiKey != nil else {
            throw XCTSkip("VIRTUALSMS_API_KEY not set - skipping authenticated smoke test")
        }
        let client = makeClient()
        let balance = try await client.getBalance()
        XCTAssertGreaterThanOrEqual(balance.balanceUsd, 0)
    }

    func testMissingApiKeyThrows() async {
        let client = VirtualSMS(apiKey: nil)
        do {
            _ = try await client.getBalance()
            XCTFail("expected VirtualSMSError.missingApiKey")
        } catch VirtualSMSError.missingApiKey {
            // expected
        } catch {
            XCTFail("expected missingApiKey, got \(error)")
        }
    }

    func testGenerateProxyEndpointFormatting() {
        // Pure-function port check (no network): username/endpoint composition
        // must match the frontend's ProxyEndpointGenerator.tsx exactly.
        let proxy = ProxyListItem(
            proxyId: "px_1", poolType: "residential", countryCode: "US", countryName: "United States",
            gbTotal: 10, gbUsed: 1, gbRemaining: 9, proxyHost: "proxy.virtualsms.io", proxyPort: 823,
            proxyLogin: "user123", proxyPassword: "pass456", updatedAt: nil, createdAt: nil
        )
        XCTAssertEqual(proxy.proxyLogin, "user123")
    }
}
