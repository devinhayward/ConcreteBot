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
      "Mix Additional 1": null,
      "Mix Additional 2": null,
      "Extra Charges": [
        { "Description": "ENVIRONNEMENT", "Qty": "9.00" }
      ]
    }
    """

    let ticket = try TicketValidator.decode(json: json)
    #expect(ticket.ticketNumber == "12345")
    #expect(ticket.mixAdditional1 == nil)
    #expect(ticket.mixAdditional2 == nil)
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
      "Mix Additional 1": null,
      "Mix Additional 2": null,
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
        mixAdditional1: nil,
        mixAdditional2: nil,
        extraCharges: [
            ExtraCharge(description: "SEASONAL/MANUTE (PER M3)", qty: "9.00"),
            ExtraCharge(description: "FLEX FUEL FEE 1-INN", qty: "9.00")
        ]
    )

    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.mixCustomer.code == "RMXD445N51N")
    #expect(normalized.mixCustomer.slump == "150+-30")
}

@Test func normalizesDescriptionWhenItContainsCodeAndSlump() {
    let ticket = Ticket(
        ticketNumber: "81754967",
        deliveryDate: "Wed, Oct 1 2025",
        deliveryTime: "09:20",
        deliveryAddress: "596 Lolita Gardens Mississauga, ON L5A 4N8",
        mixCustomer: MixRow(
            qty: "8.00 m³",
            customerDescription: "STANDARD 45MPA N NA 20MM HR 20MM SP",
            description: "RMXS45N51NX 150+-30",
            code: "RMXS45N51NX",
            slump: "150+-30"
        ),
        mixAdditional1: nil,
        mixAdditional2: nil,
        extraCharges: []
    )

    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.mixCustomer.description == "45MPA N NA 20MM HR 20MM SP")
    #expect(normalized.mixCustomer.code == "RMXS45N51NX")
    #expect(normalized.mixCustomer.slump == "150+-30")
}

@Test func normalizesDeliveryAddressAndMixSpecPrefix() {
    let ticket = Ticket(
        ticketNumber: "81754972",
        deliveryDate: "Wed, Oct 1 2025",
        deliveryTime: "09:46",
        deliveryAddress: "596 Lolita Gardens\nMississauga, ON L5A\n4N8\nPO: -",
        mixCustomer: MixRow(
            qty: "9.00 m³",
            customerDescription: "STANDAR 35MPA NA 20MM HR",
            description: "STANDAR 35MPA NA 20MM HR",
            code: "RMXS35N51NX",
            slump: "150+-30"
        ),
        mixAdditional1: nil,
        mixAdditional2: nil,
        extraCharges: []
    )

    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.deliveryAddress == "596 Lolita Gardens Mississauga, ON L5A 4N8")
    #expect(normalized.mixCustomer.customerDescription == "STANDARD 35MPA NA 20MM HR")
    #expect(normalized.mixCustomer.description == "35MPA NA 20MM HR")
}

@Test func normalizesHeaderLikeDescriptionFromCustomerSpec() {
    let ticket = Ticket(
        ticketNumber: "81754978",
        deliveryDate: "Wed, Oct 1 2025",
        deliveryTime: "10:19",
        deliveryAddress: "596 Lolita Gardens, Mississauga, ON L5A 4N8",
        mixCustomer: MixRow(
            qty: "9.00 m³",
            customerDescription: "STANDARD 35MPA NA 20MM HR",
            description: "DESCRIPTION CODE",
            code: "RMXS35N51NX",
            slump: "150+-30"
        ),
        mixAdditional1: nil,
        mixAdditional2: nil,
        extraCharges: []
    )

    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.mixCustomer.customerDescription == "STANDARD 35MPA NA 20MM HR")
    #expect(normalized.mixCustomer.description == "35MPA NA 20MM HR")
}

@Test func normalizesStandardSpecOrdering() {
    let ticket = Ticket(
        ticketNumber: "81530465",
        deliveryDate: "Thu, Oct 2 2025",
        deliveryTime: "12:05",
        deliveryAddress: "596 Lolita Gardens Mississauga, ON L5A 3K7",
        mixCustomer: MixRow(
            qty: "9.00 m³",
            customerDescription: "NA 20MM STANDARD 40MPA NA 20MM HR",
            description: "NA 20MM STANDARD 40MPA NA 20MM HR",
            code: "RMXS40N51NX",
            slump: "150+-30"
        ),
        mixAdditional1: nil,
        mixAdditional2: nil,
        extraCharges: []
    )

    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.mixCustomer.customerDescription == "STANDARD 40MPA NA 20MM HR")
    #expect(normalized.mixCustomer.description == "STANDARD 40MPA NA 20MM HR")
}

@Test func normalizesMissingStandardInDescription() {
    let ticket = Ticket(
        ticketNumber: "81530465",
        deliveryDate: "Thu, Oct 2 2025",
        deliveryTime: "12:05",
        deliveryAddress: "596 Lolita Gardens Mississauga, ON L5A 3K7",
        mixCustomer: MixRow(
            qty: "9.00 m³",
            customerDescription: "STANDARD 40MPA NA 20MM HR",
            description: "40MPA NA 20MM HR",
            code: "RMXS40N51NX",
            slump: "150+-30"
        ),
        mixAdditional1: nil,
        mixAdditional2: nil,
        extraCharges: []
    )

    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.mixCustomer.customerDescription == "STANDARD 40MPA NA 20MM HR")
    #expect(normalized.mixCustomer.description == "STANDARD 40MPA NA 20MM HR")
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
        mixAdditional1: nil,
        mixAdditional2: nil,
        extraCharges: [
            ExtraCharge(description: "ENVIRONNEMENT", qty: "9.00")
        ]
    )

    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.mixCustomer.code == "MX-1")
    #expect(normalized.mixCustomer.slump == nil)
}

@Test func normalizesTicketWithAdditionalMixRow() throws {
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
      "Mix Additional 1": {
        "Qty": "7.00 m³",
        "Cust. Descr.": null,
        "Description": "45AWIN2 WEATHERMIX 5 TO 7 DEGREES",
        "Code": "907489",
        "Slump": null
      },
      "Mix Additional 2": null,
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

    #expect(normalized.mixAdditional1 != nil)
    #expect(normalized.mixCustomer.code == "RMXW45151NX")
    #expect(normalized.mixCustomer.slump == "150+-30")
    #expect(normalized.mixAdditional1?.code == "907489")
}

@Test func decodesTicketWithSecondAdditionalRow() throws {
    let json = """
    {
      "Ticket No.": "95820739",
      "Delivery Date": "Fri, Feb 21 2025",
      "Delivery Time": "09:07",
      "Delivery Address": "330 Mill Road, Toronto, ON M9C 1Y8",
      "Mix Customer": {
        "Qty": "9.00 m³",
        "Cust. Descr.": "WEATHERMIX 25 MPA C4 20MM HR",
        "Description": "WEATHERMIX 25 MPA C4 20MM HR",
        "Code": "RMXW25951NX",
        "Slump": "150+-30"
      },
      "Mix Additional 1": {
        "Qty": "9.00 m³",
        "Cust. Descr.": null,
        "Description": "MASTERFIBER F100 2 TO 4 DEGREES",
        "Code": "908414",
        "Slump": null
      },
      "Mix Additional 2": {
        "Qty": "9.00 m³",
        "Cust. Descr.": null,
        "Description": "MICROSYNTHETIC FIBER",
        "Code": "902210",
        "Slump": null
      },
      "Extra Charges": [
        { "Description": "SITE WASH WATER MANAGEMENT FEE", "Qty": "9.00" }
      ]
    }
    """

    let ticket = try TicketValidator.decode(json: json)
    #expect(ticket.mixAdditional1?.code == "908414")
    #expect(ticket.mixAdditional2?.code == "902210")
}
