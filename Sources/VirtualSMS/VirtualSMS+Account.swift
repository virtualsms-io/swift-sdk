import Foundation

// MARK: - Account (4 methods)

extension VirtualSMS {

    private struct RawBalance: Decodable {
        let balanceUsd: Double?
        let balance: Double?
    }

    /// Check account balance. `GET /api/v1/customer/balance` — auth required.
    public func getBalance() async throws -> Balance {
        let raw: RawBalance = try await send(.get, "/api/v1/customer/balance")
        return Balance(balanceUsd: raw.balanceUsd ?? raw.balance ?? 0)
    }

    /// Full account profile. `GET /api/v1/customer/profile` — auth required.
    public func getProfile() async throws -> Profile {
        try await send(.get, "/api/v1/customer/profile")
    }

    /// Paginated transaction history. `GET /api/v1/customer/transactions` — auth required.
    /// - Parameters:
    ///   - type: filter by `deposit` / `purchase` / `refund` / `admin_credit`.
    ///   - from/to: RFC3339 or `YYYY-MM-DD`.
    ///   - limit: 1-200, default 50.
    ///   - offset: default 0.
    public func getTransactions(
        type: String? = nil,
        from: String? = nil,
        to: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> TransactionsPage {
        try await send(.get, "/api/v1/customer/transactions", query: [
            "type": type,
            "from": from,
            "to": to,
            "limit": limit.map(String.init),
            "offset": offset.map(String.init),
        ])
    }

    /// Aggregated usage stats over a lookback window. CLIENT-SIDE — calls
    /// `getBalance()` and `listOrders()` concurrently, then aggregates
    /// locally: status/service/country breakdowns, spend excluding cancelled
    /// orders, success rate over terminal-state orders only.
    ///
    /// - Note: `listOrders` is capped at 50 rows server-side; if the account
    ///   has more than 50 orders in the window this undercounts. `note` on
    ///   the result carries a warning in that case.
    public func getStats(sinceDays: Int = 30) async throws -> StatsResult {
        async let balanceTask = getBalance()
        async let ordersTask = listOrders()
        let (balance, orders) = try await (balanceTask, ordersTask)

        let cutoff: Date? = {
            guard sinceDays > 0 else { return nil }
            return Calendar.current.date(byAdding: .day, value: -sinceDays, to: Date())
        }()
        let isoFormatter = ISO8601DateFormatter()

        let windowed: [Order] = orders.filter { order in
            guard let cutoff, let createdAt = order.createdAt, let date = isoFormatter.date(from: createdAt) else {
                return true // undated orders / no window requested: include
            }
            return date >= cutoff
        }

        // "Terminal" order states, used for the success-rate denominator.
        // sms_received/completed count as successful; cancelled/failed/expired
        // are terminal-but-unsuccessful; anything else (waiting/pending) is
        // still in-flight and excluded from both success count and total spend.
        let successStatuses: Set<String> = ["sms_received", "completed"]
        let terminalStatuses: Set<String> = ["sms_received", "completed", "cancelled", "failed", "expired"]
        let terminalOrders = windowed.filter { terminalStatuses.contains($0.status) }
        let successfulOrders = windowed.filter { successStatuses.contains($0.status) }

        let spend = windowed
            .filter { $0.status != "cancelled" }
            .reduce(0.0) { $0 + ($1.price ?? 0) }

        var statusBreakdown: [String: Int] = [:]
        var serviceCounts: [String: Int] = [:]
        var countryCounts: [String: Int] = [:]
        for order in windowed {
            statusBreakdown[order.status, default: 0] += 1
            if let service = order.service, !service.isEmpty {
                serviceCounts[service, default: 0] += 1
            }
            if let country = order.country, !country.isEmpty {
                countryCounts[country, default: 0] += 1
            }
        }

        func topN(_ counts: [String: Int], _ n: Int = 5) -> [KeyCount] {
            counts.map { KeyCount(key: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
                .prefix(n)
                .map { $0 }
        }

        let successRate = terminalOrders.isEmpty ? 0 : Double(successfulOrders.count) / Double(terminalOrders.count)

        return StatsResult(
            windowDays: sinceDays,
            balanceUsd: balance.balanceUsd,
            totalOrders: windowed.count,
            successfulOrders: successfulOrders.count,
            successRate: successRate,
            totalSpendUsd: spend,
            statusBreakdown: statusBreakdown,
            topServices: topN(serviceCounts),
            topCountries: topN(countryCounts),
            note: orders.count >= 50 ? "listOrders is capped at 50 rows server-side; stats may undercount." : nil
        )
    }
}
