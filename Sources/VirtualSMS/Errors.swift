import Foundation

/// Every error the SDK can throw. Maps 1:1 onto the HTTP status codes the
/// VirtualSMS REST v1 API returns, plus a handful of client-side guard
/// errors (missing key, cooldown windows, beta gates) that exist purely to
/// save a round-trip the server would reject anyway.
public enum VirtualSMSError: Error, LocalizedError, Sendable {
    /// No API key was supplied to an operation that requires one.
    case missingApiKey

    /// HTTP 401 — invalid or missing API key.
    case badApiKey

    /// HTTP 402 — account balance is too low for the requested purchase.
    case insufficientBalance

    /// HTTP 404 — the requested resource (order/rental/proxy/webhook id) does not exist.
    case notFound(String)

    /// HTTP 429 — rate limit exceeded. Never retried automatically; slow down.
    case rateLimited

    /// HTTP 5xx. `mutating` is true when this happened on a POST/PUT/PATCH/DELETE —
    /// in that case the operation may have completed server-side despite the
    /// error, and the SDK never retries it automatically. Verify via a read
    /// call (list_orders / get_order / list_rentals / etc.) before retrying.
    case serverError(status: Int, mutating: Bool, message: String)

    /// Any other 4xx not covered above.
    case apiError(String)

    /// Client-side pre-check failed: a cancel/swap was attempted inside its
    /// cooldown window. Saves a guaranteed-to-fail round trip.
    case cooldownActive(String)

    /// A feature is gated / not available for the given input (e.g. a
    /// platform-tier rental country with no mapped numeric ID, or the manual
    /// registration session beta gate).
    case unavailable(String)

    /// Response body could not be decoded into the expected shape.
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "This operation requires an API key. Get one at https://virtualsms.io"
        case .badApiKey:
            return "Invalid API key. Get one at https://virtualsms.io"
        case .insufficientBalance:
            return "Insufficient balance. Top up at https://virtualsms.io"
        case .notFound(let message):
            return "Not found: \(message)"
        case .rateLimited:
            return "Rate limit exceeded. Please slow down requests."
        case .serverError(let status, let mutating, let message):
            if mutating {
                return "VirtualSMS had a server error (\(status)) on a request that may have made a purchase or changed state. " +
                    "DO NOT blindly retry: first verify with a list/get call (e.g. listOrders, listRentals, getOrder) " +
                    "whether it actually succeeded, as you may have been charged. Details: \(message)"
            }
            return "VirtualSMS server error (\(status)). Safe to retry this read-only request. Details: \(message)"
        case .apiError(let message):
            return "API error: \(message)"
        case .cooldownActive(let message):
            return message
        case .unavailable(let message):
            return message
        case .invalidResponse(let message):
            return "Could not decode VirtualSMS response: \(message)"
        }
    }
}
