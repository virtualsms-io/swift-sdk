import VirtualSMS

// Proxy flow: browse the catalog, buy GB, generate a connection string, rotate the exit IP.

func proxyFlowExample() async throws {
    let client = VirtualSMS(apiKey: "vsms_your_api_key")

    let catalog = try await client.listProxyCatalog()
    print("Pool types: \(catalog.map(\.id))")

    let purchase = try await client.buyProxy(poolType: .residential, gb: 5, countryCode: "US")
    print("Bought proxy \(purchase.proxyId): \(purchase.gbRemaining)GB remaining")

    // Pure client-side helper - no network call, no purchase. Composes a
    // ready-to-use connection string from the proxy's stored credentials.
    let endpoint = try await client.generateProxyEndpoint(
        proxyId: purchase.proxyId,
        countryCode: "US",
        session: .rotating,
        protocolName: .http,
        format: .curl
    )
    print("Connection string: \(endpoint.endpoints.first ?? "")")

    let rotated = try await client.rotateProxy(proxyId: purchase.proxyId)
    print("Rotated: \(rotated.rotated), message: \(rotated.message)")

    let test = try await client.testProxy(proxyId: purchase.proxyId, country: "US")
    print("Exit IP: \(test.exitIp ?? "?") (\(test.countryName ?? "?"))")
}
