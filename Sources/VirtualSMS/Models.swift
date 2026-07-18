import Foundation

// All response/request models for the VirtualSMS REST v1 API.
//
// Convention: Swift property names are camelCase; `VirtualSMS.decoder` is
// configured with `.convertFromSnakeCase` so JSON's snake_case keys map
// automatically (e.g. `price_usd` -> `priceUsd`). A handful of endpoints
// (services/countries/orders listing) return backend-internal field names
// (`service_id`, `country_id`, `price_charged`, ...) that get remapped to
// the canonical shape below in `VirtualSMS+Orders.swift` — those have their
// own private `Raw*` decode types instead of relying on the convention.

// MARK: - Catalog

public struct Service: Codable, Sendable, Equatable {
    public let code: String
    public let name: String
    public let icon: String?

    public init(code: String, name: String, icon: String? = nil) {
        self.code = code
        self.name = name
        self.icon = icon
    }
}

public struct Country: Codable, Sendable, Equatable {
    public let iso: String
    public let name: String
    public let flag: String?

    public init(iso: String, name: String, flag: String? = nil) {
        self.iso = iso
        self.name = name
        self.flag = flag
    }
}

/// Result of `getPrice`. NOTE: `/api/v1/price` alone never reports real
/// stock — `available` here is derived by cross-referencing
/// `/api/v1/catalog/countries` (see `VirtualSMS.getPrice`). Never trust an
/// `available` field decoded directly off the raw `/price` response.
public struct Price: Codable, Sendable, Equatable {
    public let priceUsd: Double
    public let currency: String
    public let available: Bool

    public init(priceUsd: Double, currency: String, available: Bool) {
        self.priceUsd = priceUsd
        self.currency = currency
        self.available = available
    }
}

/// Per-country catalog entry, the actual source of real stock (`count`).
public struct CatalogCountry: Codable, Sendable, Equatable {
    public let iso: String
    public let name: String
    public let priceUsd: Double
    public let count: Int
}

// MARK: - Account

public struct Balance: Codable, Sendable, Equatable {
    public let balanceUsd: Double
}

public struct Profile: Codable, Sendable, Equatable {
    public let id: String
    public let email: String
    public let telegramLinked: Bool
    public let telegramUsername: String?
    public let balanceUsd: Double
    public let totalSpentUsd: Double
    public let totalCreditsUsd: Double
    public let totalOrders: Int
    public let activeApiKeys: Int
    public let createdAt: String
}

public struct Transaction: Codable, Sendable, Equatable {
    public let id: String
    public let amount: Double
    public let type: String
    public let description: String?
    public let orderId: String?
    public let balanceBefore: Double
    public let balanceAfter: Double
    public let createdAt: String
}

public struct TransactionsPage: Codable, Sendable, Equatable {
    public let count: Int
    public let limit: Int
    public let offset: Int
    public let transactions: [Transaction]
}

/// Client-side aggregate produced by `getStats`. Not a direct API response —
/// composed locally from `getBalance()` + `listOrders()`.
public struct StatsResult: Codable, Sendable, Equatable {
    public let windowDays: Int
    public let balanceUsd: Double
    public let totalOrders: Int
    public let successfulOrders: Int
    public let successRate: Double
    public let totalSpendUsd: Double
    public let statusBreakdown: [String: Int]
    public let topServices: [KeyCount]
    public let topCountries: [KeyCount]
    public let note: String?
}

public struct KeyCount: Codable, Sendable, Equatable {
    public let key: String
    public let count: Int
}

// MARK: - Orders

public struct SmsMessage: Codable, Sendable, Equatable {
    public let content: String
    public let sender: String?
    public let receivedAt: String?
}

public struct Order: Codable, Sendable, Equatable {
    public let orderId: String
    public let phoneNumber: String
    public let service: String?
    public let country: String?
    public let price: Double?
    public let createdAt: String?
    public let expiresAt: String?
    public let status: String
    /// Legacy fields kept for backward compat with older API payloads.
    public let smsCode: String?
    public let smsText: String?
    /// Canonical SMS payload: one entry per inbound message.
    public let messages: [SmsMessage]?
    public let smsReceived: Bool?
    /// RFC3339 wallclock timestamps for when cancel/swap cooldowns clear.
    public let cancelAvailableAt: String?
    public let swapAvailableAt: String?

    public init(
        orderId: String, phoneNumber: String, service: String? = nil, country: String? = nil,
        price: Double? = nil, createdAt: String? = nil, expiresAt: String? = nil, status: String,
        smsCode: String? = nil, smsText: String? = nil, messages: [SmsMessage]? = nil,
        smsReceived: Bool? = nil, cancelAvailableAt: String? = nil, swapAvailableAt: String? = nil
    ) {
        self.orderId = orderId
        self.phoneNumber = phoneNumber
        self.service = service
        self.country = country
        self.price = price
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.status = status
        self.smsCode = smsCode
        self.smsText = smsText
        self.messages = messages
        self.smsReceived = smsReceived
        self.cancelAvailableAt = cancelAvailableAt
        self.swapAvailableAt = swapAvailableAt
    }
}

public struct CancelResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let refunded: Bool
}

public struct RetryOrderResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let orderId: String
    public let message: String
}

/// Normalized shape returned by the client-side `getSms` helper.
public struct GetSmsResult: Codable, Sendable, Equatable {
    public let status: String
    public let phoneNumber: String
    public let messages: [SmsMessage]?
    /// First 4-8 digit run found across message content / legacy sms fields.
    public let code: String?
    public let smsCode: String?
    public let smsText: String?
}

/// Result of the client-side `waitForSms` helper. On timeout, `success` is
/// false and this is *returned*, never thrown.
public struct WaitForSmsResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let orderId: String
    public let phoneNumber: String
    public let status: String?
    public let messages: [SmsMessage]?
    public let code: String?
    public let deliveryMethod: String?
    public let elapsedSeconds: Double?
    public let error: String?
}

public struct OrderHistoryFilters: Codable, Sendable, Equatable {
    public let status: String?
    public let service: String?
    public let country: String?
    public let sinceDays: Int?
}

public struct OrderHistoryResult: Codable, Sendable, Equatable {
    public let count: Int
    public let totalMatched: Int
    public let filters: OrderHistoryFilters
    public let orders: [Order]
}

public struct CancelledOrder: Codable, Sendable, Equatable {
    public let orderId: String
    public let refunded: Bool
}

public struct CancelFailure: Codable, Sendable, Equatable, Error {
    public let orderId: String
    public let error: String
}

public struct CancelAllOrdersResult: Codable, Sendable, Equatable {
    public let cancelled: Int
    public let failed: Int
    public let totalActive: Int
    public let cancelledOrders: [CancelledOrder]
    public let failures: [CancelFailure]
}

public struct ServiceMatch: Codable, Sendable, Equatable {
    public let code: String
    public let name: String
    public let matchScore: Double
}

public struct SearchServicesResult: Codable, Sendable, Equatable {
    public let query: String
    public let matches: [ServiceMatch]
    public let message: String?
    public let tip: String?
}

public struct CheapestOption: Codable, Sendable, Equatable {
    public let country: String
    public let countryName: String
    public let priceUsd: Double
    public let stock: Bool
}

public struct FindCheapestResult: Codable, Sendable, Equatable {
    public let service: String
    public let cheapestOptions: [CheapestOption]
    public let totalAvailableCountries: Int
    public let message: String?
}

// MARK: - Rentals

public struct RentalPricingTier: Codable, Sendable, Equatable {
    public let rentalType: String
    public let durationHours: Int
    public let durationLabel: String
    public let basePrice: Double
    public let countryCode: String
    public let serviceId: String
}

public struct RentalDurationPrice: Codable, Sendable, Equatable {
    public let durationHours: Int
    public let durationLabel: String
    public let price: Double
}

public struct RentalAvailabilityCountry: Codable, Sendable, Equatable {
    public let countryCode: String
    public let countryName: String
    public let flag: String?
    public let availableCount: Int
    public let pricing: [String: [RentalDurationPrice]]
    /// Platform tier (provider=network) only.
    public let serviceCount: Int?
    public let popularServices: [String]?
    public let minPricePerDay: Double?
}

public struct RentalFullAccessCountry: Codable, Sendable, Equatable {
    public let countryCode: String
    public let countryName: String
    public let flag: String?
    public let availableCount: Int
    public let pricing: [String: Double]
}

public struct RentalAvailabilityResult: Codable, Sendable, Equatable {
    public let countries: [RentalAvailabilityCountry]
    public let totalAvailable: Int
    public let fullAccessCountries: [RentalFullAccessCountry]?
    public let provider: String?
}

public struct RentalCatalogService: Codable, Sendable, Equatable {
    public let serviceId: String
    public let serviceName: String
    public let physicalCount: Int
    public let ourPrice: Double?
    public let basePrice: Double?
    public let popular: Bool
    public let iconUrl: String?
}

public struct RentalPriceResult: Codable, Sendable, Equatable {
    public let price: Double
    public let durationHours: Int
}

public struct Rental: Codable, Sendable, Equatable {
    public let id: String
    public let phoneNumber: String
    public let rentalType: String
    public let serviceId: String?
    public let durationHours: Int
    public let startedAt: String
    public let expiresAt: String
    public let price: Double
    public let autoRenew: Bool
    public let status: String
    public let smsReceived: Int
    public let smsForwarded: Int
    public let lastSmsAt: String?
    public let provider: String
}

public struct CreateRentalResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let rentalId: String
    public let phoneNumber: String
    public let rentalType: String?
    public let service: String?
    public let duration: String?
    public let price: Double?
    public let startedAt: String?
    public let expiresAt: String
    public let autoRenew: Bool?
    public let status: String?
    public let retailCost: Double?
    public let currency: String?
}

public struct RentalActionResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let rentalId: String
    public let status: String?
    public let refund: Double?
    public let newExpiresAt: String?
    public let price: Double?
    public let hoursUsed: String?
    public let message: String?
}

/// Which rental tier to purchase. `fullAccess` = local SIM inventory, any
/// service, longer durations. `platform` = sourced via our global supplier
/// network, one service per number, 24/72/168h durations only.
public enum RentalTier: String, Sendable {
    case fullAccess = "full_access"
    case platform = "platform"
}

// MARK: - Proxies

public struct ProxyCatalogCountry: Codable, Sendable, Equatable {
    public let code: String
    public let name: String
    public let available: Bool
    public let ipCount: Int
}

public struct ProxyCatalogPoolType: Codable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let pricePerGb: Double
    public let countries: [ProxyCatalogCountry]
}

public struct ProxyListItem: Codable, Sendable, Equatable {
    public let proxyId: String
    public let poolType: String
    public let countryCode: String
    public let countryName: String?
    public let gbTotal: Double
    public let gbUsed: Double
    public let gbRemaining: Double
    public let proxyHost: String
    public let proxyPort: Int
    public let proxyLogin: String
    public let proxyPassword: String
    public let updatedAt: String?
    public let createdAt: String?
}

public struct ProxyPurchaseResult: Codable, Sendable, Equatable {
    public let proxyId: String
    public let poolType: String
    public let gbAdded: Double
    public let gbRemaining: Double
    public let countryCode: String
    public let proxyLogin: String
    public let proxyPassword: String
    public let proxyHost: String
    public let proxyPort: Int
    public let proxyPortSocks: Int?
    public let price: Double
    public let balance: Double?
}

public struct ProxyRotateResult: Codable, Sendable, Equatable {
    public let rotated: Bool
    public let port: Int
    public let message: String
}

public struct ProxyUsage: Codable, Sendable, Equatable {
    public let gbUsed: Double
    public let gbRemaining: Double
    public let requests: Int
    public let updatedAt: String?
}

public struct ProxyUsageHistoryPoint: Codable, Sendable, Equatable {
    public let date: String
    public let gb: Double
    public let requests: Int
}

public struct ProxyUsageHistoryTotals: Codable, Sendable, Equatable {
    public let gb: Double
    public let requests: Int
}

public struct ProxyUsageHistoryResult: Codable, Sendable, Equatable {
    public let series: [ProxyUsageHistoryPoint]
    public let totals: ProxyUsageHistoryTotals
}

public struct ProxyTargetingResult: Codable, Sendable, Equatable {
    public let ok: Bool
    public let countryCode: String
    /// True when city/state/zip/asn targeting was requested on a
    /// non-premium pool — the sub-country refinement burns funded GB 2x
    /// faster. Free on `residential_premium`.
    public let premium2x: Bool
    // No explicit CodingKeys: `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`
    // (set in VirtualSMS.init) already turns `country_code` -> `countryCode`
    // and `premium_2x` -> `premium2x` to match these property names exactly.
    // Adding explicit snake_case CodingKeys here would double-apply and break
    // decoding, since the strategy transforms the JSON key BEFORE matching
    // against CodingKeys raw values.
}

public struct ProxyTestResult: Codable, Sendable, Equatable {
    public let ok: Bool
    public let exitIp: String?
    public let countryCode: String?
    public let countryName: String?
    public let city: String?
    public let region: String?
    public let isp: String?
    public let asn: String?
    public let latencyMs: Double?
    public let error: String?
}

public struct ProxyLocationItem: Codable, Sendable, Equatable {
    public let code: String
    public let name: String
    public let count: Int
}

public enum ProxyPoolType: String, Sendable {
    case residential
    case residentialPremium = "residential_premium"
    case mobile
    case datacenter
}

public enum ProxyTargetBy: String, Sendable {
    case country, state, city, zip, asn
}

public enum ProxySession: String, Sendable {
    case rotating, sticky
}

public enum ProxyProtocol: String, Sendable {
    case http = "HTTP"
    case socks5 = "SOCKS5"
}

public enum ProxyEndpointFormat: String, Sendable {
    case hostPortUserPass = "host:port:user:pass"
    case userPassAtHostPort = "user:pass@host:port"
    case curl
}

public struct ProxyEndpointResult: Codable, Sendable, Equatable {
    public let proxyId: String
    public let poolType: String
    public let host: String
    public let port: Int
    public let protocolName: String
    public let session: String
    public let stickyTtlMinutes: Int?
    public let countryCode: String
    public let targetBy: String
    public let locationCode: String?
    public let premium2x: Bool
    public let endpoints: [String]

    // Only `protocolName` needs an explicit key (JSON field is bare
    // `protocol`, no underscore for `.convertFromSnakeCase` to transform).
    // Every other property name already equals what `.convertFromSnakeCase`
    // produces from the JSON's snake_case keys — do not add explicit
    // snake_case CodingKeys for those, it would double-apply the transform
    // and break decoding/encoding (see note on ProxyTargetingResult above).
    enum CodingKeys: String, CodingKey {
        case proxyId, poolType, host, port
        case protocolName = "protocol"
        case session, stickyTtlMinutes, countryCode, targetBy, locationCode, premium2x, endpoints
    }
}

// MARK: - Manual registration session (beta)

public struct SessionTimelineEvent: Codable, Sendable, Equatable {
    public let at: String
    public let event: String
    public let detail: String?
}

public struct BrowserSessionResult: Codable, Sendable, Equatable {
    public let id: String
    public let status: String
    public let serviceName: String?
    public let countryCode: String?
    public let deviceMode: String?
    public let withProxy: Bool?
    /// Our own proxied live-viewer link. The backend never returns a raw
    /// upstream debug URL — never synthesize one.
    public let viewerUrl: String?
    public let targetUrl: String?
    public let orderId: String?
    public let phoneNumber: String?
    public let timeline: [SessionTimelineEvent]?
}

// MARK: - Tools

public struct NumberCheckResult: Codable, Sendable, Equatable {
    public let valid: Bool
    public let e164: String
    public let national: String?
    public let countryCode: String
    public let countryName: String
    public let countryPrefix: String?
    public let location: String?
    public let carrier: String?
    public let lineType: String
    public let spamRisk: String
    public let cached: Bool
    public let message: String?
}

// MARK: - Webhooks

public struct WebhookEndpoint: Codable, Sendable, Equatable {
    public let id: String
    public let url: String
    public let description: String?
    public let events: [String]
    public let active: Bool
    public let paused: Bool
    public let threshold: Double?
    public let failureCountConsecutive: Int
    public let lastDeliveredAt: String?
    public let lastErrorAt: String?
    public let lastErrorCode: String?
    public let createdAt: String
    public let updatedAt: String
    /// Only present on the response to `createWebhook` — returned exactly
    /// once. Store it immediately; it cannot be retrieved again.
    public let secret: String?
}

public struct WebhookDelivery: Codable, Sendable, Equatable {
    public let id: String
    public let eventId: String
    public let eventType: String
    public let attempt: Int
    public let status: String
    public let responseStatus: Int?
    public let responseBody: String?
    public let scheduledFor: String?
    public let deliveredAt: String?
    public let errorMessage: String?
    public let createdAt: String
    public let payload: AnyCodableValue?
}

public struct ListWebhooksResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let webhooks: [WebhookEndpoint]
    public let count: Int
}

public struct WebhookResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let webhook: WebhookEndpoint
}

public struct DeleteWebhookResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let id: String
}

public struct TestWebhookResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let message: String
    public let deliveryId: String
    public let eventId: String
    public let eventType: String
}

public struct ListWebhookDeliveriesResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let deliveries: [WebhookDelivery]
    public let count: Int
    public let limit: Int
    public let offset: Int
}

/// The full permitted set of webhook event types. VirtualSMS rejects
/// `create_webhook`/`update_webhook` calls with any event not in this list.
public enum WebhookEventType: String, Sendable, CaseIterable {
    case orderCreated = "order.created"
    case orderSmsReceived = "order.sms_received"
    case orderCancelled = "order.cancelled"
    case orderExpired = "order.expired"
    case rentalCreated = "rental.created"
    case rentalSmsReceived = "rental.sms_received"
    case rentalExpired = "rental.expired"
    case rentalCancelled = "rental.cancelled"
    case balanceLow = "balance.low"
}

/// Minimal `Codable` box for arbitrary JSON (used for `WebhookDelivery.payload`,
/// which is a free-form JSON blob keyed by event type).
public enum AnyCodableValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: AnyCodableValue].self) {
            self = .object(object)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
