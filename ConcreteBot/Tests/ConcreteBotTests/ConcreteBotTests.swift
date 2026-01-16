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

@Test func normalizesTicketWithMixVendorRow() throws {
    let json = """
    {
      "Ticket No.": "95820135",
      "Delivery Date": "Wed, Jan 29 2025",
      "Delivery Time": "11:31",
      "Delivery Address": "330 Mill Road Toronto, ON M9C 1Y8",
      "Mix Customer": {
        "Qty": "7.00 m³",
        "Cust. Descr.": "WEATHERMIX 45MPA C1 20MM HR",
        "Description": "WEATHERMIX 45MPA C1 20MM HR",
        "Code": "RMXW45151NX",
        "Slump": "150+-30"
      },
      "Mix Vendor": {
        "Qty": "7.00 m³",
        "Cust. Descr.": null,
        "Description": "45AWIN2 WEATHERMIX 5 TO 7 DEGREES",
        "Code": "907489",
        "Slump": null
      },
      "Extra Charges": [
        { "Description": "SEASONAL/MANUTE (PER M3)", "Qty": "7.00" },
        { "Description": "SITE WASH WATER MANAGEMENT FEE", "Qty": "7.00" },
        { "Description": "TOARC FEE (M3)", "Qty": "7.00" },
        { "Description": "SUPERPLASTICIZER EXT", "Qty": "7.00" },
        { "Description": "ENVIRONMENTAL/ENVIRONNEMENT", "Qty": "7.00" },
        { "Description": "FLEX FUEL FEE 1--INN", "Qty": "7.00" }
      ]
    }
    """

    let ticket = try TicketValidator.decode(json: json)
    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.mixVendor != nil)
    #expect(normalized.mixCustomer.code == "RMXW45151NX")
    #expect(normalized.mixCustomer.slump == "150+-30")
    #expect(normalized.mixVendor?.code == "907489")
}
