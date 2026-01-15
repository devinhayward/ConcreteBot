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
                let prompt = renderPrompt(
                    template: promptTemplate,
                    pdfPath: options.pdfPath,
                    page: pageNumber,
                    pageText: pageText
                )
                print(prompt)
                print("")
            }
            return
        }

        var tickets: [Ticket] = []
        for pageNumber in pageNumbers {
            let pageText = try extractPageText(document: document, pageNumber: pageNumber)
            let prompt = renderPrompt(
                template: promptTemplate,
                pdfPath: options.pdfPath,
                page: pageNumber,
                pageText: pageText
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
        }

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
        pageText: String
    ) -> String {
        let fileName = URL(fileURLWithPath: pdfPath).lastPathComponent
        var rendered = template
        rendered = rendered.replacingOccurrences(of: "<<FILE_NAME>>", with: fileName)
        rendered = rendered.replacingOccurrences(of: "<<PAGE_NUMBER>>", with: String(page))
        rendered = rendered.replacingOccurrences(of: "<<PDF_TEXT>>", with: pageText)
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
}
