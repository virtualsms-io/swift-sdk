# VirtualSMS Swift SDK

## What is VirtualSMS?

Official Swift SDK for the VirtualSMS API. VirtualSMS is an account verification platform for
individuals, developers, and AI agents: one-time SMS verification, dedicated number rentals,
matching-country proxies, and private cloud browser sessions (beta), all behind one API, one
MCP server, and one prepaid balance. This package wraps the REST API in native Swift, backed
by real carrier-issued mobile numbers (real physical SIM cards, not VoIP) across 2500+
services in 145+ countries.

Built for developers and AI agents: REST API, hosted MCP server, SDKs.

This is **not** a wrapper or a drop-in replacement for any other SMS-verification client library.
It talks directly to `https://virtualsms.io/api/v1/*` using `URLSession` + Swift concurrency
(`async`/`await`), with typed `Codable` models and a typed error enum for every documented
failure mode.

- **Platforms:** macOS 12+, iOS 15+, tvOS 15+, watchOS 8+
- **Swift tools version:** 5.9
- **Dependencies:** none -  `Foundation` + `URLSession` only

## Installation

### Swift Package Manager

Add the package in Xcode: **File → Add Package Dependencies…** and paste:

```
https://github.com/virtualsms-io/swift-sdk
```

Or add it to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/virtualsms-io/swift-sdk", from: "2.0.0")
]
```

## Quickstart

1. **Get an API key** -  sign up at [virtualsms.io](https://virtualsms.io), then Settings → API Keys.
2. **Buy a number**, then **poll or wait for the code**:

```swift
import VirtualSMS

let client = VirtualSMS(apiKey: "vsms_your_api_key")

// Check price + real stock before buying.
let price = try await client.getPrice(service: "tg", country: "US")
guard price.available else { fatalError("out of stock") }

// Buy a number.
let order = try await client.createOrder(service: "tg", country: "US")
print("Number: \(order.phoneNumber)")

// Block until the SMS arrives (default: 5 minute timeout, 5s poll interval).
let result = try await client.waitForSms(orderId: order.orderId)
if result.success {
    print("Code: \(result.code ?? "")")
}
```

More flows: [`examples/ActivationFlow.swift`](examples/ActivationFlow.swift),
[`examples/RentalFlow.swift`](examples/RentalFlow.swift),
[`examples/ProxyFlow.swift`](examples/ProxyFlow.swift).

Full docs: [virtualsms.io/docs](https://virtualsms.io/docs).

## Capabilities

1. One-time SMS verification. Receive a code for a service like WhatsApp, Telegram, Discord,
   or a dating app, on demand, from $0.05 per code.
2. Dedicated number rentals. Hold one number for 1-30 days and receive SMS from any service
   on that number, from $0.25/day.
3. Matching-country proxies. Pair a number with an IP from the same country, across 223
   proxy countries, from $1.10/GB.
4. Private cloud browser sessions (beta). Start a country-matched browser in a live viewer
   for the signup step itself, invite-only.

## Why real SIM cards

VirtualSMS runs on real carrier-issued mobile numbers, backed by real physical SIM cards,
not VoIP. Services like WhatsApp, Telegram, Discord, and dating apps run a carrier lookup
before they send a code, and VoIP or virtual numbers fail that check more often than a real
SIM does. A physical SIM on a real carrier network reads like any other phone on that network,
carriers like Vodafone, O2, and T-Mobile depending on the country, which is part of why
VirtualSMS holds a 95%+ success rate across 2500+ services in 145+ countries.

## API coverage

What's covered (46 methods):

| Group | Methods |
|---|---|
| Activations / Orders | `listServices`, `listCountries`, `getPrice`, `createOrder`, `getOrder`, `getSms`, `waitForSms`, `cancelOrder`, `swapNumber`, `retryOrder`, `listOrders`, `orderHistory`, `cancelAllOrders`, `searchServices`, `findCheapest` |
| Rentals | `rentalsPricing`, `rentalsAvailable`, `rentalsServices`, `rentalsPrice`, `createRental`, `listRentals`, `getRental`, `extendRental`, `cancelRental` |
| Proxies | `listProxyCatalog`, `listProxies`, `buyProxy`, `rotateProxy`, `getProxyUsage`, `getProxyUsageHistory`, `setProxyTargeting`, `testProxy`, `listProxyLocations`, `generateProxyEndpoint` |
| Account | `getBalance`, `getProfile`, `getTransactions`, `getStats` |
| Session (beta) | `startManualRegistrationSession` |
| Tools | `checkNumber` |
| Webhooks | `listWebhooks`, `createWebhook`, `getWebhook`, `updateWebhook`, `deleteWebhook`, `testWebhook`, `listWebhookDeliveries` |

Some methods (`getSms`, `waitForSms`, `orderHistory`, `cancelAllOrders`, `searchServices`,
`findCheapest`, `getStats`, `getRental`, `generateProxyEndpoint`) are **client-side helpers** - 
they compose one or more REST calls and do the aggregation/filtering locally, matching the
reference implementation exactly. They're documented inline with `///` doc comments on every
method.

## Rentals: two tiers

Both tiers carry the **same refund terms**: full refund within 20 minutes of purchase and before
the first SMS arrives.

- **`.fullAccess`** -  local SIM inventory, usable for any service, longer durations, optional auto-renew.
- **`.platform`** -  sourced via our global supplier network, locked to **one** chosen service per
  number, 24/72/168h durations only.

```swift
let rental = try await client.createRental(tier: .fullAccess, country: "GB", durationHours: 24)
```

## Errors

Every failure surfaces as a typed `VirtualSMSError`:

```swift
do {
    _ = try await client.createOrder(service: "tg", country: "US")
} catch VirtualSMSError.insufficientBalance {
    print("top up at https://virtualsms.io")
} catch VirtualSMSError.rateLimited {
    print("slow down")
} catch VirtualSMSError.serverError(let status, let mutating, let message) {
    // `mutating == true` means this happened on a POST/PUT/PATCH/DELETE - 
    // the purchase/cancel/etc. may have gone through despite the error.
    // NEVER blindly retry; verify with a read call first (listOrders, getOrder, ...).
    print("server error \(status): \(message)")
} catch {
    print(error.localizedDescription)
}
```

Only idempotent `GET`/`HEAD` requests are retried automatically (max 3 attempts, exponential
backoff 300ms/600ms) on network failure or a 5xx response. Mutating calls are **never** retried by
the SDK.

## Webhooks

```swift
let webhook = try await client.createWebhook(
    url: "https://example.com/hooks/virtualsms",
    events: [.orderSmsReceived, .balanceLow],
    threshold: 5.0
)
// webhook.webhook.secret is returned EXACTLY ONCE - store it now.
print("Signing secret: \(webhook.webhook.secret ?? "")")
```

## Publishing (Swift Package Index)

This package is discoverable on the [Swift Package Index](https://swiftpackageindex.com/) purely
by being a public repo with semver Git tags -  **no publish account, token, or CI step required**.
A new version ships by pushing a tag:

```bash
git tag v2.0.0
git push origin v2.0.0
```

The Swift Package Index re-crawls tagged public repos automatically; a `.spi.yml` at the repo root
declares the supported platforms/Swift versions for the badge/compatibility matrix.

## Requirements

- Swift 5.9+
- macOS 12+, iOS 15+, tvOS 15+, or watchOS 8+ (async/await + `URLSession`)

## AI agents and MCP

This package is the API-client half of VirtualSMS: typed methods you call directly from your
own Swift code. VirtualSMS also exposes a hosted MCP server, so an AI agent such as Claude or
Cursor can request a number, wait for a code, or manage a rental the same way this package
does, without you writing the glue code yourself. See
[virtualsms.io/docs](https://virtualsms.io/docs) for MCP server details.

## FAQ

### What is VirtualSMS?
VirtualSMS is an account verification platform for individuals, developers, and AI agents. It combines one-time SMS verification, dedicated number rentals, matching-country proxies, and private cloud browser sessions behind one API, one MCP server, and one prepaid balance.

### Does VirtualSMS use real SIM cards or VoIP numbers?
VirtualSMS uses real carrier-issued mobile numbers, backed by real physical SIM cards, not VoIP. Many services, including WhatsApp, Telegram, Discord, and dating apps, reject VoIP and virtual numbers at signup; a real physical SIM on a real carrier network passes that check far more often, which is reflected in a 95%+ success rate.

### Which services and countries does VirtualSMS support?
VirtualSMS covers 2500+ services across 145+ countries for SMS verification and number rentals, plus matching-country proxies across 223 proxy countries. Coverage spans messaging apps, social platforms, marketplaces, dating apps, and financial services.

### Can I rent a number, or only buy one-time codes?
Both. Buy a single one-time code from $0.05, or rent a dedicated number for 1-30 days from $0.25/day to receive SMS from any service on that number for the rental window.

### Does VirtualSMS work with AI agents and MCP?
Yes. VirtualSMS exposes a hosted MCP server plus a REST API and official SDKs in nine languages, so an AI agent can request a number, wait for a code, or manage a rental the same way a developer would call the API directly.

### How much does VirtualSMS cost?
Pricing is pay-as-you-go from one prepaid balance: SMS verification from $0.05 per code, number rentals from $0.25/day, and proxies from $1.10/GB. There is no subscription requirement.

### Is there a free API key?
Yes. Creating a VirtualSMS account issues an API key immediately, at no cost. You only spend from your prepaid balance when you place an order: an activation, a rental, or a proxy.

## Links

- Website: [virtualsms.io](https://virtualsms.io)
- Docs: [virtualsms.io/docs](https://virtualsms.io/docs)
- Dashboard: [virtualsms.io/dashboard](https://virtualsms.io/dashboard)
- Swift Package Index: [swiftpackageindex.com](https://swiftpackageindex.com/)

Works with PHP, Node.js, TypeScript, Python, Ruby, .NET, Go, Rust, Swift, and Java, plus any
HTTP client and MCP-compatible AI agents such as Claude and Cursor.

## License

MIT
