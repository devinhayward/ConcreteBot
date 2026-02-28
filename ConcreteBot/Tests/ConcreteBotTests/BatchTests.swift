import Testing
@testable import ConcreteBot

@Test func parsesBatchCSVRows() throws {
    let csv = """
    # comment

    pdf,pages
    /tmp/alpha.pdf,1-3
    /tmp/bravo.pdf,
    "/tmp/with,comma.pdf",auto
    '/tmp/with,comma-two.pdf',auto
    """

    let rows = try Batch.parseCSVRows(csv)

    #expect(rows.count == 4)
    #expect(rows[0].pdfPath == "/tmp/alpha.pdf")
    #expect(rows[0].pages == "1-3")
    #expect(rows[1].pdfPath == "/tmp/bravo.pdf")
    #expect(rows[1].pages == nil)
    #expect(rows[2].pdfPath == "/tmp/with,comma.pdf")
    #expect(rows[2].pages == "auto")
    #expect(rows[3].pdfPath == "/tmp/with,comma-two.pdf")
    #expect(rows[3].pages == "auto")
}
