import Testing
@testable import ConcreteBot

@Test func decodesTicketJSON() throws {
    let json = """
    {
      "Ticket No.": "12345",
      "Delivery Date": "2024-12-11",
      "Delivery Time": "08:15",
      "Delivery Address": "123 Example St",
      "Mix Customer": {
        "Qty": "9.00",
        "Cust. Descr.": "Sample Mix",
        "Description": "Test Mix",
        "Code": "MX-1",
        "Slump": "5"
      },
      "Mix Vendor": null,
      "Extra Charges": [
        { "Description": "ENVIRONNEMENT", "Qty": "9.00" }
      ]
    }
    """

    let ticket = try TicketValidator.decode(json: json)
    #expect(ticket.ticketNumber == "12345")
    #expect(ticket.mixVendor == nil)
    #expect(ticket.extraCharges.first?.description == "ENVIRONNEMENT")
}

@Test func requiresTicketNumber() throws {
    let json = """
    {
      "Ticket No.": "",
      "Delivery Date": null,
      "Delivery Time": null,
      "Delivery Address": null,
      "Mix Customer": {
        "Qty": null,
        "Cust. Descr.": null,
        "Description": null,
        "Code": null,
        "Slump": null
      },
      "Mix Vendor": null,
      "Extra Charges": []
    }
    """

    let ticket = try TicketValidator.decode(json: json)
    #expect(throws: TicketValidationError.self) {
        try TicketValidator.validate(ticket: ticket)
    }
}

@Test func normalizesSlumpFromCodeAndRemovesExtraChargeNoise() {
    let ticket = Ticket(
        ticketNumber: "81521701",
        deliveryDate: "Wed, Dec 11 2024",
        deliveryTime: "09:20",
        deliveryAddress: "330 Mill Road, Etobicoke, ON M9C 1Y8",
        mixCustomer: MixRow(
            qty: "9.00 m³",
            customerDescription: "CHRONOLIA 45MPA 75%72HR N 20MM",
            description: "CHRONOLIA 45MPA 75%72HR N 20MM",
            code: "RMXD445N51N 150+-30",
            slump: "9.00 SEASONAL/MANUTE (PER M3)"
        ),
        mixVendor: nil,
        extraCharges: [
            ExtraCharge(description: "SEASONAL/MANUTE (PER M3)", qty: "9.00"),
            ExtraCharge(description: "FLEX FUEL FEE 1-INN", qty: "9.00")
        ]
    )

    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.mixCustomer.code == "RMXD445N51N")
    #expect(normalized.mixCustomer.slump == "150+-30")
}

@Test func normalizesSlumpWhenItMatchesExtraChargeQty() {
    let ticket = Ticket(
        ticketNumber: "12345",
        deliveryDate: "2024-12-11",
        deliveryTime: "08:15",
        deliveryAddress: "123 Example St",
        mixCustomer: MixRow(
            qty: "9.00 m³",
            customerDescription: "Sample Mix",
            description: "Test Mix",
            code: "MX-1",
            slump: "9.00"
        ),
        mixVendor: nil,
        extraCharges: [
            ExtraCharge(description: "ENVIRONNEMENT", qty: "9.00")
        ]
    )

    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.mixCustomer.code == "MX-1")
    #expect(normalized.mixCustomer.slump == nil)
}
