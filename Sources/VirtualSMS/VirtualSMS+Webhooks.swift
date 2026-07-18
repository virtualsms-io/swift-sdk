import Foundation

// MARK: - Webhooks (7 methods) — NEW in v2
//
// Base path `/api/v1/customer/webhooks`. Auth is the same `X-API-Key` header
// as every other customer route — no special-case handling needed.

extension VirtualSMS {

    /// List the account's webhook subscriptions. `GET /api/v1/customer/webhooks`.
    public func listWebhooks() async throws -> ListWebhooksResult {
        try await send(.get, "/api/v1/customer/webhooks")
    }

    /// Create a webhook subscription.
    /// `POST /api/v1/customer/webhooks {url, description?, events, threshold?}`.
    ///
    /// - `url` MUST be `https://` — no localhost / IP literals.
    /// - `events` must be non-empty, a subset of `WebhookEventType`.
    /// - `threshold` is required if `events` includes `.balanceLow` (0 < n <= 99999.99, 2dp).
    /// - The returned `WebhookEndpoint.secret` is returned EXACTLY ONCE, on
    ///   create only. Store it immediately — it cannot be retrieved again.
    public func createWebhook(
        url: String,
        events: [WebhookEventType],
        description: String? = nil,
        threshold: Double? = nil
    ) async throws -> WebhookResult {
        try await send(.post, "/api/v1/customer/webhooks", jsonBody: [
            "url": url,
            "description": description,
            "events": events.map { $0.rawValue },
            "threshold": threshold,
        ])
    }

    /// Get one webhook (never includes the secret). `GET /api/v1/customer/webhooks/{id}`.
    public func getWebhook(id: String) async throws -> WebhookResult {
        try await send(.get, "/api/v1/customer/webhooks/\(id)")
    }

    /// Partial update (url/description/events/threshold/active/paused).
    /// `PATCH /api/v1/customer/webhooks/{id}`.
    ///
    /// At least one field is required. Un-pausing (`paused: false` when
    /// previously `true`) resets `failure_count_consecutive` to 0 server-side.
    public func updateWebhook(
        id: String,
        url: String? = nil,
        description: String? = nil,
        events: [WebhookEventType]? = nil,
        threshold: Double? = nil,
        active: Bool? = nil,
        paused: Bool? = nil
    ) async throws -> WebhookResult {
        try await send(.patch, "/api/v1/customer/webhooks/\(id)", jsonBody: [
            "url": url,
            "description": description,
            "events": events?.map { $0.rawValue },
            "threshold": threshold,
            "active": active,
            "paused": paused,
        ])
    }

    /// Delete a webhook. `DELETE /api/v1/customer/webhooks/{id}`.
    public func deleteWebhook(id: String) async throws -> DeleteWebhookResult {
        try await send(.delete, "/api/v1/customer/webhooks/\(id)")
    }

    /// Fire a synthetic test event through the real dispatcher.
    /// `POST /api/v1/customer/webhooks/{id}/test`. Requires the webhook to
    /// be active and not paused, else the server returns a 400.
    public func testWebhook(id: String) async throws -> TestWebhookResult {
        try await send(.post, "/api/v1/customer/webhooks/\(id)/test")
    }

    /// List recent delivery attempts for a webhook.
    /// `GET /api/v1/customer/webhooks/{id}/deliveries?limit=&offset=`.
    /// `limit` default 100, max 500. `offset` default 0.
    public func listWebhookDeliveries(
        id: String,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> ListWebhookDeliveriesResult {
        try await send(.get, "/api/v1/customer/webhooks/\(id)/deliveries", query: [
            "limit": limit.map(String.init),
            "offset": offset.map(String.init),
        ])
    }
}
