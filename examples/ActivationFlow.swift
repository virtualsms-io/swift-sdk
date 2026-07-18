import VirtualSMS

// Basic SMS-verification activation flow: buy a number, wait for the code,
// then cancel/swap as needed.
//
// Run with: swift run --package-path . ActivationExample
// (or paste into a Swift script / Playground with the VirtualSMS package added)

@main
struct ActivationExample {
    static func main() async {
        do {
            // Get your API key at https://virtualsms.io (Settings -> API Keys)
            let client = VirtualSMS(apiKey: "vsms_your_api_key")

            let balance = try await client.getBalance()
            print("Balance: $\(balance.balanceUsd)")

            // Check price + real stock before buying.
            let price = try await client.getPrice(service: "tg", country: "US")
            guard price.available else {
                print("Telegram/US is out of stock right now.")
                return
            }
            print("Telegram/US: $\(price.priceUsd), in stock: \(price.available)")

            // Buy a number.
            let order = try await client.createOrder(service: "tg", country: "US")
            print("Bought \(order.phoneNumber) (order \(order.orderId))")

            // Block until the SMS arrives (5 min default timeout, 5s poll interval).
            let result = try await client.waitForSms(orderId: order.orderId)
            if result.success {
                print("Code: \(result.code ?? "?")")
            } else {
                print("No SMS yet (\(result.error ?? "unknown")). Try swapNumber or cancelOrder.")
                let cancel = try await client.cancelOrder(orderId: order.orderId)
                print("Cancelled, refunded: \(cancel.refunded)")
            }
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }
}
