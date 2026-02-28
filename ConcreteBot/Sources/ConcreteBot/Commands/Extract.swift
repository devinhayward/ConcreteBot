import Foundation
import PDFKit

enum ExtractError: Error, CustomStringConvertible {
    case missingPromptTemplate
    case noJSONFound
    case invalidResponse(String)
    case missingResponseInput
    case invalidPageRange(String)
    case autoPageSelectionFailed(String)
    case pdfLoadFailed(String)
    case pageOutOfRange(Int, Int)
    case emptyPageText(Int)
    case responseOutputFailed(String)

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
        case .autoPageSelectionFailed(let detail):
            return "Auto page selection failed: \(detail)"
        case .pdfLoadFailed(let detail):
            return "Failed to load PDF: \(detail)"
        case .pageOutOfRange(let page, let total):
            return "Page \(page) is out of range (1-\(total))."
        case .emptyPageText(let page):
            return "No text extracted from page \(page)."
        case .responseOutputFailed(let detail):
            return "Failed to write response output: \(detail)"
        }
    }
}

enum Extract {
    static func run(options: CLIOptions) throws {
        let promptTemplate = try loadPromptTemplate(named: "prompt_template")
        let compactPromptTemplate = try loadPromptTemplate(named: "prompt_template_compact")
        let repairPromptTemplate = try loadPromptTemplate(named: "prompt_template_repair")

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

            let nonCriticalPaths: Set<String> = ["Delivery Date", "Delivery Time"]
            var tickets: [Ticket] = []
            for json in jsonObjects {
                let ticket = try TicketValidator.decode(json: json)
                let normalizedTicket = TicketNormalizer.normalize(ticket: ticket)
                try TicketValidator.validate(ticket: normalizedTicket, ignoringPaths: nonCriticalPaths)
                tickets.append(normalizedTicket)
            }

            let outputDir = expandingTilde(in: options.outputDir)
            try FileWriter.write(tickets: tickets, outputDir: outputDir)
            return
        }

        let pdfPath = expandingTilde(in: options.pdfPath)
        guard let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            throw ExtractError.pdfLoadFailed(pdfPath)
        }
        let pageNumbers: [Int]
        do {
            pageNumbers = try resolvePageNumbers(pages: options.pages, document: document, pdfPath: pdfPath)
        } catch let error as PageRangeError {
            throw ExtractError.invalidPageRange(error.description)
        }

        if options.printPrompt {
        for pageNumber in pageNumbers {
            let pageText = try extractPageText(document: document, pageNumber: pageNumber)
                let condensedText = condensePageText(pageText, maxChars: 800)
                let mixText = extractSection(
                    text: pageText,
                    startMarkers: ["MIX"],
                    endMarkers: ["INSTRUCTIONS"]
                )
                let mixRowLines = extractMixRowLines(mixText)
                let mixParsedHints = buildMixParsedHints(from: mixRowLines)
                let extraChargesText = extractSection(
                    text: pageText,
                    startMarkers: ["EXTRA CHARGES"],
                    endMarkers: ["WATER CONTENT", "MATERIAL REQUIRED"]
                )
                let prompt = renderPrompt(
                    template: promptTemplate,
                    compactTemplate: compactPromptTemplate,
                    pdfPath: pdfPath,
                    page: pageNumber,
                    pageText: condensedText,
                    mixText: mixText,
                    mixRowLines: mixRowLines,
                    mixParsedHints: mixParsedHints,
                    extraChargesText: extraChargesText
                )
                print(prompt)
                print("")
            }
            return
        }

        let nonCriticalPaths: Set<String> = ["Delivery Date", "Delivery Time"]
        var tickets: [Ticket] = []
        let totalPages = pageNumbers.count
        var processedPages = 0
        var totalDuration: TimeInterval = 0
        updateProgress(current: processedPages, total: totalPages, averageSeconds: nil)
        for pageNumber in pageNumbers {
            let pageStart = Date()
            let pageText = try extractPageText(document: document, pageNumber: pageNumber)
            let condensedText = condensePageText(pageText, maxChars: 800)
            let mixText = extractSection(
                text: pageText,
                startMarkers: ["MIX"],
                endMarkers: ["INSTRUCTIONS"]
            )
            let mixRowLines = extractMixRowLines(mixText)
            let mixParsedHints = buildMixParsedHints(from: mixRowLines)
            let extraChargesText = extractSection(
                text: pageText,
                startMarkers: ["EXTRA CHARGES"],
                endMarkers: ["WATER CONTENT", "MATERIAL REQUIRED"]
            )
            let prompt = renderPrompt(
                template: promptTemplate,
                compactTemplate: compactPromptTemplate,
                pdfPath: pdfPath,
                page: pageNumber,
                pageText: condensedText,
                mixText: mixText,
                mixRowLines: mixRowLines,
                mixParsedHints: mixParsedHints,
                extraChargesText: extraChargesText
            )

            let modelResponse = try FoundationalModelsClient.run(prompt: prompt)
            if let responseOut = options.responseOut {
                do {
                    try writeResponseOut(modelResponse, outputPath: responseOut)
                } catch {
                    throw ExtractError.responseOutputFailed(error.localizedDescription)
                }
            }
            let jsonObjects = splitJSONObjects(from: modelResponse)
            guard !jsonObjects.isEmpty else {
                throw ExtractError.noJSONFound
            }

            for json in jsonObjects {
                let ticket = try TicketValidator.decode(json: json)
                let hintedTicket = applyMixParsedHints(ticket: ticket, mixParsedHints: mixParsedHints)
                let mergedTicket = mergeExtraCharges(from: extraChargesText, ticket: hintedTicket)
                let normalizedTicket = TicketNormalizer.normalize(ticket: mergedTicket)
                let issues = TicketValidator.issues(ticket: normalizedTicket)
                let criticalIssues = issues.filter { issue in
                    !nonCriticalPaths.contains(issue.path)
                }
                if criticalIssues.isEmpty {
                    try TicketValidator.validate(ticket: normalizedTicket, ignoringPaths: nonCriticalPaths)
                    tickets.append(normalizedTicket)
                    continue
                }

                if let repairedTicket = try attemptRepair(
                    template: repairPromptTemplate,
                    pdfPath: pdfPath,
                    page: pageNumber,
                    pageText: condensedText,
                    mixText: mixText,
                    mixRowLines: mixRowLines,
                    mixParsedHints: mixParsedHints,
                    extraChargesText: extraChargesText,
                    baseTicket: mergedTicket,
                    issues: criticalIssues
                ) {
                    let normalizedRepaired = TicketNormalizer.normalize(ticket: repairedTicket)
                    try TicketValidator.validate(ticket: normalizedRepaired, ignoringPaths: nonCriticalPaths)
                    tickets.append(normalizedRepaired)
                } else {
                    throw TicketValidationError.invalidFields(criticalIssues)
                }
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

    static func processPageForTest(
        pageText: String,
        pdfPath: String = "fixture.pdf",
        page: Int = 1,
        modelResponse: String
    ) throws -> [Ticket] {
        let normalizedPageText = normalizePageText(pageText)
        let mixText = extractSection(
            text: normalizedPageText,
            startMarkers: ["MIX"],
            endMarkers: ["INSTRUCTIONS"]
        )
        let mixRowLines = extractMixRowLines(mixText)
        let mixParsedHints = buildMixParsedHints(from: mixRowLines)
        let extraChargesText = extractSection(
            text: normalizedPageText,
            startMarkers: ["EXTRA CHARGES"],
            endMarkers: ["WATER CONTENT", "MATERIAL REQUIRED"]
        )

        let jsonObjects = splitJSONObjects(from: modelResponse)
        guard !jsonObjects.isEmpty else {
            throw ExtractError.noJSONFound
        }

        var tickets: [Ticket] = []
        for json in jsonObjects {
            let ticket = try TicketValidator.decode(json: json)
            let hintedTicket = applyMixParsedHints(ticket: ticket, mixParsedHints: mixParsedHints)
            let mergedTicket = mergeExtraCharges(from: extraChargesText, ticket: hintedTicket)
            let normalizedTicket = TicketNormalizer.normalize(ticket: mergedTicket)
            try TicketValidator.validate(ticket: normalizedTicket)
            tickets.append(normalizedTicket)
        }
        return tickets
    }

    private static func loadPromptTemplate(named name: String) throws -> String {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "txt"
        ) else {
            throw ExtractError.missingPromptTemplate
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private struct PromptSections {
        var pageText: String
        var mixText: String
        var mixRowLines: String
        var mixParsedHints: String
        var extraChargesText: String
    }

    private static func renderPrompt(
        template: String,
        compactTemplate: String,
        pdfPath: String,
        page: Int,
        pageText: String,
        mixText: String,
        mixRowLines: String,
        mixParsedHints: String,
        extraChargesText: String
    ) -> String {
        let fileName = URL(fileURLWithPath: pdfPath).lastPathComponent
        let maxSectionChars = 800
        let maxExtraChargesChars = 2400
        let condensedExtraChargesText = condenseExtraChargesText(extraChargesText)
        let baseSections = PromptSections(
            pageText: truncateSection(pageText, maxChars: maxSectionChars),
            mixText: truncateSection(mixText, maxChars: maxSectionChars),
            mixRowLines: truncateSection(mixRowLines, maxChars: maxSectionChars),
            mixParsedHints: truncateSection(mixParsedHints, maxChars: maxSectionChars),
            extraChargesText: truncateSection(condensedExtraChargesText, maxChars: maxExtraChargesChars)
        )
        let maxPromptChars = 9000

        func buildPrompt(template: String, sections: PromptSections) -> String {
            var rendered = template
            rendered = rendered.replacingOccurrences(of: "<<FILE_NAME>>", with: fileName)
            rendered = rendered.replacingOccurrences(of: "<<PAGE_NUMBER>>", with: String(page))
            rendered = rendered.replacingOccurrences(of: "<<PDF_TEXT>>", with: sections.pageText)
            rendered = rendered.replacingOccurrences(of: "<<MIX_TEXT>>", with: sections.mixText)
            rendered = rendered.replacingOccurrences(of: "<<MIX_ROW_LINES>>", with: sections.mixRowLines)
            rendered = rendered.replacingOccurrences(of: "<<MIX_PARSED_HINTS>>", with: sections.mixParsedHints)
            rendered = rendered.replacingOccurrences(of: "<<EXTRA_CHARGES_TEXT>>", with: sections.extraChargesText)
            return rendered
        }

        func renderWithTemplate(
            _ template: String,
            sections: PromptSections,
            minPageText: Int,
            minMixText: Int,
            minExtraCharges: Int
        ) -> String {
            var sections = sections
            var rendered = buildPrompt(template: template, sections: sections)
            if rendered.count <= maxPromptChars {
                return rendered
            }
            var overage = rendered.count - maxPromptChars
            shrinkSection(&sections.mixText, overage: &overage, minChars: minMixText)
            shrinkSection(&sections.pageText, overage: &overage, minChars: minPageText)
            shrinkSection(&sections.extraChargesText, overage: &overage, minChars: minExtraCharges)
            rendered = buildPrompt(template: template, sections: sections)
            return rendered
        }

        let fullRendered = renderWithTemplate(
            template,
            sections: baseSections,
            minPageText: 400,
            minMixText: 200,
            minExtraCharges: 600
        )
        if fullRendered.count <= maxPromptChars {
            return fullRendered
        }

        var compactRendered = renderWithTemplate(
            compactTemplate,
            sections: baseSections,
            minPageText: 300,
            minMixText: 0,
            minExtraCharges: 800
        )
        if compactRendered.count > maxPromptChars {
            var tighterSections = baseSections
            tighterSections.mixText = ""
            compactRendered = renderWithTemplate(
                compactTemplate,
                sections: tighterSections,
                minPageText: 200,
                minMixText: 0,
                minExtraCharges: 600
            )
        }

        return compactRendered
    }

    private static func renderRepairPrompt(
        template: String,
        pdfPath: String,
        page: Int,
        pageText: String,
        mixText: String,
        mixRowLines: String,
        mixParsedHints: String,
        extraChargesText: String,
        currentJSON: String,
        validationErrors: String
    ) -> String {
        let fileName = URL(fileURLWithPath: pdfPath).lastPathComponent
        let maxSectionChars = 800
        let maxExtraChargesChars = 2400
        let condensedExtraChargesText = condenseExtraChargesText(extraChargesText)
        let baseSections = PromptSections(
            pageText: truncateSection(pageText, maxChars: maxSectionChars),
            mixText: truncateSection(mixText, maxChars: maxSectionChars),
            mixRowLines: truncateSection(mixRowLines, maxChars: maxSectionChars),
            mixParsedHints: truncateSection(mixParsedHints, maxChars: maxSectionChars),
            extraChargesText: truncateSection(condensedExtraChargesText, maxChars: maxExtraChargesChars)
        )
        let maxPromptChars = 9000

        func buildPrompt(sections: PromptSections, currentJSON: String, validationErrors: String) -> String {
            var rendered = template
            rendered = rendered.replacingOccurrences(of: "<<FILE_NAME>>", with: fileName)
            rendered = rendered.replacingOccurrences(of: "<<PAGE_NUMBER>>", with: String(page))
            rendered = rendered.replacingOccurrences(of: "<<PDF_TEXT>>", with: sections.pageText)
            rendered = rendered.replacingOccurrences(of: "<<MIX_TEXT>>", with: sections.mixText)
            rendered = rendered.replacingOccurrences(of: "<<MIX_ROW_LINES>>", with: sections.mixRowLines)
            rendered = rendered.replacingOccurrences(of: "<<MIX_PARSED_HINTS>>", with: sections.mixParsedHints)
            rendered = rendered.replacingOccurrences(of: "<<EXTRA_CHARGES_TEXT>>", with: sections.extraChargesText)
            rendered = rendered.replacingOccurrences(of: "<<CURRENT_JSON>>", with: currentJSON)
            rendered = rendered.replacingOccurrences(of: "<<VALIDATION_ERRORS>>", with: validationErrors)
            return rendered
        }

        var sections = baseSections
        var rendered = buildPrompt(
            sections: sections,
            currentJSON: currentJSON,
            validationErrors: validationErrors
        )
        if rendered.count <= maxPromptChars {
            return rendered
        }

        var overage = rendered.count - maxPromptChars
        shrinkSection(&sections.mixText, overage: &overage, minChars: 200)
        shrinkSection(&sections.pageText, overage: &overage, minChars: 300)
        shrinkSection(&sections.extraChargesText, overage: &overage, minChars: 600)
        rendered = buildPrompt(
            sections: sections,
            currentJSON: currentJSON,
            validationErrors: validationErrors
        )
        return rendered
    }

    private static func truncateSection(_ text: String, maxChars: Int) -> String {
        guard maxChars > 0 else { return "" }
        guard text.count > maxChars else { return text }
        return truncateToBoundary(text, limit: maxChars)
    }

    private static func attemptRepair(
        template: String,
        pdfPath: String,
        page: Int,
        pageText: String,
        mixText: String,
        mixRowLines: String,
        mixParsedHints: String,
        extraChargesText: String,
        baseTicket: Ticket,
        issues: [TicketValidationIssue]
    ) throws -> Ticket? {
        let currentJSON = encodeTicketForPrompt(baseTicket)
        let validationErrors = formatValidationErrors(issues)
        let prompt = renderRepairPrompt(
            template: template,
            pdfPath: pdfPath,
            page: page,
            pageText: pageText,
            mixText: mixText,
            mixRowLines: mixRowLines,
            mixParsedHints: mixParsedHints,
            extraChargesText: extraChargesText,
            currentJSON: currentJSON,
            validationErrors: validationErrors
        )

        let response = try FoundationalModelsClient.run(prompt: prompt)
        let jsonObjects = splitJSONObjects(from: response)
        guard let repairJSON = jsonObjects.first else {
            throw ExtractError.invalidResponse("No JSON object found in repair response.")
        }
        return try applyRepairPatch(baseTicket: baseTicket, patchJSON: repairJSON)
    }

    private static func encodeTicketForPrompt(_ ticket: Ticket) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(ticket),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private static func formatValidationErrors(_ issues: [TicketValidationIssue]) -> String {
        if issues.isEmpty {
            return "None"
        }
        return issues.map { "- \($0.path): \($0.message)" }.joined(separator: "\n")
    }

    private static func applyRepairPatch(baseTicket: Ticket, patchJSON: String) throws -> Ticket {
        let baseDict = try ticketDictionary(from: baseTicket)
        let patchObject = try jsonObject(from: patchJSON)
        guard let patchDict = patchObject as? [String: Any] else {
            throw ExtractError.invalidResponse("Repair response must be a JSON object.")
        }
        let merged = mergeDictionaries(baseDict, patchDict)
        let data = try JSONSerialization.data(withJSONObject: merged, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw ExtractError.invalidResponse("Failed to encode repaired JSON.")
        }
        return try TicketValidator.decode(json: json)
    }

    private static func ticketDictionary(from ticket: Ticket) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(ticket)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = object as? [String: Any] else {
            throw ExtractError.invalidResponse("Failed to convert ticket to JSON dictionary.")
        }
        return dict
    }

    private static func jsonObject(from text: String) throws -> Any {
        guard let data = text.data(using: .utf8) else {
            throw ExtractError.invalidResponse("Repair response is not valid UTF-8.")
        }
        return try JSONSerialization.jsonObject(with: data, options: [])
    }

    private static func mergeDictionaries(_ base: [String: Any], _ patch: [String: Any]) -> [String: Any] {
        var result = base
        for (key, patchValue) in patch {
            if let patchDict = patchValue as? [String: Any],
               let baseDict = result[key] as? [String: Any] {
                result[key] = mergeDictionaries(baseDict, patchDict)
            } else {
                result[key] = patchValue
            }
        }
        return result
    }

    private static func shrinkSection(_ text: inout String, overage: inout Int, minChars: Int) {
        guard overage > 0 else { return }
        let minChars = max(0, minChars)
        let available = max(0, text.count - minChars)
        guard available > 0 else { return }
        let trimAmount = min(overage, available)
        let target = text.count - trimAmount
        let originalCount = text.count
        text = truncateToBoundary(text, limit: target)
        let actualTrim = max(0, originalCount - text.count)
        overage = max(0, overage - actualTrim)
    }

    private static func truncateToBoundary(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.count > limit else { return text }
        let prefix = String(text.prefix(limit))
        if let range = prefix.range(of: "\n", options: .backwards) {
            return String(prefix[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func condenseExtraChargesText(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var cleaned: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if isExtraChargesHeaderLine(trimmed) {
                continue
            }
            cleaned.append(trimmed)
        }

        var merged: [String] = []
        var index = 0
        while index < cleaned.count {
            let line = cleaned[index]
            if isQtyOnlyLine(line) {
                let qty = line
                if index + 1 < cleaned.count {
                    let next = cleaned[index + 1]
                    if !next.hasPrefix(qty),
                       !next.contains(qty),
                       containsLetters(next) {
                        merged.append("\(qty) \(next)")
                        index += 2
                        continue
                    }
                }
            }
            merged.append(line)
            index += 1
        }

        var result: [String] = []
        var seen = Set<String>()
        for line in merged {
            let normalized = normalizeExtraChargeLine(line)
            if seen.insert(normalized).inserted {
                result.append(line)
            }
        }

        return result.joined(separator: "\n")
    }

    private static func mergeExtraCharges(from text: String, ticket: Ticket) -> Ticket {
        let parsedCharges = parseExtraCharges(from: text)
        guard !parsedCharges.isEmpty else { return ticket }

        let existingCharges = ticket.extraCharges
        var seenKeys = Set<String>()
        var merged: [ExtraCharge] = []

        for charge in parsedCharges {
            let key = extraChargeKey(charge)
            if seenKeys.insert(key).inserted {
                merged.append(charge)
            }
        }

        for charge in existingCharges {
            let key = extraChargeKey(charge)
            if seenKeys.insert(key).inserted {
                merged.append(charge)
            }
        }

        return Ticket(
            ticketNumber: ticket.ticketNumber,
            deliveryDate: ticket.deliveryDate,
            deliveryTime: ticket.deliveryTime,
            deliveryAddress: ticket.deliveryAddress,
            mixCustomer: ticket.mixCustomer,
            mixAdditional1: ticket.mixAdditional1,
            mixAdditional2: ticket.mixAdditional2,
            extraCharges: merged
        )
    }

    private static func parseExtraCharges(from text: String) -> [ExtraCharge] {
        let condensed = condenseExtraChargesText(text)
        let lines = condensed.split(separator: "\n", omittingEmptySubsequences: true)
        var charges: [ExtraCharge] = []
        var seen = Set<String>()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let (qty, desc) = splitLeadingNumber(from: trimmed) else { continue }
            guard containsLetters(desc) else { continue }
            let charge = ExtraCharge(description: desc, qty: qty)
            let key = extraChargeKey(charge)
            if seen.insert(key).inserted {
                charges.append(charge)
            }
        }

        return charges
    }

    private static func isExtraChargesHeaderLine(_ line: String) -> Bool {
        let upper = line.uppercased()
        if upper.contains("EXTRA CHARGES") || upper.contains("EXTRA-CHARGES") {
            return true
        }
        if upper.contains("QTY") && upper.contains("DESCRIPTION") {
            return true
        }
        return false
    }

    private static func isQtyOnlyLine(_ line: String) -> Bool {
        matches(line, pattern: #"^\s*\d+(?:\.\d+)?\s*$"#)
    }

    private static func containsLetters(_ line: String) -> Bool {
        line.rangeOfCharacter(from: CharacterSet.letters) != nil
    }

    private static func isIgnoredMixLine(_ line: String) -> Bool {
        let upper = line.uppercased()
        if upper.hasPrefix("ADDRESS") {
            return true
        }
        if upper.hasPrefix("TICKET NO") {
            return true
        }
        if upper.hasPrefix("PLANT NO") {
            return true
        }
        if upper.hasPrefix("CERTIFICATE") {
            return true
        }
        return false
    }

    private static func mergeSpecFragments(_ parts: [String]) -> [String] {
        guard parts.count > 1 else { return parts }
        var result: [String] = []
        var index = 0
        while index < parts.count {
            let current = parts[index]
            if index + 1 < parts.count {
                let next = parts[index + 1]
                if isAlphaToken(current), isAlphaToken(next),
                   current.count <= 8, next.count <= 6 {
                    result.append(current + next)
                    index += 2
                    continue
                }
            }
            result.append(current)
            index += 1
        }
        return result
    }

    private static func orderSpecParts(_ parts: [String]) -> [String] {
        guard parts.count > 1 else { return parts }
        let decorated = parts.enumerated().map { (index, value) -> (Int, Int, String) in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let upper = trimmed.uppercased()
            let first = trimmed.first
            let category: Int
            if upper.contains("WEATHERMIX") {
                category = 0
            } else if let first, first.isLetter {
                category = 1
            } else if let first, first.isNumber {
                category = 2
            } else {
                category = 3
            }
            return (category, index, value)
        }
        return decorated.sorted { (lhs, rhs) in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            return lhs.1 < rhs.1
        }.map { $0.2 }
    }

    private static func isAlphaToken(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.allSatisfy { $0.isLetter }
    }

    private static func normalizeExtraChargeLine(_ line: String) -> String {
        let upper = line.uppercased()
        let collapsed = upper.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed
    }

    private static func extraChargeKey(_ charge: ExtraCharge) -> String {
        let qty = charge.qty?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let description = charge.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedDescription = normalizeExtraChargeDescription(description, qty: qty)
        let normalized = normalizeExtraChargeLine(normalizedDescription)
        return "\(qty)|\(normalized)"
    }

    private static func normalizeExtraChargeDescription(_ description: String, qty: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let qtyNumeric = numericPrefix(in: qty) else { return trimmed }
        if let (number, remainder) = splitLeadingNumber(from: trimmed),
           number == qtyNumeric {
            return remainder
        }
        return trimmed
    }

    private static func numericPrefix(in value: String) -> String? {
        let pattern = #"\d+(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = regex.firstMatch(in: value, range: range) else { return nil }
        guard let matchRange = Range(match.range, in: value) else { return nil }
        return String(value[matchRange])
    }

    private static func splitLeadingNumber(from value: String) -> (String, String)? {
        let pattern = #"^\s*(\d+(?:\.\d+)?)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = regex.firstMatch(in: value, range: range) else { return nil }
        guard match.numberOfRanges >= 3,
              let numberRange = Range(match.range(at: 1), in: value),
              let remainderRange = Range(match.range(at: 2), in: value) else {
            return nil
        }
        let number = String(value[numberRange])
        let remainder = String(value[remainderRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (number, remainder)
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

    private static func resolvePageNumbers(
        pages: String,
        document: PDFDocument,
        pdfPath: String
    ) throws -> [Int] {
        let trimmed = pages.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        if normalized == "auto" {
            return try autoSelectPages(document: document, pdfPath: pdfPath)
        }
        return try PageRange.parse(trimmed)
    }

    private static func autoSelectPages(
        document: PDFDocument,
        pdfPath: String
    ) throws -> [Int] {
        let pageCount = document.pageCount
        var scored: [(page: Int, score: Int)] = []
        var pagesWithText: [Int] = []

        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { continue }
            let pageNumber = index + 1
            pagesWithText.append(pageNumber)
            let score = scorePageText(text)
            if score > 0 {
                scored.append((page: pageNumber, score: score))
            }
        }

        guard !pagesWithText.isEmpty else {
            throw ExtractError.autoPageSelectionFailed("No text found in PDF: \(pdfPath)")
        }

        guard let maxScore = scored.map({ $0.score }).max() else {
            return pagesWithText
        }

        let threshold = max(3, maxScore - 2)
        let selected = scored.filter { $0.score >= threshold }.map { $0.page }
        return selected.isEmpty ? pagesWithText : selected
    }

    private static func scorePageText(_ text: String) -> Int {
        let upper = text.uppercased()
        let ticketMarkers = [
            "TICKET NO",
            "TICKET NUMBER",
            "TICKET #"
        ]
        let deliveryMarkers = [
            "DELIVERY DATE",
            "DELIVERY TIME",
            "DELIVERY ADDR",
            "DELIVERY ADDRESS",
            "JOBSITE",
            "CUSTOMER",
            "ORDER NO",
            "ORDER #"
        ]
        let mixMarkers = [
            "MIX",
            "SLUMP",
            "MPA",
            "EXTRA CHARGES",
            "PLANT NO"
        ]

        var score = 0
        if containsAny(upper, markers: ticketMarkers) {
            score += 4
        }
        for marker in deliveryMarkers where upper.contains(marker) {
            score += 1
        }
        for marker in mixMarkers where upper.contains(marker) {
            score += 1
        }
        return score
    }

    private static func containsAny(_ text: String, markers: [String]) -> Bool {
        for marker in markers {
            if text.contains(marker) {
                return true
            }
        }
        return false
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
        return normalizePageText(text)
    }

    static func expandingTilde(in path: String) -> String {
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        return path
    }

    private static func normalizePageText(_ text: String) -> String {
        let normalizedLineBreaks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedLineBreaks.split(separator: "\n", omittingEmptySubsequences: false)
        let normalizedLines = lines.map { normalizeLine(String($0)) }
        return normalizedLines.joined(separator: "\n")
    }

    private static func normalizeLine(_ line: String) -> String {
        var cleaned = line.replacingOccurrences(of: "\t", with: " ")
        cleaned = normalizeDecimalDots(in: cleaned)
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })
        let normalizedTokens = tokens.map { normalizeToken(String($0)) }
        return normalizedTokens.joined(separator: " ")
    }

    private static func normalizeDecimalDots(in text: String) -> String {
        let pattern = #"(\\d)\\s*\\.(?:\\s*\\.)+(\\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1.$2")
    }

    private static func normalizeToken(_ token: String) -> String {
        guard shouldCollapseDuplicatedLetters(token) else { return token }
        return collapseDuplicateRuns(token)
    }

    private static func shouldCollapseDuplicatedLetters(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        let letterSet = CharacterSet.letters
        guard token.rangeOfCharacter(from: letterSet.inverted) == nil else {
            return false
        }
        let chars = Array(token)
        if hasRun(of: 3, in: chars) {
            return true
        }
        let pairCount = chars.count / 2
        guard pairCount >= 3 else { return false }
        var matchingPairs = 0
        for index in stride(from: 0, to: pairCount * 2, by: 2) {
            let left = String(chars[index]).uppercased()
            let right = String(chars[index + 1]).uppercased()
            if left == right {
                matchingPairs += 1
            }
        }
        return matchingPairs >= pairCount - 1
    }

    private static func hasRun(of length: Int, in chars: [Character]) -> Bool {
        guard length > 1 else { return false }
        var currentCount = 1
        var previousUpper: String?
        for char in chars {
            let upper = String(char).uppercased()
            if previousUpper == nil {
                previousUpper = upper
                currentCount = 1
                continue
            }
            if previousUpper == upper {
                currentCount += 1
                if currentCount >= length {
                    return true
                }
            } else {
                previousUpper = upper
                currentCount = 1
            }
        }
        return false
    }

    private static func collapseDuplicateRuns(_ token: String) -> String {
        var result = ""
        result.reserveCapacity(token.count)
        var previousUpper: String?
        for char in token {
            let upper = String(char).uppercased()
            if previousUpper == upper {
                continue
            }
            result.append(char)
            previousUpper = upper
        }
        return result
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
        let headerWords: Set<String> = [
            "MIX",
            "TABLE",
            "TERMS",
            "CONDITIONS",
            "ON",
            "LAST",
            "PAGE",
            "QTY",
            "CUST",
            "DESCR",
            "DESCRIPTION",
            "CODE",
            "SLUMP",
            "PLANT",
            "CERTIFICATE",
            "ADDRESS",
            "TICKET",
            "NO"
        ]
        func isHeaderLine(_ line: String) -> Bool {
            let cleaned = line.uppercased().replacingOccurrences(
                of: #"[^A-Z0-9]+"#,
                with: " ",
                options: .regularExpression
            )
            let tokens = cleaned.split(whereSeparator: { $0.isWhitespace })
            guard !tokens.isEmpty else { return false }
            return tokens.allSatisfy { headerWords.contains(String($0)) }
        }
        let lines = mixText.split(separator: "\n", omittingEmptySubsequences: false)
        var filtered: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if isHeaderLine(trimmed) {
                continue
            }
            filtered.append(trimmed)
        }

        guard let startIndex = firstMixDataIndex(in: filtered) else {
            return ""
        }
        let mixLines = filtered[startIndex...]
        return mixLines.joined(separator: "\n")
    }

    private struct MixParsedHintRow {
        var qty: String
        var code: String
        var slump: String
        var spec: String
    }

    private static func buildMixParsedHints(from mixRowLines: String) -> String {
        let rawLines = mixRowLines.split(separator: "\n", omittingEmptySubsequences: true)
        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return formatMixParsedHints([MixParsedHintRow(qty: "", code: "", slump: "", spec: "")])
        }

        let cubeSymbol = "\u{00B3}"
        let strengthTagPattern = #"^[A-Z]{1,3}\s*\d+\s*MPA$"#
        let qtyPattern = #"(\d+(?:\.\d+)?)\s*(m3|m³)"#
        let codePattern = #"\b([A-Z]{2,}[A-Z0-9]*\d[A-Z0-9]*)\b"#
        let slumpPattern = #"\b\d+(?:\.\d+)?\s*\+\-\s*\d+(?:\.\d+)?\b"#

        let rows = splitMixRows(lines, qtyPattern: qtyPattern, cubeSymbol: cubeSymbol)
        let targetRows = rows.isEmpty ? [lines] : rows

        var hints = targetRows.prefix(3).enumerated().map { index, rowLines in
            parseRowHints(
                lines: rowLines,
                qtyPattern: qtyPattern,
                codePattern: codePattern,
                slumpPattern: slumpPattern,
                strengthTagPattern: strengthTagPattern,
                cubeSymbol: cubeSymbol,
                rowIndex: index
            )
        }
        supplementRowHints(
            &hints,
            allLines: lines,
            codePattern: codePattern,
            slumpPattern: slumpPattern,
            cubeSymbol: cubeSymbol
        )
        return formatMixParsedHints(hints)
    }

    private static func splitMixRows(
        _ lines: [String],
        qtyPattern: String,
        cubeSymbol: String
    ) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []

        for line in lines {
            let normalized = line.replacingOccurrences(of: cubeSymbol, with: "3")
            let isQtyLine = matches(normalized, pattern: qtyPattern)
            if isQtyLine {
                if !current.isEmpty {
                    rows.append(current)
                }
                current = [line]
            } else if !current.isEmpty {
                current.append(line)
            }
        }

        if !current.isEmpty {
            rows.append(current)
        }

        return rows
    }

    private static func parseRowHints(
        lines: [String],
        qtyPattern: String,
        codePattern: String,
        slumpPattern: String,
        strengthTagPattern: String,
        cubeSymbol: String,
        rowIndex: Int
    ) -> MixParsedHintRow {
        let numericCodePattern = #"\b\d{5,}\b"#
        var qty: String?
        var code: String?
        var slump: String?
        var specParts: [String] = []
        var strengthTags: [String] = []
        var seenSpec = Set<String>()

        for line in lines {
            let normalized = line.replacingOccurrences(of: cubeSymbol, with: "3")
            let upper = normalized.uppercased()

            if qty == nil, let match = firstMatch(in: normalized, pattern: qtyPattern) {
                let number = match[1]
                let unit = match[2].contains(cubeSymbol) ? "m³" : "m3"
                qty = "\(number) \(unit)"
            }

            let lineCodeToken = firstMatch(in: upper, pattern: codePattern).flatMap { match -> String? in
                guard match.count > 1 else { return nil }
                return match[1]
            }
            if code == nil, let token = lineCodeToken, !(rowIndex > 0 && isCustomerMixCode(token)) {
                code = token
            } else if code == nil, rowIndex == 0, let match = firstMatch(in: normalized, pattern: numericCodePattern) {
                code = match[0]
            } else if code == nil, rowIndex == 0, let numericCode = digitsOnlyCode(from: line) {
                code = numericCode
            }

            if slump == nil {
                if rowIndex > 0, let token = lineCodeToken, isCustomerMixCode(token) {
                    continue
                }
                if let match = firstMatch(in: normalized, pattern: slumpPattern) {
                    slump = match[0].replacingOccurrences(of: " ", with: "")
                }
            }

            if matches(line, pattern: strengthTagPattern) {
                strengthTags.append(line)
                continue
            }

            if isIgnoredMixLine(line) {
                continue
            }

            let candidate = stripLeadingQty(line)
            guard !candidate.isEmpty else { continue }
            let candidateUpper = candidate.uppercased()
            let candidateHasCode = matches(candidateUpper, pattern: codePattern)
                || matches(candidate, pattern: numericCodePattern)
                || digitsOnlyCode(from: candidate) != nil
            let candidateHasSlump = matches(candidate, pattern: slumpPattern)
            if candidateHasCode || candidateHasSlump {
                let cleaned = stripMixSpecCandidate(
                    candidate,
                    codePattern: codePattern,
                    numericCodePattern: numericCodePattern,
                    slumpPattern: slumpPattern
                )
                guard let cleaned = trimmedNonEmpty(cleaned) else { continue }
                let cleanedUpper = cleaned.uppercased()
                if rowIndex > 0, isCustomerSpecLine(cleanedUpper) {
                    continue
                }
                let isSpec = isCustomerSpecLine(cleanedUpper) || containsLetters(cleaned)
                if isSpec && seenSpec.insert(cleaned).inserted {
                    specParts.append(cleaned)
                }
            } else {
                if rowIndex > 0, isCustomerSpecLine(candidateUpper) {
                    continue
                }

                let isSpec = isCustomerSpecLine(candidateUpper) || containsLetters(candidate)
                if isSpec && seenSpec.insert(candidate).inserted {
                    specParts.append(candidate)
                }
            }
        }

        if specParts.isEmpty, let fallback = strengthTags.first {
            specParts = [fallback]
        }

        let merged = mergeSpecFragments(specParts)
        let ordered = orderSpecParts(merged)
        let spec = dedupeSpecParts(ordered).joined(separator: " ")
        return MixParsedHintRow(qty: qty ?? "", code: code ?? "", slump: slump ?? "", spec: spec)
    }

    private static func supplementRowHints(
        _ hints: inout [MixParsedHintRow],
        allLines: [String],
        codePattern: String,
        slumpPattern: String,
        cubeSymbol: String
    ) {
        guard !hints.isEmpty else { return }
        let numericCodePattern = #"\b\d{5,}\b"#
        var alphaCodes: [String] = []
        var numericCodes: [String] = []
        var slumps: [String] = []
        var seenAlpha = Set<String>()
        var seenNumeric = Set<String>()
        var seenSlumps = Set<String>()

        for line in allLines {
            if isIgnoredMixLine(line) {
                continue
            }
            let normalized = line.replacingOccurrences(of: cubeSymbol, with: "3")
            let upper = normalized.uppercased()
            if let match = firstMatch(in: upper, pattern: codePattern) {
                let code = match[1]
                if seenAlpha.insert(code).inserted {
                    alphaCodes.append(code)
                }
            }
            for match in allMatches(in: normalized, pattern: numericCodePattern) {
                if seenNumeric.insert(match).inserted {
                    numericCodes.append(match)
                }
            }
            for match in allMatches(in: normalized, pattern: slumpPattern) {
                let slumpValue = match.replacingOccurrences(of: " ", with: "")
                if seenSlumps.insert(slumpValue).inserted {
                    slumps.append(slumpValue)
                }
            }
        }

        if trimmedNonEmpty(hints[0].code) == nil, let code = alphaCodes.first {
            hints[0].code = code
        }
        if trimmedNonEmpty(hints[0].slump) == nil, let slump = slumps.first {
            hints[0].slump = slump
        }

        var numericIndex = 0
        for rowIndex in 1..<hints.count {
            if trimmedNonEmpty(hints[rowIndex].code) == nil, numericIndex < numericCodes.count {
                hints[rowIndex].code = numericCodes[numericIndex]
                numericIndex += 1
            }
        }
    }

    private static func formatMixParsedHints(_ hints: [MixParsedHintRow]) -> String {
        var lines: [String] = []
        for (index, hint) in hints.enumerated() {
            lines.append("Row \(index + 1):")
            lines.append("Qty: \(hint.qty)")
            lines.append("Code: \(hint.code)")
            lines.append("Slump: \(hint.slump)")
            lines.append("Spec: \(hint.spec)")
        }
        return lines.joined(separator: "\n")
    }

    private static func applyMixParsedHints(ticket: Ticket, mixParsedHints: String) -> Ticket {
        let rows = parseMixParsedHints(mixParsedHints)
        if rows.isEmpty {
            return ticket
        }

        var mixCustomer = ticket.mixCustomer
        if let customer = rows.first {
            let hintSpec = sanitizeHintSpec(customer.spec)
            let hintQty = trimmedNonEmpty(customer.qty)
            let hintCode = trimmedNonEmpty(customer.code)
            let hintSlump = trimmedNonEmpty(customer.slump)
            if shouldUseHint(existing: mixCustomer.customerDescription, hint: hintSpec) {
                mixCustomer = MixRow(
                    qty: mixCustomer.qty,
                    customerDescription: hintSpec,
                    description: mixCustomer.description,
                    code: mixCustomer.code,
                    slump: mixCustomer.slump
                )
            }
            if shouldUseHint(existing: mixCustomer.description, hint: hintSpec) {
                mixCustomer = MixRow(
                    qty: mixCustomer.qty,
                    customerDescription: mixCustomer.customerDescription,
                    description: hintSpec,
                    code: mixCustomer.code,
                    slump: mixCustomer.slump
                )
            }
            if mixCustomer.qty?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true, let hintQty {
                mixCustomer = MixRow(
                    qty: hintQty,
                    customerDescription: mixCustomer.customerDescription,
                    description: mixCustomer.description,
                    code: mixCustomer.code,
                    slump: mixCustomer.slump
                )
            }
            if mixCustomer.code?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true, let hintCode {
                mixCustomer = MixRow(
                    qty: mixCustomer.qty,
                    customerDescription: mixCustomer.customerDescription,
                    description: mixCustomer.description,
                    code: hintCode,
                    slump: mixCustomer.slump
                )
            }
            if mixCustomer.slump?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true, let hintSlump {
                mixCustomer = MixRow(
                    qty: mixCustomer.qty,
                    customerDescription: mixCustomer.customerDescription,
                    description: mixCustomer.description,
                    code: mixCustomer.code,
                    slump: hintSlump
                )
            }
        }

        let customerCode = trimmedNonEmpty(mixCustomer.code)
        let customerSlump = trimmedNonEmpty(mixCustomer.slump)

        var mixAdditional1 = ticket.mixAdditional1
        if rows.count > 1 {
            let additional = rows[1]
            let qty = trimmedNonEmpty(additional.qty)
            let code = trimmedNonEmpty(additional.code)
            let slump = trimmedNonEmpty(additional.slump)
            let description = sanitizeHintSpec(additional.spec)
            if mixAdditional1 == nil, qty != nil || code != nil || slump != nil || description != nil {
                mixAdditional1 = MixRow(
                    qty: qty,
                    customerDescription: nil,
                    description: description,
                    code: code,
                    slump: slump
                )
            } else if var existing = mixAdditional1 {
                if existing.qty == nil, let qty {
                    existing = MixRow(
                        qty: qty,
                        customerDescription: existing.customerDescription,
                        description: existing.description,
                        code: existing.code,
                        slump: existing.slump
                    )
                }
                if shouldOverrideAdditionalField(existing: existing.code, hint: code, customerValue: customerCode) {
                    existing = MixRow(
                        qty: existing.qty,
                        customerDescription: existing.customerDescription,
                        description: existing.description,
                        code: code,
                        slump: existing.slump
                    )
                }
                if shouldOverrideAdditionalField(existing: existing.slump, hint: slump, customerValue: customerSlump) {
                    existing = MixRow(
                        qty: existing.qty,
                        customerDescription: existing.customerDescription,
                        description: existing.description,
                        code: existing.code,
                        slump: slump
                    )
                }
                if let hintDescription = trimmedNonEmpty(description),
                   shouldApplyAdditionalDescriptionOverride(
                    existing: existing.description,
                    hint: hintDescription
                   ) {
                    existing = MixRow(
                        qty: existing.qty,
                        customerDescription: existing.customerDescription,
                        description: hintDescription,
                        code: existing.code,
                        slump: existing.slump
                    )
                }
                mixAdditional1 = existing
            }
        }

        var mixAdditional2 = ticket.mixAdditional2
        if rows.count > 2 {
            let additional = rows[2]
            let qty = trimmedNonEmpty(additional.qty)
            let code = trimmedNonEmpty(additional.code)
            let slump = trimmedNonEmpty(additional.slump)
            let description = sanitizeHintSpec(additional.spec)
            if mixAdditional2 == nil, qty != nil || code != nil || slump != nil || description != nil {
                mixAdditional2 = MixRow(
                    qty: qty,
                    customerDescription: nil,
                    description: description,
                    code: code,
                    slump: slump
                )
            } else if var existing = mixAdditional2 {
                if existing.qty == nil, let qty {
                    existing = MixRow(
                        qty: qty,
                        customerDescription: existing.customerDescription,
                        description: existing.description,
                        code: existing.code,
                        slump: existing.slump
                    )
                }
                if shouldOverrideAdditionalField(existing: existing.code, hint: code, customerValue: customerCode) {
                    existing = MixRow(
                        qty: existing.qty,
                        customerDescription: existing.customerDescription,
                        description: existing.description,
                        code: code,
                        slump: existing.slump
                    )
                }
                if shouldOverrideAdditionalField(existing: existing.slump, hint: slump, customerValue: customerSlump) {
                    existing = MixRow(
                        qty: existing.qty,
                        customerDescription: existing.customerDescription,
                        description: existing.description,
                        code: existing.code,
                        slump: slump
                    )
                }
                if let hintDescription = trimmedNonEmpty(description),
                   shouldApplyAdditionalDescriptionOverride(
                    existing: existing.description,
                    hint: hintDescription
                   ) {
                    existing = MixRow(
                        qty: existing.qty,
                        customerDescription: existing.customerDescription,
                        description: hintDescription,
                        code: existing.code,
                        slump: existing.slump
                    )
                }
                mixAdditional2 = existing
            }
        }

        if let additional = mixAdditional1,
           shouldNullAdditionalCustomerDescription(
            customerDescription: additional.customerDescription,
            description: additional.description
           ) {
            mixAdditional1 = MixRow(
                qty: additional.qty,
                customerDescription: nil,
                description: additional.description,
                code: additional.code,
                slump: additional.slump
            )
        }

        if let additional = mixAdditional2,
           shouldNullAdditionalCustomerDescription(
            customerDescription: additional.customerDescription,
            description: additional.description
           ) {
            mixAdditional2 = MixRow(
                qty: additional.qty,
                customerDescription: nil,
                description: additional.description,
                code: additional.code,
                slump: additional.slump
            )
        }

        return Ticket(
            ticketNumber: ticket.ticketNumber,
            deliveryDate: ticket.deliveryDate,
            deliveryTime: ticket.deliveryTime,
            deliveryAddress: ticket.deliveryAddress,
            mixCustomer: mixCustomer,
            mixAdditional1: mixAdditional1,
            mixAdditional2: mixAdditional2,
            extraCharges: ticket.extraCharges
        )
    }

    private static func parseMixParsedHints(_ mixParsedHints: String) -> [MixParsedHintRow] {
        let lines = mixParsedHints.split(separator: "\n", omittingEmptySubsequences: true)
        var rows: [MixParsedHintRow] = []
        var current: MixParsedHintRow? = nil

        for lineSubstring in lines {
            let line = lineSubstring.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.lowercased().hasPrefix("row ") {
                if let current {
                    rows.append(current)
                }
                current = MixParsedHintRow(qty: "", code: "", slump: "", spec: "")
                continue
            }

            if current == nil {
                current = MixParsedHintRow(qty: "", code: "", slump: "", spec: "")
            }

            if let value = value(after: "Qty:", in: line) {
                current?.qty = value
                continue
            }
            if let value = value(after: "Code:", in: line) {
                current?.code = value
                continue
            }
            if let value = value(after: "Slump:", in: line) {
                current?.slump = value
                continue
            }
            if let value = value(after: "Spec:", in: line) {
                current?.spec = value
                continue
            }
        }

        if let current {
            rows.append(current)
        }

        return rows
    }

    private static func value(after prefix: String, in line: String) -> String? {
        let lowerLine = line.lowercased()
        let lowerPrefix = prefix.lowercased()
        guard lowerLine.hasPrefix(lowerPrefix) else { return nil }
        let start = line.index(line.startIndex, offsetBy: prefix.count)
        return line[start...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeHintSpec(_ value: String?) -> String? {
        guard let value else { return nil }
        let stripped = stripLeadingQty(value)
        let cleaned = removeIgnoredMixPrefixes(from: stripped)
        return trimmedNonEmpty(cleaned)
    }

    private static func stripLeadingQty(_ value: String) -> String {
        let pattern = #"^\s*\d+(?:\.\d+)?\s*m(?:3|³)\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let range = NSRange(value.startIndex..., in: value)
        let stripped = regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeIgnoredMixPrefixes(from value: String) -> String {
        let patterns = [
            #"^ADDRESS:\s*"#,
            #"^TICKET\s*NO\.?:\s*"#,
            #"^PLANT\s*NO\.?:\s*"#,
            #"^CERTIFICATE:\s*"#
        ]
        var result = value
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stripMixSpecCandidate(
        _ value: String,
        codePattern: String,
        numericCodePattern: String,
        slumpPattern: String
    ) -> String {
        var cleaned = replacePattern(in: value, pattern: slumpPattern, with: " ")
        let tokens = cleaned.split(whereSeparator: { $0.isWhitespace })
        var kept: [Substring] = []

        for token in tokens {
            let rawToken = String(token)
            let trimmed = rawToken.trimmingCharacters(in: .punctuationCharacters)
            guard !trimmed.isEmpty else { continue }
            let upper = trimmed.uppercased()
            if isCustomerMixCode(upper) {
                continue
            }
            if matches(upper, pattern: codePattern),
               !upper.contains("MPA"),
               !upper.contains("MM") {
                continue
            }
            if matches(upper, pattern: numericCodePattern) || digitsOnlyCode(from: trimmed) != nil {
                continue
            }
            kept.append(token)
        }

        cleaned = kept.joined(separator: " ")
        cleaned = cleaned.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacePattern(in value: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return value
        }
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: replacement)
    }

    private static func shouldUseHint(existing: String?, hint: String?) -> Bool {
        guard let hint = trimmedNonEmpty(hint) else { return false }
        guard let existing = trimmedNonEmpty(existing) else { return true }
        if existing == hint { return false }
        let existingUpper = existing.uppercased()
        let hintUpper = hint.uppercased()
        if hintUpper.hasPrefix("WEATHERMIX") && !existingUpper.hasPrefix("WEATHERMIX") {
            return true
        }
        if existing.count < min(8, hint.count) {
            return true
        }
        if hint.hasPrefix(existing), hint.count > existing.count + 2 {
            return true
        }
        let normalizedExisting = normalizeSpecLine(existing)
        let normalizedHint = normalizeSpecLine(hint)
        if normalizedHint == normalizedExisting {
            return false
        }
        let existingTokens = normalizedExisting.split(whereSeparator: { $0.isWhitespace })
        let hintTokens = normalizedHint.split(whereSeparator: { $0.isWhitespace })
        if hintTokens.count > existingTokens.count, !existingTokens.isEmpty {
            let isSubset = existingTokens.allSatisfy { existingToken in
                hintTokens.contains { hintToken in
                    if hintToken == existingToken {
                        return true
                    }
                    if hintToken.hasPrefix(existingToken), existingToken.count >= 3 {
                        return true
                    }
                    return false
                }
            }
            if isSubset {
                return true
            }
        }
        return false
    }

    private static func shouldOverrideAdditionalField(
        existing: String?,
        hint: String?,
        customerValue: String?
    ) -> Bool {
        guard let hint = trimmedNonEmpty(hint) else { return false }
        guard let existing = trimmedNonEmpty(existing) else { return true }
        if existing == hint { return false }
        if let customerValue {
            let normalizedExisting = normalizeSpecLine(existing)
            let normalizedCustomer = normalizeSpecLine(customerValue)
            if normalizedExisting == normalizedCustomer {
                return true
            }
        }
        return false
    }

    private static func shouldApplyAdditionalDescriptionOverride(
        existing: String?,
        hint: String
    ) -> Bool {
        guard let existing = trimmedNonEmpty(existing) else { return true }
        let normalizedExisting = normalizeSpecLine(existing)
        let normalizedHint = normalizeSpecLine(hint)
        return normalizedExisting != normalizedHint
    }

    private static func shouldNullAdditionalCustomerDescription(
        customerDescription: String?,
        description: String?
    ) -> Bool {
        guard let customerDescription = trimmedNonEmpty(customerDescription) else { return false }
        guard let description = trimmedNonEmpty(description) else { return false }
        let normalizedCustomer = normalizeSpecLine(customerDescription)
        let normalizedDescription = normalizeSpecLine(description)
        if normalizedCustomer == normalizedDescription {
            return true
        }
        if normalizedDescription.hasPrefix(normalizedCustomer) {
            return true
        }
        if normalizedCustomer.hasPrefix(normalizedDescription) {
            return true
        }
        return false
    }

    private static func digitsOnlyCode(from line: String) -> String? {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 4 else { return nil }
        guard stripped.allSatisfy({ $0.isNumber }) else { return nil }
        return stripped
    }

    private static func isCustomerSpecLine(_ line: String) -> Bool {
        line.contains("MPA") || line.contains("%") || line.contains("N 20MM") || line.contains("20MM")
    }

    private static func isCustomerMixCode(_ value: String) -> Bool {
        value.uppercased().hasPrefix("RMX")
    }

    private static func dedupeSpecParts(_ parts: [String]) -> [String] {
        guard parts.count > 1 else { return parts }
        let normalized = parts.map { normalizeSpecLine($0) }
        var result: [String] = []
        for (index, part) in parts.enumerated() {
            let current = normalized[index]
            var isSubstring = false
            for (otherIndex, other) in normalized.enumerated() {
                guard index != otherIndex else { continue }
                if other.contains(current) && other.count > current.count {
                    isSubstring = true
                    break
                }
            }
            if !isSubstring {
                result.append(part)
            }
        }
        return result
    }

    private static func normalizeSpecLine(_ line: String) -> String {
        let upper = line.uppercased()
        let components = upper.split(whereSeparator: { $0.isWhitespace })
        let collapsed = components.joined(separator: " ")
        return normalizeSpecTokens(collapsed)
    }

    private static func normalizeSpecTokens(_ value: String) -> String {
        var normalized = value
        let patterns: [(String, String)] = [
            (#"(\d+)\s*MPA"#, "$1MPA"),
            (#"(\d+)\s*MM"#, "$1MM"),
            (#"\bC\s*(\d+)\b"#, "C$1")
        ]
        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(normalized.startIndex..., in: normalized)
                normalized = regex.stringByReplacingMatches(
                    in: normalized,
                    options: [],
                    range: range,
                    withTemplate: replacement
                )
            }
        }
        return normalized
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        var results: [String] = []
        for index in 0..<match.numberOfRanges {
            let matchRange = match.range(at: index)
            if let range = Range(matchRange, in: text) {
                results.append(String(text[range]))
            } else {
                results.append("")
            }
        }
        return results
    }

    private static func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private static func firstMixDataIndex(in lines: [String]) -> Int? {
        let cubeSymbol = "\u{00B3}"

        func normalized(_ line: String) -> String {
            line.replacingOccurrences(of: cubeSymbol, with: "3").uppercased()
        }

        func matches(_ line: String, pattern: String) -> Bool {
            line.range(of: pattern, options: .regularExpression) != nil
        }

        for (index, line) in lines.enumerated() {
            let upper = normalized(line)
            if matches(upper, pattern: #"\b\d+(?:\.\d+)?\s*M(?:3|³)\b"#) {
                return index
            }
        }

        for (index, line) in lines.enumerated() {
            let upper = normalized(line)
            if matches(upper, pattern: #"^\s*\d+\b"#) {
                return index
            }
        }

        return nil
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

    private static func writeResponseOut(_ response: String, outputPath: String) throws {
        let url = URL(fileURLWithPath: outputPath)
        let data = response.data(using: .utf8) ?? Data()
        try data.write(to: url, options: Data.WritingOptions.atomic)
    }

}
