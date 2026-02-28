import Foundation

enum BatchError: Error, CustomStringConvertible {
    case emptyCSV(String)
    case invalidCSVLine(Int, String)
    case missingPDFPath(Int)

    var description: String {
        switch self {
        case .emptyCSV(let path):
            return "CSV file is empty: \(path)"
        case .invalidCSVLine(let line, let detail):
            return "Invalid CSV line \(line): \(detail)"
        case .missingPDFPath(let line):
            return "Missing PDF path on CSV line \(line)."
        }
    }
}

struct BatchRow {
    let pdfPath: String
    let pages: String?
}

enum Batch {
    static func run(options: BatchOptions) throws {
        let csvPath = Extract.expandingTilde(in: options.csvPath)
        let csvContents = try String(contentsOfFile: csvPath, encoding: .utf8)
        let rows = try parseCSVRows(csvContents)
        guard !rows.isEmpty else {
            throw BatchError.emptyCSV(csvPath)
        }

        for row in rows {
            let resolvedPages = row.pages ?? options.pages
            let extractOptions = CLIOptions(
                pdfPath: Extract.expandingTilde(in: row.pdfPath),
                pages: resolvedPages,
                outputDir: options.outputDir,
                printPrompt: options.printPrompt,
                responseFile: nil,
                responseStdin: false,
                responseOut: nil
            )
            try Extract.run(options: extractOptions)
        }
    }

    static func parseCSVRows(_ csv: String) throws -> [BatchRow] {
        let lines = csv.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var rows: [BatchRow] = []
        var checkedHeader = false

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("#") { continue }

            let fields = try parseCSVLine(trimmed, lineNumber: lineNumber)
            let normalizedFields = fields.map {
                $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            }
            guard !normalizedFields.isEmpty else { continue }

            if !checkedHeader {
                checkedHeader = true
                if isHeaderRow(normalizedFields) {
                    continue
                }
            }

            let pdfPath = normalizedFields[0]
            guard !pdfPath.isEmpty else {
                throw BatchError.missingPDFPath(lineNumber)
            }
            let pages = normalizedFields.count > 1 ? trimmedNonEmpty(normalizedFields[1]) : nil
            rows.append(BatchRow(pdfPath: pdfPath, pages: pages))
        }

        return rows
    }

    private static func isHeaderRow(_ fields: [String]) -> Bool {
        guard let first = fields.first?.lowercased() else { return false }
        let headerNames = ["pdf", "pdf_path", "path", "file"]
        guard headerNames.contains(first) else { return false }
        if fields.count < 2 {
            return true
        }
        let second = fields[1].lowercased()
        return second.contains("page")
    }

    private static func parseCSVLine(_ line: String, lineNumber: Int) throws -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var quoteChar: Character?
        var index = line.startIndex

        while index < line.endIndex {
            let char = line[index]
            if inQuotes {
                if char == quoteChar {
                    let next = line.index(after: index)
                    if next < line.endIndex, line[next] == quoteChar {
                        current.append(char)
                        index = next
                    } else {
                        inQuotes = false
                        quoteChar = nil
                    }
                } else {
                    current.append(char)
                }
            } else {
                if char == "\"" || char == "'" {
                    inQuotes = true
                    quoteChar = char
                } else if char == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(char)
                }
            }
            index = line.index(after: index)
        }

        if inQuotes {
            throw BatchError.invalidCSVLine(lineNumber, "Unterminated quote.")
        }

        fields.append(current)
        return fields
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
