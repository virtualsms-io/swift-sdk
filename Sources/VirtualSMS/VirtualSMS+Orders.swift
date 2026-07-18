import Foundation

// MARK: - Activations / Orders (14 methods)

extension VirtualSMS {

    /// Buy a virtual number for one-off SMS verification.
    /// `POST /api/v1/customer/purchase {service, country}` — auth required.
    public func createOrder(service: String, country: String) async throws -> Order {
        try await send(.post, "/api/v1/customer/purchase", jsonBody: ["service": service, "country": country])
    }

    /// Full order detail, including any received SMS.
    /// `GET /api/v1/customer/order/{orderId}` — auth required.
    public func getOrder(orderId: String) async throws -> Order {
        try await send(.get, "/api/v1/customer/order/\(orderId)")
    }

    /// Poll for SMS delivery on an order — a thin, normalized wrapper over
    /// `getOrder`. CLIENT-SIDE (no dedicated backend route). Extracts the
    /// first 4-8 digit run found in the message content as `code`.
    public func getSms(orderId: String) async throws -> GetSmsResult {
        let order = try await getOrder(orderId: orderId)
        let code = Self.extractCode(from: order)
        return GetSmsResult(
            status: order.status,
            phoneNumber: order.phoneNumber,
            messages: order.messages,
            code: code,
            smsCode: order.smsCode,
            smsText: order.smsText
        )
    }

    /// Extracts the first 4-8 digit run from an order's message content /
    /// legacy sms fields — matches the reference client's `\b(\d{4,8})\b`.
    static func extractCode(from order: Order) -> String? {
        var candidates: [String] = []
        if let messages = order.messages {
            candidates.append(contentsOf: messages.map { $0.content })
        }
        if let smsText = order.smsText { candidates.append(smsText) }
        if let smsCode = order.smsCode { candidates.append(smsCode) }

        let regex = try? NSRegularExpression(pattern: "\\b(\\d{4,8})\\b")
        for text in candidates {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex?.firstMatch(in: text, range: range), let matchRange = Range(match.range(at: 1), in: text) {
                return String(text[matchRange])
            }
        }
        return nil
    }

    /// Block until an SMS arrives on `orderId` or `timeoutSeconds` elapses.
    /// CLIENT-SIDE polling helper (no WebSocket in this SDK — the spec marks
    /// WebSocket racing as optional per-SDK/v2.1; polling-only is an
    /// acceptable v2.0.0 baseline).
    ///
    /// - Never throws on timeout: returns `WaitForSmsResult(success: false, ...)`.
    /// - Throws if the order reaches a terminal failure state (`cancelled`/`failed`).
    /// - Parameters:
    ///   - timeoutSeconds: default 300 (5 minutes) — generous, since an SDK
    ///     caller is usually a human or script blocking on this, not an LLM
    ///     agent loop (the MCP tool's own default is 60s/max 600s; documented
    ///     discrepancy per spec).
    ///   - intervalSeconds: default 5.
    public func waitForSms(
        orderId: String,
        timeoutSeconds: Double = 300,
        intervalSeconds: Double = 5
    ) async throws -> WaitForSmsResult {
        let start = Date()

        func check() async throws -> (Order, WaitForSmsResult?) {
            let order = try await getOrder(orderId: orderId)
            if order.status == "cancelled" || order.status == "failed" {
                throw VirtualSMSError.apiError("Order \(orderId) reached terminal state '\(order.status)' while waiting for SMS.")
            }
            let hasMessage = !(order.messages?.isEmpty ?? true) || order.smsCode != nil || order.smsText != nil
            if hasMessage {
                let result = WaitForSmsResult(
                    success: true,
                    orderId: orderId,
                    phoneNumber: order.phoneNumber,
                    status: "sms_received",
                    messages: order.messages,
                    code: Self.extractCode(from: order),
                    deliveryMethod: "poll",
                    elapsedSeconds: Date().timeIntervalSince(start),
                    error: nil
                )
                return (order, result)
            }
            return (order, nil)
        }

        // Short-circuit: check once up front before entering the poll loop.
        let (firstOrder, firstResult) = try await check()
        if let firstResult { return firstResult }

        while Date().timeIntervalSince(start) < timeoutSeconds {
            try await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
            let (_, result) = try await check()
            if let result { return result }
        }

        return WaitForSmsResult(
            success: false,
            orderId: orderId,
            phoneNumber: firstOrder.phoneNumber,
            status: nil,
            messages: nil,
            code: nil,
            deliveryMethod: nil,
            elapsedSeconds: Date().timeIntervalSince(start),
            error: "timeout"
        )
    }

    /// Cancel + refund an order (before any SMS received).
    /// `POST /api/v1/customer/cancel/{orderId}` — auth required.
    ///
    /// Pre-checks `cancel_available_at` via a fresh `getOrder` call first and
    /// throws a local `VirtualSMSError.cooldownActive` if still in the
    /// future (120s post-purchase cooldown) — saves a guaranteed-to-fail
    /// round-trip.
    public func cancelOrder(orderId: String) async throws -> CancelResult {
        let order = try await getOrder(orderId: orderId)
        if let cooldown = Self.parseDate(order.cancelAvailableAt), cooldown > Date() {
            throw VirtualSMSError.cooldownActive(
                "cancel_order is on cooldown for order \(orderId) until \(order.cancelAvailableAt ?? ""). " +
                "Cancellation opens 120 seconds after purchase."
            )
        }
        return try await send(.post, "/api/v1/customer/cancel/\(orderId)")
    }

    /// Get a new number for the same service/country at no extra charge.
    /// `POST /api/v1/customer/swap/{orderId}` — auth required.
    ///
    /// Same cooldown pre-check pattern as `cancelOrder`, gated on `swap_available_at`.
    public func swapNumber(orderId: String) async throws -> Order {
        let order = try await getOrder(orderId: orderId)
        if let cooldown = Self.parseDate(order.swapAvailableAt), cooldown > Date() {
            throw VirtualSMSError.cooldownActive(
                "swap_number is on cooldown for order \(orderId) until \(order.swapAvailableAt ?? ""). " +
                "Swapping opens 120 seconds after purchase."
            )
        }
        return try await send(.post, "/api/v1/customer/swap/\(orderId)")
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    /// Ask the provider to resend the SMS to the SAME number (not a new
    /// number — see `swapNumber` for that). `POST /api/v1/orders/{orderId}/retry` — auth required.
    public func retryOrder(orderId: String) async throws -> RetryOrderResult {
        try await send(.post, "/api/v1/orders/\(orderId)/retry")
    }

    private struct RawOrderListItem: Decodable {
        let orderId: String?
        let id: String?
        let phoneNumber: String?
        let serviceId: String?
        let service: String?
        let countryId: String?
        let country: String?
        let priceCharged: Double?
        let price: Double?
        let createdAt: String?
        let expiresAt: String?
        let status: String?
        let smsCode: String?
        let smsText: String?
    }
    private struct OrdersEnvelope: Decodable { let orders: [RawOrderListItem]? }

    /// List orders, optional status filter. `GET /api/v1/customer/orders?status=` — auth required.
    ///
    /// A 404 on this endpoint is swallowed to `[]` rather than thrown —
    /// mirrors the reference client: the endpoint may not exist on older
    /// deployments.
    public func listOrders(status: String? = nil) async throws -> [Order] {
        let raw: [RawOrderListItem]
        do {
            if let envelope: OrdersEnvelope = try? await send(
                .get, "/api/v1/customer/orders", query: ["status": status]
            ), let orders = envelope.orders {
                raw = orders
            } else {
                raw = try await send(.get, "/api/v1/customer/orders", query: ["status": status])
            }
        } catch VirtualSMSError.notFound {
            return []
        }
        return raw.map {
            Order(
                orderId: $0.orderId ?? $0.id ?? "",
                phoneNumber: $0.phoneNumber ?? "",
                service: $0.serviceId ?? $0.service ?? "",
                country: $0.countryId ?? $0.country ?? "",
                price: $0.priceCharged ?? $0.price ?? 0,
                createdAt: $0.createdAt,
                expiresAt: $0.expiresAt,
                status: $0.status ?? "",
                smsCode: $0.smsCode,
                smsText: $0.smsText
            )
        }
    }

    /// Order history with client-side filtering (service/country/since_days)
    /// on top of `listOrders`, plus a hard client-side cap on `limit`.
    /// CLIENT-SIDE (calls `listOrders`, then filters/caps locally).
    public func orderHistory(
        status: String? = nil,
        service: String? = nil,
        country: String? = nil,
        sinceDays: Int? = nil,
        limit: Int = 20
    ) async throws -> OrderHistoryResult {
        let cappedLimit = min(max(limit, 1), 50)
        let all = try await listOrders(status: status)

        let cutoff: Date? = sinceDays.map { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) ?? Date() }
        let isoFormatter = ISO8601DateFormatter()

        let filtered = all.filter { order in
            if let service, order.service != service { return false }
            if let country, order.country != country { return false }
            if let cutoff, let createdAt = order.createdAt, let date = isoFormatter.date(from: createdAt), date < cutoff {
                return false
            }
            return true
        }

        return OrderHistoryResult(
            count: min(filtered.count, cappedLimit),
            totalMatched: filtered.count,
            filters: OrderHistoryFilters(status: status, service: service, country: country, sinceDays: sinceDays),
            orders: Array(filtered.prefix(cappedLimit))
        )
    }

    /// Bulk-cancel every active order. CLIENT-SIDE: lists orders, filters to
    /// active statuses, then fans out `cancelOrder` concurrently with
    /// partial-failure tolerance (never aborts on the first failure).
    public func cancelAllOrders() async throws -> CancelAllOrdersResult {
        let activeStatuses: Set<String> = ["waiting", "pending", "sms_received", "created"]
        let all = try await listOrders()
        let active = all.filter { activeStatuses.contains($0.status) }

        var cancelledOrders: [CancelledOrder] = []
        var failures: [CancelFailure] = []

        await withTaskGroup(of: Result<CancelledOrder, CancelFailure>.self) { group in
            for order in active {
                group.addTask {
                    do {
                        let result = try await self.cancelOrder(orderId: order.orderId)
                        return .success(CancelledOrder(orderId: order.orderId, refunded: result.refunded))
                    } catch {
                        return .failure(CancelFailure(orderId: order.orderId, error: error.localizedDescription))
                    }
                }
            }
            for await outcome in group {
                switch outcome {
                case .success(let cancelled): cancelledOrders.append(cancelled)
                case .failure(let failure): failures.append(failure)
                }
            }
        }

        return CancelAllOrdersResult(
            cancelled: cancelledOrders.count,
            failed: failures.count,
            totalActive: active.count,
            cancelledOrders: cancelledOrders,
            failures: failures
        )
    }

    /// Find the right service code using natural language ("uber", "binance",
    /// "steam"). CLIENT-SIDE — calls `listServices()` once, then fuzzy-scores
    /// locally (no dedicated backend search route).
    ///
    /// Scoring: exact code/name match = 1.0; prefix match = 0.9; substring
    /// match = 0.7; else word-token overlap ratio capped at 0.6. Only
    /// matches scoring >= 0.5 are returned, top 5, sorted descending.
    public func searchServices(query: String) async throws -> SearchServicesResult {
        let services = try await listServices()
        let needle = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        func score(_ service: Service) -> Double {
            let code = service.code.lowercased()
            let name = service.name.lowercased()
            if code == needle || name == needle { return 1.0 }
            if name.hasPrefix(needle) || code.hasPrefix(needle) { return 0.9 }
            if name.contains(needle) || code.contains(needle) { return 0.7 }
            let needleTokens = Set(needle.split(separator: " ").map(String.init))
            let nameTokens = Set(name.split(separator: " ").map(String.init))
            guard !needleTokens.isEmpty, !nameTokens.isEmpty else { return 0 }
            let overlap = needleTokens.intersection(nameTokens).count
            let ratio = Double(overlap) / Double(max(needleTokens.count, nameTokens.count))
            return min(ratio, 0.6)
        }

        let matches = services
            .map { ($0, score($0)) }
            .filter { $0.1 >= 0.5 }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { ServiceMatch(code: $0.0.code, name: $0.0.name, matchScore: ($0.1 * 100).rounded() / 100) }

        return SearchServicesResult(
            query: query,
            matches: Array(matches),
            message: matches.isEmpty ? "No confident matches for '\(query)'." : nil,
            tip: matches.isEmpty ? "Try listServices() for the full catalog." : nil
        )
    }

    /// Find the cheapest in-stock countries for a service, sorted by price.
    /// CLIENT-SIDE — calls `getCatalogCountries(service:)` (the same source
    /// `getPrice` uses for real stock), filters to `count > 0`, sorts
    /// ascending by price.
    public func findCheapest(service: String, limit: Int = 5) async throws -> FindCheapestResult {
        let catalog = try await getCatalogCountries(service: service)
        let inStock = catalog.filter { $0.count > 0 }.sorted { $0.priceUsd < $1.priceUsd }
        let options = inStock.prefix(max(limit, 1)).map {
            CheapestOption(country: $0.iso, countryName: $0.name, priceUsd: $0.priceUsd, stock: true)
        }
        return FindCheapestResult(
            service: service,
            cheapestOptions: Array(options),
            totalAvailableCountries: inStock.count,
            message: inStock.isEmpty ? "No in-stock countries for '\(service)'. Try searchServices() or listServices()." : nil
        )
    }
}
