import Foundation

// MARK: - Catalog & pricing (public, no auth required)

extension VirtualSMS {

    private struct RawService: Decodable {
        let serviceId: String?
        let code: String?
        let serviceName: String?
        let name: String?
        let icon: String?
    }
    private struct ServicesEnvelope: Decodable { let services: [RawService]? }

    /// List every SMS-verification service (Telegram, WhatsApp, etc.).
    /// `GET /api/v1/customer/services` — public, no auth.
    public func listServices() async throws -> [Service] {
        // Backend returns {services: [{service_id, service_name, ...}]} OR a
        // bare array; try the wrapped shape first, then fall back to a bare array.
        if let envelope: ServicesEnvelope = try? await send(.get, "/api/v1/customer/services", auth: false),
           let raw = envelope.services {
            return raw.map {
                Service(code: $0.serviceId ?? $0.code ?? "", name: $0.serviceName ?? $0.name ?? "", icon: $0.icon)
            }
        }
        let raw: [RawService] = try await send(.get, "/api/v1/customer/services", auth: false)
        return raw.map {
            Service(code: $0.serviceId ?? $0.code ?? "", name: $0.serviceName ?? $0.name ?? "", icon: $0.icon)
        }
    }

    private struct RawCountry: Decodable {
        let countryId: String?
        let iso: String?
        let countryName: String?
        let name: String?
        let flag: String?
    }
    private struct CountriesEnvelope: Decodable { let countries: [RawCountry]? }

    /// List every available country. `GET /api/v1/customer/countries` — public, no auth.
    public func listCountries() async throws -> [Country] {
        if let envelope: CountriesEnvelope = try? await send(.get, "/api/v1/customer/countries", auth: false),
           let raw = envelope.countries {
            return raw.map {
                Country(iso: $0.countryId ?? $0.iso ?? "", name: $0.countryName ?? $0.name ?? "", flag: $0.flag)
            }
        }
        let raw: [RawCountry] = try await send(.get, "/api/v1/customer/countries", auth: false)
        return raw.map {
            Country(iso: $0.countryId ?? $0.iso ?? "", name: $0.countryName ?? $0.name ?? "", flag: $0.flag)
        }
    }

    private struct RawPrice: Decodable {
        let price: Double?
        let priceUsd: Double?
        let currency: String?
    }

    private struct RawCatalogCountry: Decodable {
        let id: String?
        let iso: String?
        let country: String?
        let name: String?
        let countryName: String?
        let price: Double?
        let ourPrice: Double?
        let priceUsd: Double?
        let count: Int?
    }
    private struct CatalogCountriesEnvelope: Decodable { let countries: [RawCatalogCountry]? }

    /// Real per-country stock for a service. `GET /api/v1/catalog/countries?service=` — public.
    /// This is the ONLY source of truth for stock; `/api/v1/price` never reports it.
    public func getCatalogCountries(service: String) async throws -> [CatalogCountry] {
        let raw: [RawCatalogCountry]
        if let envelope: CatalogCountriesEnvelope = try? await send(
            .get, "/api/v1/catalog/countries", query: ["service": service], auth: false
        ), let countries = envelope.countries {
            raw = countries
        } else {
            raw = try await send(.get, "/api/v1/catalog/countries", query: ["service": service], auth: false)
        }
        return raw.map {
            CatalogCountry(
                iso: $0.id ?? $0.iso ?? $0.country ?? "",
                name: $0.name ?? $0.countryName ?? "",
                priceUsd: $0.price ?? $0.ourPrice ?? $0.priceUsd ?? 0,
                count: $0.count ?? 0
            )
        }
    }

    /// Check price + REAL stock for a service+country combo.
    ///
    /// Two-call composite, matching the reference client exactly:
    /// `GET /api/v1/price` alone never returns availability, so this always
    /// cross-references `GET /api/v1/catalog/countries` and treats
    /// `count > 0` as in-stock. Never reports `available: true` off `/price`
    /// alone (fail-closed).
    public func getPrice(service: String, country: String) async throws -> Price {
        let raw: RawPrice = try await send(
            .get, "/api/v1/price", query: ["service": service, "country": country], auth: false
        )
        let catalog = try await getCatalogCountries(service: service)
        let available = catalog.first { $0.iso.caseInsensitiveCompare(country) == .orderedSame }
            .map { $0.count > 0 } ?? false
        return Price(
            priceUsd: raw.price ?? raw.priceUsd ?? 0,
            currency: raw.currency ?? "USD",
            available: available
        )
    }

    /// Carrier + line-type lookup for an arbitrary E.164 number.
    /// `GET /api/v1/tools/number-check?number=` — public, no auth.
    public func checkNumber(_ number: String) async throws -> NumberCheckResult {
        try await send(.get, "/api/v1/tools/number-check", query: ["number": number], auth: false)
    }
}
