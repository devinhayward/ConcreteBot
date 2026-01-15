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
