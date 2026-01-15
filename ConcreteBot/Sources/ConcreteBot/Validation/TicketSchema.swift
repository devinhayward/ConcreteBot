import Foundation

struct Ticket: Codable {
    let ticketNumber: String?
    let deliveryDate: String?
    let deliveryTime: String?
    let deliveryAddress: String?
    let mixCustomer: MixRow
    let mixVendor: MixRow?
    let extraCharges: [ExtraCharge]

    enum CodingKeys: String, CodingKey {
        case ticketNumber = "Ticket No."
        case deliveryDate = "Delivery Date"
        case deliveryTime = "Delivery Time"
        case deliveryAddress = "Delivery Address"
        case mixCustomer = "Mix Customer"
        case mixVendor = "Mix Vendor"
        case extraCharges = "Extra Charges"
    }
}

struct MixRow: Codable {
    let qty: String?
    let customerDescription: String?
    let description: String?
    let code: String?
    let slump: String?

    enum CodingKeys: String, CodingKey {
        case qty = "Qty"
        case customerDescription = "Cust. Descr."
        case description = "Description"
        case code = "Code"
        case slump = "Slump"
    }
}

struct ExtraCharge: Codable {
    let description: String?
    let qty: String?

    enum CodingKeys: String, CodingKey {
        case description = "Description"
        case qty = "Qty"
    }
}
