import Foundation

// MARK: - Session (start only — 1 method in scope)
//
// Beta, invite-only. The 3 session-*drive* tools (navigate/stop/viewer) are
// gated behind VIRTUALSMS_ENABLE_SESSIONS on the MCP surface and are OUT OF
// SCOPE for v2.0.0 SDKs per spec appendix.

extension VirtualSMS {

    public enum SessionDeviceMode: String, Sendable { case desktop, mobile }
    public enum SessionMode: String, Sendable { case attach, fresh }

    /// Start a country-matched cloud browser session the caller drives
    /// manually via `viewer_url`.
    /// `POST /api/v1/browser-sessions/start {serviceName?, country?, deviceMode?, withProxy?, targetUrl?, orderId?, mode?}` — auth required.
    ///
    /// On a 403/404/503 (beta-gate signals) this throws
    /// `VirtualSMSError.unavailable` with a clean invite-only message rather
    /// than surfacing the raw HTTP error.
    public func startManualRegistrationSession(
        serviceName: String? = nil,
        country: String? = nil,
        deviceMode: SessionDeviceMode? = nil,
        withProxy: Bool? = nil,
        targetUrl: String? = nil,
        orderId: String? = nil,
        mode: SessionMode = .fresh
    ) async throws -> BrowserSessionResult {
        let resolvedWithProxy = withProxy ?? (country != nil)
        do {
            struct Envelope: Decodable { let session: BrowserSessionResult? }
            if let envelope: Envelope = try? await send(.post, "/api/v1/browser-sessions/start", jsonBody: [
                "serviceName": serviceName,
                "country": country,
                "deviceMode": deviceMode?.rawValue,
                "withProxy": resolvedWithProxy,
                "targetUrl": targetUrl,
                "orderId": orderId,
                "mode": mode.rawValue,
            ]), let session = envelope.session {
                return session
            }
            return try await send(.post, "/api/v1/browser-sessions/start", jsonBody: [
                "serviceName": serviceName,
                "country": country,
                "deviceMode": deviceMode?.rawValue,
                "withProxy": resolvedWithProxy,
                "targetUrl": targetUrl,
                "orderId": orderId,
                "mode": mode.rawValue,
            ])
        } catch VirtualSMSError.notFound {
            // 404 - beta gate signal.
            throw VirtualSMSError.unavailable(Self.sessionsBetaMessage)
        } catch VirtualSMSError.apiError {
            // Any other non-standard 4xx (incl. 403) - beta gate signal.
            throw VirtualSMSError.unavailable(Self.sessionsBetaMessage)
        } catch VirtualSMSError.serverError(let status, _, _) where status == 503 {
            throw VirtualSMSError.unavailable(Self.sessionsBetaMessage)
        }
    }

    static let sessionsBetaMessage = "Manual registration sessions are an invite-only beta. Join https://t.me/VirtualSMS_io to request access."
}
