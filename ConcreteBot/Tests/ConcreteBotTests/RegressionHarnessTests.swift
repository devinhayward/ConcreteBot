import Foundation
import Testing
@testable import ConcreteBot

@Test func regressionFixturesEndToEnd() throws {
    let root = fixturesRoot()
    let manager = FileManager.default
    guard manager.fileExists(atPath: root.path) else { return }

    let fixtureDirs = try manager.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ).filter { url in
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    guard !fixtureDirs.isEmpty else { return }

    for fixtureDir in fixtureDirs.sorted(by: { $0.path < $1.path }) {
        let fixtureName = fixtureDir.lastPathComponent
        let pageText = try String(
            contentsOf: fixtureDir.appendingPathComponent("page_text.txt"),
            encoding: .utf8
        )
        let modelResponse = try String(
            contentsOf: fixtureDir.appendingPathComponent("model_response.txt"),
            encoding: .utf8
        )
        let expectedJSON = try String(
            contentsOf: fixtureDir.appendingPathComponent("expected.json"),
            encoding: .utf8
        )

        let expected = try TicketValidator.decode(json: expectedJSON)
        let tickets = try Extract.processPageForTest(
            pageText: pageText,
            modelResponse: modelResponse
        )
        #expect(tickets.count == 1, "Fixture \(fixtureName) produced \(tickets.count) tickets.")
        guard let actual = tickets.first else { continue }

        assertEqual(expected: expected, actual: actual, fixture: fixtureName)
    }
}

private func fixturesRoot() -> URL {
    let testFile = URL(fileURLWithPath: #filePath)
    return testFile.deletingLastPathComponent().appendingPathComponent("Fixtures")
}

private func assertEqual(expected: Ticket, actual: Ticket, fixture: String) {
    #expect(actual.ticketNumber == expected.ticketNumber, "\(fixture) ticketNumber mismatch")
    #expect(actual.deliveryDate == expected.deliveryDate, "\(fixture) deliveryDate mismatch")
    #expect(actual.deliveryTime == expected.deliveryTime, "\(fixture) deliveryTime mismatch")
    #expect(actual.deliveryAddress == expected.deliveryAddress, "\(fixture) deliveryAddress mismatch")

    assertEqualMixRow(
        expected: expected.mixCustomer,
        actual: actual.mixCustomer,
        path: "Mix Customer",
        fixture: fixture
    )
    assertEqualOptionalMixRow(
        expected: expected.mixAdditional1,
        actual: actual.mixAdditional1,
        path: "Mix Additional 1",
        fixture: fixture
    )
    assertEqualOptionalMixRow(
        expected: expected.mixAdditional2,
        actual: actual.mixAdditional2,
        path: "Mix Additional 2",
        fixture: fixture
    )

    #expect(
        actual.extraCharges.count == expected.extraCharges.count,
        "\(fixture) extraCharges count mismatch"
    )
    for index in 0..<min(actual.extraCharges.count, expected.extraCharges.count) {
        let actualCharge = actual.extraCharges[index]
        let expectedCharge = expected.extraCharges[index]
        #expect(
            actualCharge.description == expectedCharge.description,
            "\(fixture) Extra Charges[\(index)].Description mismatch"
        )
        #expect(
            actualCharge.qty == expectedCharge.qty,
            "\(fixture) Extra Charges[\(index)].Qty mismatch"
        )
    }
}

private func assertEqualOptionalMixRow(
    expected: MixRow?,
    actual: MixRow?,
    path: String,
    fixture: String
) {
    if expected == nil || actual == nil {
        #expect(expected == nil && actual == nil, "\(fixture) \(path) nil mismatch")
        return
    }
    assertEqualMixRow(expected: expected!, actual: actual!, path: path, fixture: fixture)
}

private func assertEqualMixRow(
    expected: MixRow,
    actual: MixRow,
    path: String,
    fixture: String
) {
    #expect(actual.qty == expected.qty, "\(fixture) \(path).Qty mismatch")
    #expect(actual.customerDescription == expected.customerDescription, "\(fixture) \(path).Cust. Descr. mismatch")
    #expect(actual.description == expected.description, "\(fixture) \(path).Description mismatch")
    #expect(actual.code == expected.code, "\(fixture) \(path).Code mismatch")
    #expect(actual.slump == expected.slump, "\(fixture) \(path).Slump mismatch")
}
