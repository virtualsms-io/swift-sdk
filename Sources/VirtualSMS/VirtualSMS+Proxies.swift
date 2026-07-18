import Foundation

// MARK: - Proxies (10 methods)

extension VirtualSMS {

    // Fixed gateway ports. Rotating vs. sticky is encoded entirely in the
    // username's sessid/sessttl params, NOT by port selection.
    static let proxyHttpPort = 823
    static let proxySocks5Port = 824

    /// List pool types, countries, price/GB. `GET /api/v1/proxies/catalog` — public, ~10min cache.
    public func listProxyCatalog() async throws -> [ProxyCatalogPoolType] {
        struct Envelope: Decodable { let poolTypes: [ProxyCatalogPoolType]? }
        if let envelope: Envelope = try? await send(.get, "/api/v1/proxies/catalog", auth: false),
           let poolTypes = envelope.poolTypes {
            return poolTypes
        }
        return try await send(.get, "/api/v1/proxies/catalog", auth: false)
    }

    /// List owned proxies with credentials. `GET /api/v1/proxies` — auth required.
    public func listProxies() async throws -> [ProxyListItem] {
        try await send(.get, "/api/v1/proxies")
    }

    /// Purchase proxy traffic (GB) for a pool type.
    /// `POST /api/v1/proxies {pool_type, gb, country_code?, idempotency_key?}` — auth required.
    public func buyProxy(
        poolType: ProxyPoolType,
        gb: Double,
        countryCode: String? = nil,
        idempotencyKey: String? = nil
    ) async throws -> ProxyPurchaseResult {
        try await send(.post, "/api/v1/proxies", jsonBody: [
            "pool_type": poolType.rawValue,
            "gb": gb,
            "country_code": countryCode,
            "idempotency_key": idempotencyKey,
        ])
    }

    /// Get a fresh exit IP for an existing proxy.
    /// `POST /api/v1/proxies/{id}/rotate {port?}` — auth required.
    public func rotateProxy(proxyId: String, port: Int? = nil) async throws -> ProxyRotateResult {
        let body: [String: Any?] = ["port": port]
        return try await send(.post, "/api/v1/proxies/\(proxyId)/rotate", jsonBody: body)
    }

    /// Cached GB used/remaining (refreshed ~5min, no upstream call).
    /// `GET /api/v1/proxies/{id}/usage` — auth required.
    public func getProxyUsage(proxyId: String) async throws -> ProxyUsage {
        try await send(.get, "/api/v1/proxies/\(proxyId)/usage")
    }

    /// Per-day GB/requests series, 7d or 30d.
    /// `GET /api/v1/proxies/{id}/usage-history?range=` — auth required.
    public func getProxyUsageHistory(proxyId: String, range: String = "7d") async throws -> ProxyUsageHistoryResult {
        try await send(.get, "/api/v1/proxies/\(proxyId)/usage-history", query: ["range": range])
    }

    /// Persist default geo-targeting on a proxy sub-user.
    /// `POST /api/v1/proxies/{id}/targeting {country_code, cities?, asns?}` — auth required.
    /// Country-only is free; cities/asns bill 2x GB on non-premium pools
    /// (free on `residential_premium`) — `premium2x` on the result tells you which.
    public func setProxyTargeting(
        proxyId: String,
        countryCode: String,
        cities: [String]? = nil,
        asns: [Int]? = nil
    ) async throws -> ProxyTargetingResult {
        try await send(.post, "/api/v1/proxies/\(proxyId)/targeting", jsonBody: [
            "country_code": countryCode,
            "cities": cities,
            "asns": asns,
        ])
    }

    /// Dial out through the proxy, report exit IP/country/city/ISP/latency.
    /// `POST /api/v1/proxies/{id}/test {country, session?, protocol?}` — auth required.
    /// Rate-limited to roughly 1 call per 20s per proxy.
    public func testProxy(
        proxyId: String,
        country: String,
        session: ProxySession? = nil,
        protocolName: String? = nil
    ) async throws -> ProxyTestResult {
        try await send(.post, "/api/v1/proxies/\(proxyId)/test", jsonBody: [
            "country": country,
            "session": session?.rawValue,
            "protocol": protocolName,
        ])
    }

    /// Discover valid cities/states/asns/zips for a pool_type+country.
    /// `GET /api/v1/proxies/locations?pool_type=&country=&kind=` — public, no auth, 6h cache.
    /// NOT available for `residentialPremium`.
    public func listProxyLocations(
        poolType: ProxyPoolType,
        country: String,
        kind: String
    ) async throws -> [ProxyLocationItem] {
        struct Envelope: Decodable { let items: [ProxyLocationItem]? }
        let query: [String: String?] = ["pool_type": poolType.rawValue, "country": country, "kind": kind]
        if let envelope: Envelope = try? await send(.get, "/api/v1/proxies/locations", query: query, auth: false),
           let items = envelope.items {
            return items
        }
        return try await send(.get, "/api/v1/proxies/locations", query: query, auth: false)
    }

    /// Compose a ready-to-use connection string. NO backend call, no
    /// purchase — pure function over `listProxies()` output. Every SDK
    /// ports `buildProxyUsername`/`buildProxyEndpointString` byte-identical
    /// to the frontend's `ProxyEndpointGenerator.tsx` logic (shared
    /// client-side contract, not a backend call — drift here silently
    /// breaks connection strings).
    public func generateProxyEndpoint(
        proxyId: String,
        countryCode: String,
        targetBy: ProxyTargetBy = .country,
        locationCode: String? = nil,
        session: ProxySession = .rotating,
        stickyTtlMinutes: Int = 10,
        count: Int = 1,
        protocolName: ProxyProtocol = .http,
        format: ProxyEndpointFormat = .hostPortUserPass
    ) async throws -> ProxyEndpointResult {
        _ = try requireApiKey()
        let proxies = try await listProxies()
        guard let proxy = proxies.first(where: { $0.proxyId == proxyId }) else {
            throw VirtualSMSError.notFound("proxy \(proxyId) does not exist on this account")
        }

        let clampedCount = max(1, min(100, count))
        let port = protocolName == .socks5 ? Self.proxySocks5Port : Self.proxyHttpPort
        let trimmedLocation = (locationCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let premium2x = targetBy != .country && !trimmedLocation.isEmpty && proxy.poolType != ProxyPoolType.residentialPremium.rawValue

        func buildUsername(stickyIndex: Int? = nil) -> String {
            var username = "\(proxy.proxyLogin)__cr.\(countryCode.lowercased())"
            if !trimmedLocation.isEmpty && targetBy != .country {
                switch targetBy {
                case .state: username += ";state.\(trimmedLocation.lowercased())"
                case .city: username += ";city.\(trimmedLocation.lowercased())"
                case .zip: username += ";zip.\(trimmedLocation)"
                case .asn: username += ";asn.\(trimmedLocation)"
                case .country: break
                }
            }
            if let stickyIndex {
                username += ";sessid.s\(stickyIndex);sessttl.\(stickyTtlMinutes)"
            }
            return username
        }

        func buildEndpointString(username: String) -> String {
            switch format {
            case .hostPortUserPass:
                return "\(proxy.proxyHost):\(port):\(username):\(proxy.proxyPassword)"
            case .userPassAtHostPort:
                return "\(username):\(proxy.proxyPassword)@\(proxy.proxyHost):\(port)"
            case .curl:
                let scheme = protocolName == .socks5 ? "socks5h" : "http"
                return "curl -x \"\(scheme)://\(username):\(proxy.proxyPassword)@\(proxy.proxyHost):\(port)\" https://api.ipify.org"
            }
        }

        var endpoints: [String] = []
        if session == .rotating {
            let endpoint = buildEndpointString(username: buildUsername())
            endpoints = Array(repeating: endpoint, count: clampedCount)
        } else {
            endpoints = (1...clampedCount).map { buildEndpointString(username: buildUsername(stickyIndex: $0)) }
        }

        return ProxyEndpointResult(
            proxyId: proxy.proxyId,
            poolType: proxy.poolType,
            host: proxy.proxyHost,
            port: port,
            protocolName: protocolName.rawValue,
            session: session.rawValue,
            stickyTtlMinutes: session == .sticky ? stickyTtlMinutes : nil,
            countryCode: countryCode,
            targetBy: targetBy.rawValue,
            locationCode: locationCode,
            premium2x: premium2x,
            endpoints: endpoints
        )
    }
}
