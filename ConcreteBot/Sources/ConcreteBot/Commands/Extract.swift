import Foundation
import PDFKit

enum ExtractError: Error, CustomStringConvertible {
    case missingPromptTemplate
    case noJSONFound
    case invalidResponse(String)
    case missingResponseInput
    case invalidPageRange(String)
    case pdfLoadFailed(String)
    case pageOutOfRange(Int, Int)
    case emptyPageText(Int)

    var description: String {
        switch self {
        case .missingPromptTemplate:
            return "Missing prompt template in resources."
        case .noJSONFound:
            return "No JSON objects found in model response."
        case .invalidResponse(let detail):
            return "Invalid response: \(detail)"
        case .missingResponseInput:
            return "No response input provided. Use --response-file or --response-stdin."
        case .invalidPageRange(let detail):
            return "Invalid page range: \(detail)"
        case .pdfLoadFailed(let detail):
            return "Failed to load PDF: \(detail)"
        case .pageOutOfRange(let page, let total):
            return "Page \(page) is out of range (1-\(total))."
        case .emptyPageText(let page):
            return "No text extracted from page \(page)."
        }
    }
}

enum Extract {
    static func run(options: CLIOptions) throws {
        let promptTemplate = try loadPromptTemplate()

        let response: String
        if let responseFile = options.responseFile {
            response = try String(contentsOfFile: responseFile, encoding: .utf8)
        } else if options.responseStdin {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            response = String(data: data, encoding: .utf8) ?? ""
        } else {
            response = ""
        }

        if !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let jsonObjects = splitJSONObjects(from: response)
            guard !jsonObjects.isEmpty else {
                throw ExtractError.noJSONFound
            }

            var tickets: [Ticket] = []
            for json in jsonObjects {
                let ticket = try TicketValidator.decode(json: json)
                let normalizedTicket = TicketNormalizer.normalize(ticket: ticket)
                try TicketValidator.validate(ticket: normalizedTicket)
                tickets.append(normalizedTicket)
            }

            let outputDir = expandingTilde(in: options.outputDir)
            try FileWriter.write(tickets: tickets, outputDir: outputDir)
            return
        }

        let pageNumbers: [Int]
        do {
            pageNumbers = try PageRange.parse(options.pages)
        } catch let error as PageRangeError {
            throw ExtractError.invalidPageRange(error.description)
        }
        guard let document = PDFDocument(url: URL(fileURLWithPath: options.pdfPath)) else {
            throw ExtractError.pdfLoadFailed(options.pdfPath)
        }

        if options.printPrompt {
            for pageNumber in pageNumbers {
                let pageText = try extractPageText(document: document, pageNumber: pageNumber)
                let condensedText = condensePageText(pageText, maxChars: 2000)
                let mixText = extractSection(
                    text: pageText,
                    startMarkers: ["MIX"],
                    endMarkers: ["INSTRUCTIONS"]
                )
                let mixRowLines = extractMixRowLines(mixText)
                let extraChargesText = extractSection(
                    text: pageText,
                    startMarkers: ["EXTRA CHARGES"],
                    endMarkers: ["WATER CONTENT", "MATERIAL REQUIRED"]
                )
                let prompt = renderPrompt(
                    template: promptTemplate,
                    pdfPath: options.pdfPath,
                    page: pageNumber,
                    pageText: condensedText,
                    mixText: mixText,
                    mixRowLines: mixRowLines,
                    extraChargesText: extraChargesText
                )
                print(prompt)
                print("")
            }
            return
        }

        var tickets: [Ticket] = []
        let totalPages = pageNumbers.count
        var processedPages = 0
        var totalDuration: TimeInterval = 0
        updateProgress(current: processedPages, total: totalPages, averageSeconds: nil)
        for pageNumber in pageNumbers {
            let pageStart = Date()
            let pageText = try extractPageText(document: document, pageNumber: pageNumber)
            let condensedText = condensePageText(pageText, maxChars: 2000)
            let mixText = extractSection(
                text: pageText,
                startMarkers: ["MIX"],
                endMarkers: ["INSTRUCTIONS"]
            )
            let mixRowLines = extractMixRowLines(mixText)
            let extraChargesText = extractSection(
                text: pageText,
                startMarkers: ["EXTRA CHARGES"],
                endMarkers: ["WATER CONTENT", "MATERIAL REQUIRED"]
            )
            let prompt = renderPrompt(
                template: promptTemplate,
                pdfPath: options.pdfPath,
                page: pageNumber,
                pageText: condensedText,
                mixText: mixText,
                mixRowLines: mixRowLines,
                extraChargesText: extraChargesText
            )

            let modelResponse = try FoundationalModelsClient.run(prompt: prompt)
            let jsonObjects = splitJSONObjects(from: modelResponse)
            guard !jsonObjects.isEmpty else {
                throw ExtractError.noJSONFound
            }

            for json in jsonObjects {
                let ticket = try TicketValidator.decode(json: json)
                let normalizedTicket = TicketNormalizer.normalize(ticket: ticket)
                try TicketValidator.validate(ticket: normalizedTicket)
                tickets.append(normalizedTicket)
            }
            processedPages += 1
            totalDuration += Date().timeIntervalSince(pageStart)
            let averageSeconds = totalDuration / Double(processedPages)
            updateProgress(current: processedPages, total: totalPages, averageSeconds: averageSeconds)
        }
        finishProgress(totalDuration: totalDuration)

        let outputDir = expandingTilde(in: options.outputDir)
        try FileWriter.write(tickets: tickets, outputDir: outputDir)
    }

    private static func loadPromptTemplate() throws -> String {
        guard let url = Bundle.module.url(
            forResource: "prompt_template",
            withExtension: "txt"
        ) else {
            throw ExtractError.missingPromptTemplate
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func renderPrompt(
        template: String,
        pdfPath: String,
        page: Int,
        pageText: String,
        mixText: String,
        mixRowLines: String,
        extraChargesText: String
    ) -> String {
        let fileName = URL(fileURLWithPath: pdfPath).lastPathComponent
        var rendered = template
        rendered = rendered.replacingOccurrences(of: "<<FILE_NAME>>", with: fileName)
        rendered = rendered.replacingOccurrences(of: "<<PAGE_NUMBER>>", with: String(page))
        rendered = rendered.replacingOccurrences(of: "<<PDF_TEXT>>", with: pageText)
        rendered = rendered.replacingOccurrences(of: "<<MIX_TEXT>>", with: mixText)
        rendered = rendered.replacingOccurrences(of: "<<MIX_ROW_LINES>>", with: mixRowLines)
        rendered = rendered.replacingOccurrences(of: "<<EXTRA_CHARGES_TEXT>>", with: extraChargesText)
        return rendered
    }

    private static func splitJSONObjects(from text: String) -> [String] {
        var results: [String] = []
        var depth = 0
        var startIndex: String.Index?
        var inString = false
        var escapeNext = false

        for index in text.indices {
            let char = text[index]
            if escapeNext {
                escapeNext = false
                continue
            }

            if char == "\\" && inString {
                escapeNext = true
                continue
            }

            if char == "\"" {
                inString.toggle()
                continue
            }

            guard !inString else { continue }

            if char == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0, let start = startIndex {
                    let json = String(text[start...index])
                    results.append(json)
                    startIndex = nil
                }
            }
        }

        return results
    }

    private static func extractPageText(document: PDFDocument, pageNumber: Int) throws -> String {
        let pageCount = document.pageCount
        guard pageNumber >= 1 && pageNumber <= pageCount else {
            throw ExtractError.pageOutOfRange(pageNumber, pageCount)
        }
        guard let page = document.page(at: pageNumber - 1) else {
            throw ExtractError.pageOutOfRange(pageNumber, pageCount)
        }
        let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            throw ExtractError.emptyPageText(pageNumber)
        }
        return text
    }

    private static func expandingTilde(in path: String) -> String {
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        return path
    }

    private static func extractSection(
        text: String,
        startMarkers: [String],
        endMarkers: [String]
    ) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let normalizedLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }

        func containsMarker(_ line: String, markers: [String]) -> Bool {
            for marker in markers {
                if line.contains(marker.uppercased()) {
                    return true
                }
            }
            return false
        }

        var startIndex: Int?
        var endIndex: Int?
        for (index, line) in normalizedLines.enumerated() {
            if startIndex == nil, containsMarker(line, markers: startMarkers) {
                startIndex = index
                continue
            }
            if startIndex != nil, containsMarker(line, markers: endMarkers) {
                endIndex = index
                break
            }
        }

        guard let start = startIndex, let end = endIndex, end > start else {
            return ""
        }

        let slice = lines[(start + 1)..<end]
        return slice.joined(separator: "\n")
    }

    private static func extractMixRowLines(_ mixText: String) -> String {
        let headerTokens = [
            "MIX",
            "TERMS",
            "CONDITIONS",
            "ON LAST PAGE",
            "QTY",
            "CUST.",
            "CUST",
            "DESCR.",
            "DESCR",
            "DESCRIPTION",
            "CODE",
            "SLUMP"
        ]
        let lines = mixText.split(separator: "\n", omittingEmptySubsequences: false)
        var filtered: [String] = []
        var seen = Set<String>()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let upper = trimmed.uppercased()
            if headerTokens.contains(where: { upper == $0 || upper.contains($0) }) {
                continue
            }
            if !seen.insert(trimmed).inserted {
                continue
            }
            filtered.append(trimmed)
        }
        return filtered.joined(separator: "\n")
    }

    private static func condensePageText(_ text: String, maxChars: Int) -> String {
        let keywords = [
            "TICKET NO",
            "ORDER NO",
            "DELIVERY DATE",
            "DELIVERY TIME",
            "DELIVERY ADDR",
            "DELIVERY ADDR.",
            "CUSTOMER:",
            "CUSTOMER NO.",
            "JOBSITE",
            "ADDRESS:",
            "PO:",
            "ORDER",
            "VOLUME"
        ]

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var selected: [Substring] = []
        var carry = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let upper = trimmed.uppercased()
            if carry > 0 {
                selected.append(line)
                carry -= 1
                continue
            }
            if keywords.contains(where: { upper.contains($0) }) {
                selected.append(line)
                carry = 2
            }
        }

        var condensed = selected.joined(separator: "\n")
        if condensed.isEmpty {
            condensed = String(text.prefix(maxChars))
        }
        if condensed.count > maxChars {
            condensed = String(condensed.prefix(maxChars))
        }
        return condensed
    }

    private static func updateProgress(current: Int, total: Int, averageSeconds: TimeInterval?) {
        guard total > 0 else { return }
        let width = 24
        let fraction = Double(current) / Double(total)
        let filled = Int(round(fraction * Double(width)))
        let bar = String(repeating: "=", count: filled) + String(repeating: ".", count: max(0, width - filled))
        let percent = Int(round(fraction * 100.0))
        let etaText: String
        if let averageSeconds, current < total {
            let remaining = Double(total - current)
            etaText = " ETA \(format(seconds: averageSeconds * remaining))"
        } else {
            etaText = ""
        }
        let line = "\rProcessing pages [\(bar)] \(current)/\(total) (\(percent)%)\(etaText)"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    private static func finishProgress(totalDuration: TimeInterval) {
        if let data = "\n".data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
        let line = "Total time: \(format(seconds: totalDuration))\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    private static func format(seconds: TimeInterval) -> String {
        let clamped = max(0, Int(seconds.rounded()))
        let minutes = clamped / 60
        let seconds = clamped % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
