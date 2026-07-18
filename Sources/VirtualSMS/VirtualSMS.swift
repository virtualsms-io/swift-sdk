import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Native Swift client for the VirtualSMS REST API v1.
///
/// ```swift
/// let client = VirtualSMS(apiKey: "vsms_your_api_key")
/// let balance = try await client.getBalance()
/// let order = try await client.createOrder(service: "tg", country: "US")
/// let sms = try await client.waitForSms(orderId: order.orderId)
/// ```
///
/// Every mutating call (POST/PUT/PATCH/DELETE) is NEVER retried automatically —
/// a 5xx on a purchase/cancel/rotate/extend call does not prove the operation
/// failed server-side. Only idempotent GET/HEAD reads get a bounded retry
/// (max 3 attempts, exponential backoff 300ms/600ms) for transient network
/// failures and 5xx responses. See `VirtualSMSError` for the full error model.
public final class VirtualSMS: @unchecked Sendable {

    /// Default production API root. Endpoints are appended under `/api/v1/...`.
    public static let defaultBaseURL = "https://virtualsms.io"

    public let apiKey: String?
    public let baseURL: String
    public let timeout: TimeInterval

    let session: URLSession
    let decoder: JSONDecoder
    let getRetryMaxAttempts = 3
    let getRetryBaseDelaySeconds = 0.3

    /// - Parameters:
    ///   - apiKey: Your VirtualSMS API key (Settings → API Keys at
    ///     https://virtualsms.io). Optional — public endpoints (catalog,
    ///     pricing, `checkNumber`, etc.) work without one; authenticated
    ///     endpoints throw `VirtualSMSError.missingApiKey` if omitted.
    ///   - baseURL: API root, defaults to `https://virtualsms.io`. Override
    ///     for a sandbox/staging environment.
    ///   - timeout: Per-request timeout in seconds. Defaults to 30, matching
    ///     every other VirtualSMS SDK.
    public init(apiKey: String? = nil, baseURL: String = VirtualSMS.defaultBaseURL, timeout: TimeInterval = 30) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeout = timeout

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func requireApiKey() throws -> String {
        guard let apiKey, !apiKey.isEmpty else { throw VirtualSMSError.missingApiKey }
        return apiKey
    }

    // MARK: - Core request plumbing

    enum Method: String { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE" }

    /// Performs one HTTP call and decodes the JSON body into `T`.
    ///
    /// - `query` values are stringified by the caller; `nil` values are omitted.
    /// - `jsonBody` is only sent for mutating methods, and always carries a
    ///   fresh `X-Idempotency-Key` (UUID) unless the caller doesn't want one
    ///   generated — every SDK mirrors the reference `client.ts` axios
    ///   interceptor here.
    /// - `auth` = true attaches `X-API-Key`; throws `missingApiKey` first if
    ///   none was configured.
    @discardableResult
    func send<T: Decodable>(
        _ method: Method,
        _ path: String,
        query: [String: String?] = [:],
        jsonBody: [String: Any?]? = nil,
        auth: Bool = true
    ) async throws -> T {
        // Build the URL via plain string concatenation rather than
        // `appendingPathComponent`, which can mis-handle a `path` that
        // already starts with "/" (every call site here passes one). Every
        // `baseURL` is expected without a trailing slash (default
        // `https://virtualsms.io`) and every `path` starts with "/api/v1/...".
        let trimmedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard var components = URLComponents(string: trimmedBase + path) else {
            throw VirtualSMSError.invalidResponse("could not build URL for \(path)")
        }
        let queryItems = query.compactMap { key, value -> URLQueryItem? in
            guard let value else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw VirtualSMSError.invalidResponse("could not build URL for \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if auth {
            let key = try requireApiKey()
            request.setValue(key, forHTTPHeaderField: "X-API-Key")
        }

        let isMutating = method != .get
        if isMutating {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")
            if let jsonBody {
                let cleaned = jsonBody.compactMapValues { $0 }
                request.httpBody = try? JSONSerialization.data(withJSONObject: cleaned)
            }
        }

        let maxAttempts = isMutating ? 1 : getRetryMaxAttempts
        var attempt = 0
        var lastNetworkError: Error?

        while attempt < maxAttempts {
            attempt += 1
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw VirtualSMSError.invalidResponse("no HTTP response")
                }

                if (200..<300).contains(http.statusCode) {
                    if data.isEmpty {
                        // Some mutating endpoints (rare) may return an empty
                        // 2xx body; only valid if T can decode from `{}`.
                        return try decoder.decode(T.self, from: Data("{}".utf8))
                    }
                    do {
                        return try decoder.decode(T.self, from: data)
                    } catch {
                        throw VirtualSMSError.invalidResponse("\(error)")
                    }
                }

                let message = Self.extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
                switch http.statusCode {
                case 401:
                    throw VirtualSMSError.badApiKey
                case 402:
                    throw VirtualSMSError.insufficientBalance
                case 404:
                    throw VirtualSMSError.notFound(message)
                case 429:
                    throw VirtualSMSError.rateLimited
                case 500...599:
                    if !isMutating && attempt < maxAttempts {
                        try await Task.sleep(nanoseconds: Self.delayNanoseconds(attempt: attempt, base: getRetryBaseDelaySeconds))
                        continue
                    }
                    throw VirtualSMSError.serverError(status: http.statusCode, mutating: isMutating, message: message)
                default:
                    throw VirtualSMSError.apiError(message)
                }
            } catch let error as VirtualSMSError {
                throw error
            } catch {
                // Network-level failure (timeout, connection reset, DNS, etc.)
                lastNetworkError = error
                if !isMutating && attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: Self.delayNanoseconds(attempt: attempt, base: getRetryBaseDelaySeconds))
                    continue
                }
                throw error
            }
        }

        throw lastNetworkError ?? VirtualSMSError.apiError("request failed after \(maxAttempts) attempt(s)")
    }

    static func delayNanoseconds(attempt: Int, base: Double) -> UInt64 {
        let seconds = base * pow(2.0, Double(attempt - 1))
        return UInt64(seconds * 1_000_000_000)
    }

    static func extractErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let message = json["message"] as? String { return message }
        if let error = json["error"] as? String { return error }
        return nil
    }
}
