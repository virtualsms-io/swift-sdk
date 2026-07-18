import Foundation

// MARK: - Rentals (9 in-scope methods)
//
// Two tiers, both refund-identical (full refund within 20 min of purchase,
// before first SMS): `.fullAccess` (local SIM inventory, any service) and
// `.platform` (our global supplier network, one service per number, 24/72/168h
// durations only). Never name the supplier in code/docs — "our global
// supplier network" / "platform tier" only.

extension VirtualSMS {

    /// Raw Full-Access pricing tiers (catalog dump, not authoritative for
    /// what's purchasable today — use `rentalsAvailable` for that).
    /// `GET /api/v1/rentals/pricing` — public.
    public func rentalsPricing() async throws -> [RentalPricingTier] {
        try await send(.get, "/api/v1/rentals/pricing", auth: false)
    }

    /// List country availability + pricing per tier.
    /// `GET /api/v1/rentals/available?country=&service=&type=&provider=network(if tier=.platform)` — public.
    public func rentalsAvailable(
        country: String? = nil,
        service: String? = nil,
        type: String? = nil,
        tier: RentalTier = .fullAccess
    ) async throws -> RentalAvailabilityResult {
        try await send(.get, "/api/v1/rentals/available", query: [
            "country": country,
            "service": service,
            "type": type,
            "provider": tier == .platform ? "network" : nil,
        ], auth: false)
    }

    private struct RawRentalCatalogService: Decodable {
        let serviceId: String?
        let serviceName: String?
        let physicalCount: Int?
        let ourPrice: Double?
        let basePrice: Double?
        let popular: Bool?
        let iconUrl: String?
        // `providerCode` (or similar internal supplier field) is deliberately
        // NOT decoded here — explicit field allowlist, never forwarded.
    }

    /// List platform-tier services available in a country w/ stock + retail price.
    /// `GET /api/v1/rentals/services?country_code=&duration=` — public.
    /// Explicit field allowlist: never forwards an internal supplier-code field.
    public func rentalsServices(countryCode: String, durationHours: Int = 24) async throws -> [RentalCatalogService] {
        let raw: [RawRentalCatalogService] = try await send(.get, "/api/v1/rentals/services", query: [
            "country_code": countryCode,
            "duration": String(durationHours),
        ], auth: false)
        return raw.map {
            RentalCatalogService(
                serviceId: $0.serviceId ?? "",
                serviceName: $0.serviceName ?? "",
                physicalCount: $0.physicalCount ?? 0,
                ourPrice: $0.ourPrice,
                basePrice: $0.basePrice,
                popular: $0.popular ?? false,
                iconUrl: $0.iconUrl
            )
        }
    }

    /// Get catalog price for a (service, country, duration) platform-tier combo.
    /// `GET /api/v1/rentals/price?service=&country_code=&duration=` — public.
    public func rentalsPrice(service: String, countryCode: String, durationHours: Int) async throws -> RentalPriceResult {
        try await send(.get, "/api/v1/rentals/price", query: [
            "service": service,
            "country_code": countryCode,
            "duration": String(durationHours),
        ], auth: false)
    }

    /// Create a rental (either tier). Auth required.
    ///
    /// - `.fullAccess` -> `POST /api/v1/rentals {country, rental_type, duration_hours, service?, auto_renew?}`
    /// - `.platform` -> resolves `countryCode` (ISO-2) to the internal numeric
    ///   platform ID via `PlatformTierCountryIDs`, then
    ///   `POST /api/v1/rentals/provider {service, country: numericID, duration_hours, provider: "network"}`.
    ///   Throws `VirtualSMSError.unavailable` if the country has no mapped ID.
    public func createRental(
        tier: RentalTier,
        country: String,
        durationHours: Int,
        service: String? = nil,
        autoRenew: Bool = false
    ) async throws -> CreateRentalResult {
        switch tier {
        case .fullAccess:
            return try await send(.post, "/api/v1/rentals", jsonBody: [
                "country": country,
                "rental_type": service != nil ? "service" : "full",
                "duration_hours": durationHours,
                "service": service,
                "auto_renew": autoRenew,
            ])
        case .platform:
            guard let service else {
                throw VirtualSMSError.apiError("service is required for platform-tier rentals")
            }
            guard let countryID = PlatformTierCountryIDs.map[country.uppercased()] else {
                throw VirtualSMSError.unavailable(
                    "Platform-tier rentals are not available for country_code \"\(country)\". " +
                    "Use rentalsAvailable(tier: .platform) to see supported countries."
                )
            }
            struct RawPlatformRentalResult: Decodable {
                let success: Bool?
                let rentalId: String?
                let phoneNumber: String?
                let expiresAt: String?
                let retailCost: Double?
                let currency: String?
            }
            let raw: RawPlatformRentalResult = try await send(.post, "/api/v1/rentals/provider", jsonBody: [
                "service": service,
                "country": countryID,
                "duration_hours": durationHours,
                "provider": "network",
            ])
            return CreateRentalResult(
                success: raw.success ?? true,
                rentalId: raw.rentalId ?? "",
                phoneNumber: raw.phoneNumber ?? "",
                rentalType: nil,
                service: service,
                duration: nil,
                price: nil,
                startedAt: nil,
                expiresAt: raw.expiresAt ?? "",
                autoRenew: nil,
                status: "active",
                retailCost: raw.retailCost,
                currency: raw.currency
            )
        }
    }

    /// List rentals, optional status filter (server default is "active").
    /// `GET /api/v1/rentals?status=` — auth required.
    public func listRentals(status: String? = nil) async throws -> [Rental] {
        try await send(.get, "/api/v1/rentals", query: ["status": status])
    }

    /// Get one rental by id. CLIENT-SIDE — no dedicated GET-by-id backend
    /// route exists; calls `listRentals(status: "all")` and finds by id.
    public func getRental(rentalId: String) async throws -> Rental? {
        let all = try await listRentals(status: "all")
        return all.first { $0.id == rentalId }
    }

    /// Extend an active rental, charged at current catalog price.
    /// `POST /api/v1/rentals/{id}/extend {duration_hours}` — auth required.
    public func extendRental(rentalId: String, durationHours: Int) async throws -> RentalActionResult {
        try await send(.post, "/api/v1/rentals/\(rentalId)/extend", jsonBody: ["duration_hours": durationHours])
    }

    /// Full refund — only eligible within 20 minutes of purchase and before
    /// the first SMS, either tier. `POST /api/v1/rentals/{id}/cancel` — auth required.
    public func cancelRental(rentalId: String) async throws -> RentalActionResult {
        try await send(.post, "/api/v1/rentals/\(rentalId)/cancel")
    }

    // NOTE: `release_rental` (early release with partial refund) is
    // deliberately NOT implemented — gated behind VIRTUALSMS_ENABLE_RELEASE
    // on the MCP surface pending a pricing decision (VSMS-486). Out of scope
    // for SDK v2.0.0 per spec appendix.
}
