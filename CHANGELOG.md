# Changelog

## 2.0.0 — first REST v1-native major

Breaking change from the (unshipped) v1.x line, which would have wrapped the legacy
`/stubs/handler_api.php` (sms-activate-compatible) dispatcher. v2 talks to `/api/v1/*` REST
endpoints directly and does not use the legacy PHP dispatcher at all. This SDK is a **native
client for the VirtualSMS REST API v1** — not a drop-in replacement for any sms-activate-style
client library.

- Initial public release: 46 methods across Activations/Orders, Rentals (Full Access + Platform
  tiers), Proxies, Account, Session (beta), Tools, and Webhooks (new in v2).
- Typed `VirtualSMSError` enum covering every documented HTTP failure mode (401/402/404/429/5xx)
  plus client-side guard errors (missing key, cancel/swap cooldown, beta gate).
- GET-only bounded retry (max 3 attempts, exponential backoff) for idempotent reads; mutating
  calls are never auto-retried.
- Client-side helpers (`getSms`, `waitForSms`, `orderHistory`, `cancelAllOrders`,
  `searchServices`, `findCheapest`, `getStats`, `getRental`, `generateProxyEndpoint`) matching the
  reference client's composition logic exactly.
