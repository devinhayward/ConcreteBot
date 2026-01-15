import Foundation

enum ExtractError: Error, CustomStringConvertible {
    case missingPromptTemplate
    case noJSONFound
    case invalidResponse(String)
    case missingResponseInput

    var description: String {
        switch self {
        case .missingPromptTemplate:
            return "Missing prompt template in resources."
        case .noJSONFound:
            return "No JSON objects found in ChatGPT response."
        case .invalidResponse(let detail):
            return "Invalid response: \(detail)"
        case .missingResponseInput:
            return "No response input provided. Use --response-file or --response-stdin."
        }
    }
}

enum Extract {
    static func run(options: CLIOptions) throws {
        let promptTemplate = try loadPromptTemplate()
        let prompt = renderPrompt(
            template: promptTemplate,
            pdfPath: options.pdfPath,
            pages: options.pages
        )

        if options.printPrompt {
            print(prompt)
            if options.responseFile == nil && !options.responseStdin {
                return
            }
        }

        let response: String
        if let responseFile = options.responseFile {
            response = try String(contentsOfFile: responseFile, encoding: .utf8)
        } else if options.responseStdin {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            response = String(data: data, encoding: .utf8) ?? ""
        } else {
            response = try PlaywrightClient.run(
                prompt: prompt,
                pdfPath: options.pdfPath,
                profileDir: options.profileDir,
                headless: options.headless,
                browserChannel: options.browserChannel,
                manualLogin: options.manualLogin
            )
        }

        if response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ExtractError.missingResponseInput
        }

        let jsonObjects = splitJSONObjects(from: response)
        guard !jsonObjects.isEmpty else {
            throw ExtractError.noJSONFound
        }

        var tickets: [Ticket] = []
        for json in jsonObjects {
            let ticket = try TicketValidator.decode(json: json)
            try TicketValidator.validate(ticket: ticket)
            tickets.append(ticket)
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

    private static func renderPrompt(template: String, pdfPath: String, pages: String) -> String {
        let fileName = URL(fileURLWithPath: pdfPath).lastPathComponent
        var lines = template.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for index in lines.indices {
            if lines[index].hasPrefix("File name:") {
                lines[index] = "File name: <<\(fileName)>>"
            } else if lines[index].hasPrefix("Page(s):") {
                lines[index] = "Page(s): <<\(pages)>>"
            }
        }

        return lines.joined(separator: "\n")
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

    private static func expandingTilde(in path: String) -> String {
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        return path
    }
}
