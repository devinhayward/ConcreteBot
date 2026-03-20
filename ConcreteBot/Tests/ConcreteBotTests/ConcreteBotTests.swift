import Foundation
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

@Test func keepsDescriptionWithoutStandardWhenCustomerHasStandardPrefix() {
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
    #expect(normalized.mixCustomer.description == "40MPA NA 20MM HR")
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

@Test func normalizesShotcreteSpecAndPromotesDescriptionOverCustomerName() {
    let ticket = Ticket(
        ticketNumber: "95822767",
        deliveryDate: "Mon, May 5 2025",
        deliveryTime: "07:42",
        deliveryAddress: "330 Mill Road, Toronto, ON M9C 1Y8",
        mixCustomer: MixRow(
            qty: "8.00 m³",
            customerDescription: "BMR RENTAL LIMITED",
            description: "SHOTCRETE 40MPA F2 14MM",
            code: "RMXQ405C11X",
            slump: "60+-10"
        ),
        mixAdditional1: nil,
        mixAdditional2: nil,
        extraCharges: [
            ExtraCharge(description: "TOARC FEE (M3)", qty: "8.00")
        ]
    )

    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.mixCustomer.customerDescription == "40MPA F2 14MM SHOTCRETE")
    #expect(normalized.mixCustomer.description == "40MPA F2 14MM SHOTCRETE")
}

@Test func normalizesMixSpecUnitCasingInCustomerDescription() {
    let ticket = Ticket(
        ticketNumber: "95822773",
        deliveryDate: "Mon, May 5 2025",
        deliveryTime: "08:27",
        deliveryAddress: "330 Mill Road, Toronto, ON M9C 1Y8",
        mixCustomer: MixRow(
            qty: "8.00 m³",
            customerDescription: "40MPA F2 14mm SHOTCRETE",
            description: "40MPA F2 14MM SHOTCRETE",
            code: "RMXQ405C11X",
            slump: "60+-10"
        ),
        mixAdditional1: nil,
        mixAdditional2: nil,
        extraCharges: []
    )

    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.mixCustomer.customerDescription == "40MPA F2 14MM SHOTCRETE")
    #expect(normalized.mixCustomer.description == "40MPA F2 14MM SHOTCRETE")
}

@Test func normalizesRepeatedWeatherSpecSuffixForClassMix() {
    let ticket = Ticket(
        ticketNumber: "95820744",
        deliveryDate: "Fri, Feb 21 2025",
        deliveryTime: "10:11",
        deliveryAddress: "330 Mill Road, Toronto, ON M9C 1Y8",
        mixCustomer: MixRow(
            qty: "9.00 m³",
            customerDescription: "WEATHERMIX 25 MPA C4 20MM HR 25MPA C4 20MM HR",
            description: "WEATHERMIX 25 MPA C4 20MM HR 25MPA C4 20MM HR",
            code: "RMXW25951NX",
            slump: "150+-30"
        ),
        mixAdditional1: nil,
        mixAdditional2: nil,
        extraCharges: []
    )

    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.mixCustomer.customerDescription == "WEATHERMIX 25MPA C4 20MM HR")
    #expect(normalized.mixCustomer.description == "WEATHERMIX 25 MPA C4 20MM HR")
}

@Test func normalizesRepeatedWeatherSpecSuffixForNonAirMix() {
    let ticket = Ticket(
        ticketNumber: "96069731",
        deliveryDate: "Fri, Feb 21 2025",
        deliveryTime: "13:14",
        deliveryAddress: "330 Mill Road, Toronto, ON M9C 1Y8",
        mixCustomer: MixRow(
            qty: "8.00 m³",
            customerDescription: "WEATHERMIX 35 MPA NON AIR 20MM MPA NON",
            description: "WEATHERMIX 35 MPA NON AIR 20MM MPA NON AIR",
            code: "RMXW35N511X",
            slump: "80+-30"
        ),
        mixAdditional1: nil,
        mixAdditional2: nil,
        extraCharges: []
    )

    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.mixCustomer.customerDescription == "WEATHERMIX 35 MPA NON AIR 20MM")
    #expect(normalized.mixCustomer.description == "WEATHERMIX 35 MPA NON AIR 20MM")
}

@Test func dedupesRepeatedShotcreteToken() {
    let ticket = Ticket(
        ticketNumber: "95822779",
        deliveryDate: "Mon, May 5 2025",
        deliveryTime: "09:37",
        deliveryAddress: "330 Mill Road, Toronto, ON M9C 1Y8",
        mixCustomer: MixRow(
            qty: "8.00 m³",
            customerDescription: "40MPA F2 14MM SHOTCRETE SHOTCRETE",
            description: "40MPA F2 14MM SHOTCRETE SHOTCRETE",
            code: "RMXQ405C11X",
            slump: "60+-10"
        ),
        mixAdditional1: nil,
        mixAdditional2: nil,
        extraCharges: []
    )

    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.mixCustomer.customerDescription == "40MPA F2 14MM SHOTCRETE")
    #expect(normalized.mixCustomer.description == "40MPA F2 14MM SHOTCRETE")
}

@Test func normalizesAndDedupesNoisyExtraCharges() {
    let ticket = Ticket(
        ticketNumber: "95822794",
        deliveryDate: "Mon, May 5 2025",
        deliveryTime: "12:00",
        deliveryAddress: "330 Mill Road, Toronto, ON M9C 1Y8",
        mixCustomer: MixRow(
            qty: "6.00 m³",
            customerDescription: "40MPA F2 14MM SHOTCRETE",
            description: "40MPA F2 14MM SHOTCRETE",
            code: "RMXQ405C11X",
            slump: "60+-10"
        ),
        mixAdditional1: nil,
        mixAdditional2: nil,
        extraCharges: [
            ExtraCharge(description: "6.00 FLEX FUEL FEE 1-INN", qty: "1"),
            ExtraCharge(description: "6.00 ENVIRONMENTAL/ENVIRONNEMENT", qty: "1"),
            ExtraCharge(description: "6.00 TOARC FEE (M3)", qty: "1"),
            ExtraCharge(description: "FLEX FUEL FEE 1-INN", qty: "6.00"),
            ExtraCharge(description: "ENVIRONMENTAL/ENVIRONNEMENT", qty: "6.00"),
            ExtraCharge(description: "TOARC FEE (M3)", qty: "6.00"),
            ExtraCharge(description: "6.00 SITE WASH WATER MANAGEMENT FEE", qty: "1")
        ]
    )

    let normalized = TicketNormalizer.normalize(ticket: ticket)

    #expect(normalized.extraCharges.count == 4)
    #expect(normalized.extraCharges[0].description == "FLEX FUEL FEE 1-INN")
    #expect(normalized.extraCharges[0].qty == "6.00")
    #expect(normalized.extraCharges[1].description == "ENVIRONMENTAL/ENVIRONNEMENT")
    #expect(normalized.extraCharges[1].qty == "6.00")
    #expect(normalized.extraCharges[2].description == "TOARC FEE (M3)")
    #expect(normalized.extraCharges[2].qty == "6.00")
    #expect(normalized.extraCharges[3].description == "SITE WASH WATER MANAGEMENT FEE")
    #expect(normalized.extraCharges[3].qty == "6.00")
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

@Test func parseExtractCommandDefaultsModelModeToAuto() throws {
    let command = try parseCLI(arguments: [
        "concretebot",
        "extract",
        "--pdf", "/tmp/input.pdf",
        "--pages", "1-2"
    ])

    guard case let .extract(options) = command else {
        Issue.record("Expected extract command.")
        return
    }
    #expect(options.modelMode == "auto")
    #expect(options.promptVariant == "adaptive")
    #expect(options.runReport == nil)
}

@Test func parseExtractCommandAcceptsModelModeAndRunReport() throws {
    let command = try parseCLI(arguments: [
        "concretebot",
        "extract",
        "--pdf", "/tmp/input.pdf",
        "--pages", "auto",
        "--model-mode", "guided",
        "--prompt-variant", "minimal",
        "--run-report", "/tmp/run-report.json"
    ])

    guard case let .extract(options) = command else {
        Issue.record("Expected extract command.")
        return
    }
    #expect(options.modelMode == "guided")
    #expect(options.promptVariant == "minimal")
    #expect(options.runReport == "/tmp/run-report.json")
}

@Test func parseExtractCommandRejectsInvalidModelMode() throws {
    #expect(throws: CLIError.self) {
        try parseCLI(arguments: [
            "concretebot",
            "extract",
            "--pdf", "/tmp/input.pdf",
            "--pages", "1",
            "--model-mode", "turbo"
        ])
    }
}

@Test func parseExtractCommandRejectsInvalidPromptVariant() throws {
    #expect(throws: CLIError.self) {
        try parseCLI(arguments: [
            "concretebot",
            "extract",
            "--pdf", "/tmp/input.pdf",
            "--pages", "1",
            "--prompt-variant", "maximal"
        ])
    }
}

@Test func parseEvaluateCommandAcceptsModeAndPromptLists() throws {
    let command = try parseCLI(arguments: [
        "concretebot",
        "evaluate",
        "--model-modes", "guided,legacy",
        "--prompt-variants", "compact,minimal"
    ])

    guard case let .evaluate(options) = command else {
        Issue.record("Expected evaluate command.")
        return
    }
    #expect(options.modelModes == ["guided", "legacy"])
    #expect(options.promptVariants == ["compact", "minimal"])
}

@Test func parseEvaluateCommandRejectsUnsupportedModes() throws {
    #expect(throws: CLIError.self) {
        try parseCLI(arguments: [
            "concretebot",
            "evaluate",
            "--model-modes", "guided,unknown"
        ])
    }
}

@Test func usesLegacyCompactValidationFallbackForAdditionalMixRowIssuesInAutoMode() {
    let issues = [
        TicketValidationIssue(
            path: "Mix Additional 1.Qty",
            message: "Qty must be numeric with optional m3 unit"
        ),
        TicketValidationIssue(
            path: "Mix Additional 1.Slump",
            message: "Slump must be a number or X+-Y format"
        ),
        TicketValidationIssue(
            path: "Mix Additional 2.Qty",
            message: "Qty must be numeric with optional m3 unit"
        )
    ]

    #expect(
        Extract.shouldUseLegacyCompactValidationFallback(
            modelMode: .auto,
            issues: issues
        )
    )
}

@Test func doesNotUseLegacyCompactValidationFallbackForNonAdditionalMixIssues() {
    let issues = [
        TicketValidationIssue(
            path: "Mix Customer.Qty",
            message: "Qty must be numeric with optional m3 unit"
        )
    ]

    #expect(
        !Extract.shouldUseLegacyCompactValidationFallback(
            modelMode: .auto,
            issues: issues
        )
    )
}

@Test func doesNotUseLegacyCompactValidationFallbackOutsideAutoMode() {
    let issues = [
        TicketValidationIssue(
            path: "Mix Additional 1.Qty",
            message: "Qty must be numeric with optional m3 unit"
        )
    ]

    #expect(
        !Extract.shouldUseLegacyCompactValidationFallback(
            modelMode: .guided,
            issues: issues
        )
    )
    #expect(
        !Extract.shouldUseLegacyCompactValidationFallback(
            modelMode: .legacy,
            issues: issues
        )
    )
}

@Test func lookupFieldEvidenceReturnsTargetMixRowAndParsedHint() {
    let mixRowLines = """
    9.00 m3
    RMX35N 80+-20
    7.50 m3
    RMXS45N51NX 150+-30
    """
    let mixParsedHints = """
    Row 1:
    Qty: 9.00 m3
    Code: RMX35N
    Slump: 80+-20
    Spec: 35MPA N 20MM
    Row 2:
    Qty: 7.50 m3
    Code: RMXS45N51NX
    Slump: 150+-30
    Spec: 45MPA N 20MM HR
    """

    let evidence = Extract.lookupFieldEvidence(
        path: "Mix Additional 1.Slump",
        pageText: "",
        mixText: "",
        mixRowLines: mixRowLines,
        mixParsedHints: mixParsedHints,
        extraChargesText: ""
    )

    #expect(evidence?.contains("Raw row 2:") == true)
    #expect(evidence?.contains("RMXS45N51NX 150+-30") == true)
    #expect(evidence?.contains("Parsed hint row 2:") == true)
    #expect(evidence?.contains("Slump: 150+-30") == true)
}

@Test func getMixRowReturnsRequestedOneBasedRow() {
    let mixRow = Extract.getMixRow(
        rowIndex: 2,
        mixText: "",
        mixRowLines: """
        9.00 m3
        RMX35N 80+-20
        7.50 m3
        RMXS45N51NX 150+-30
        """
    )

    #expect(mixRow == "7.50 m3\nRMXS45N51NX 150+-30")
}

@Test func getMixRowFallsBackToRawMixSectionText() {
    let mixRow = Extract.getMixRow(
        rowIndex: 2,
        mixText: """
        MIX
        QTY CUST DESCR DESCRIPTION CODE SLUMP
        9.00 m3
        RMX35N 80+-20
        7.50 m3
        RMXS45N51NX 150+-30
        """,
        mixRowLines: ""
    )

    #expect(mixRow == "7.50 m3\nRMXS45N51NX 150+-30")
}

@Test func getChargeRowReturnsRequestedOneBasedRow() {
    let chargeRow = Extract.getChargeRow(
        rowIndex: 2,
        extraChargesText: """
        EXTRA CHARGES
        SEASONAL/MINUTE (PER M3) 9.00
        FLEX FUEL FEE 1-INN 9.00
        """
    )

    #expect(chargeRow == "FLEX FUEL FEE 1-INN 9.00")
}

@Test func getChargeRowMergesQtyOnlySplitLines() {
    let chargeRow = Extract.getChargeRow(
        rowIndex: 1,
        extraChargesText: """
        EXTRA CHARGES
        9.00
        SEASONAL/MINUTE (PER M3)
        FLEX FUEL FEE 1-INN 9.00
        """
    )

    #expect(chargeRow == "9.00 SEASONAL/MINUTE (PER M3)")
}

@Test func extractsRecalledTicketNumbersFromOrderSummaryText() {
    let recalled = Extract.extractRecalledTicketNumbers(from: """
    1. 9.00 m³ 96077921 5410710 Recalled
    2. 9.00 m³ 96077922 5410711 Delivered
    3. 9.00 m³ 96077930 5410487 Recalled
    """)

    #expect(recalled == Set(["96077921", "96077930"]))
}

@Test func detectsRecalledWatermarkText() {
    #expect(Extract.containsRecalledWatermark(in: "RECALLED") == true)
    #expect(Extract.containsRecalledWatermark(in: "This ticket has been Recalled") == true)
    #expect(Extract.containsRecalledWatermark(in: "RETURNED: 0,00 m³") == false)
}

@Test func processPageForTestAppliesRecalledFlagFromDocumentContext() throws {
    let tickets = try Extract.processPageForTest(
        pageText: """
        TICKET NO. 96077921
        DELIVERY DATE: Wed, Mar 5 2026
        DELIVERY TIME: 09:00
        DELIVERY ADDR.: 596 Lolita Gardens
        MIX
        9.00 m3
        RMXS45N51NX 150+-30
        INSTRUCTIONS
        EXTRA CHARGES
        """,
        modelResponse: """
        {
          "Ticket No.": "96077921",
          "Delivery Date": "Wed, Mar 5 2026",
          "Delivery Time": "09:00",
          "Delivery Address": "596 Lolita Gardens",
          "Mix Customer": {
            "Qty": "9.00 m3",
            "Cust. Descr.": null,
            "Description": null,
            "Code": "RMXS45N51NX",
            "Slump": "150+-30"
          },
          "Mix Additional 1": null,
          "Mix Additional 2": null,
          "Extra Charges": []
        }
        """,
        recalledTicketNumbers: Set(["96077921"])
    )

    #expect(tickets.count == 1)
    #expect(tickets.first?.recalled == true)
}

@Test func processPageForTestAppliesRecalledFlagFromWatermarkText() throws {
    let tickets = try Extract.processPageForTest(
        pageText: """
        RECALLED
        TICKET NO. 96077921
        DELIVERY DATE: Wed, Mar 5 2026
        DELIVERY TIME: 09:00
        DELIVERY ADDR.: 596 Lolita Gardens
        MIX
        9.00 m3
        RMXS45N51NX 150+-30
        INSTRUCTIONS
        EXTRA CHARGES
        """,
        modelResponse: """
        {
          "Ticket No.": "96077921",
          "Delivery Date": "Wed, Mar 5 2026",
          "Delivery Time": "09:00",
          "Delivery Address": "596 Lolita Gardens",
          "Mix Customer": {
            "Qty": "9.00 m3",
            "Cust. Descr.": null,
            "Description": null,
            "Code": "RMXS45N51NX",
            "Slump": "150+-30"
          },
          "Mix Additional 1": null,
          "Mix Additional 2": null,
          "Extra Charges": []
        }
        """
    )

    #expect(tickets.count == 1)
    #expect(tickets.first?.recalled == true)
}

@Test func fileWriterUsesRecalledSuffixForRecalledTickets() {
    let ticket = Ticket(
        ticketNumber: "96077921",
        recalled: true,
        deliveryDate: "Wed, Mar 5 2026",
        deliveryTime: "09:00",
        deliveryAddress: "596 Lolita Gardens",
        mixCustomer: MixRow(
            qty: "9.00 m3",
            customerDescription: "STANDARD 45MPA N NA 20MM HR",
            description: "45MPA N NA 20MM HR",
            code: "RMXS45N51NX",
            slump: "150+-30"
        ),
        mixAdditional1: nil,
        mixAdditional2: nil,
        extraCharges: []
    )

    #expect(FileWriter.outputFileName(for: ticket) == "ticket-96077921_recalled.json")
}

@Test func lookupFieldEvidenceReturnsRequestedExtraChargeRow() {
    let evidence = Extract.lookupFieldEvidence(
        path: "Extra Charges[1].Qty",
        pageText: "",
        mixText: "",
        mixRowLines: "",
        mixParsedHints: "",
        extraChargesText: """
        EXTRA CHARGES
        SEASONAL/MINUTE (PER M3) 9.00
        FLEX FUEL FEE 1-INN 9.00
        """
    )

    #expect(evidence == "Charge row 2:\nFLEX FUEL FEE 1-INN 9.00")
}
