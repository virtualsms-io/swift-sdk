# VirtualSMS Swift SDK

A native Swift client for the [VirtualSMS](https://virtualsms.io) REST API v1 -  real carrier
mobile numbers (not VoIP), matching-country proxies, and long-term rentals, all from one API.

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

## What's covered (46 methods)

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

## License

MIT
