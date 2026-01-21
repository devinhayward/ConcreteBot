import Foundation

struct Ticket: Codable {
    let ticketNumber: String?
    let deliveryDate: String?
    let deliveryTime: String?
    let deliveryAddress: String?
    let mixCustomer: MixRow
    let mixAdditional1: MixRow?
    let mixAdditional2: MixRow?
    let extraCharges: [ExtraCharge]

    enum CodingKeys: String, CodingKey {
        case ticketNumber = "Ticket No."
        case deliveryDate = "Delivery Date"
        case deliveryTime = "Delivery Time"
        case deliveryAddress = "Delivery Address"
        case mixCustomer = "Mix Customer"
        case mixAdditional1 = "Mix Additional 1"
        case mixAdditional2 = "Mix Additional 2"
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
