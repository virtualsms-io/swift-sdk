import VirtualSMS

// Rental flow: check availability, create a Full Access rental (any service,
// local SIM inventory), then list/extend/cancel it.

func rentalFlowExample() async throws {
    let client = VirtualSMS(apiKey: "vsms_your_api_key")

    let availability = try await client.rentalsAvailable(country: "GB", tier: .fullAccess)
    print("Available countries: \(availability.totalAvailable)")

    let rental = try await client.createRental(
        tier: .fullAccess,
        country: "GB",
        durationHours: 24,
        service: nil, // nil = full access to any service, not locked to one
        autoRenew: false
    )
    print("Rented \(rental.phoneNumber), expires \(rental.expiresAt)")

    // Platform tier (our global supplier network): locked to one service,
    // 24/72/168h durations only, same refund terms.
    let platformRental = try await client.createRental(
        tier: .platform,
        country: "GB",
        durationHours: 24,
        service: "tg"
    )
    print("Platform rental \(platformRental.rentalId): \(platformRental.phoneNumber)")

    let rentals = try await client.listRentals(status: "active")
    print("Active rentals: \(rentals.count)")

    if let first = rentals.first {
        let extended = try await client.extendRental(rentalId: first.id, durationHours: 24)
        print("Extended \(first.id): new expiry \(extended.newExpiresAt ?? "?")")

        // Full refund only within 20 minutes of purchase, before first SMS.
        let cancelled = try await client.cancelRental(rentalId: first.id)
        print("Cancel result: \(cancelled.success), refund: \(cancelled.refund ?? 0)")
    }
}
