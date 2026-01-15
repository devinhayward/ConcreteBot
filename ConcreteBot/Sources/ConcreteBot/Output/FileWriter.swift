import Foundation

enum FileWriterError: Error, CustomStringConvertible {
    case invalidOutputDirectory(String)
    case encodeFailed(String)

    var description: String {
        switch self {
        case .invalidOutputDirectory(let path):
            return "Output directory does not exist: \(path)"
        case .encodeFailed(let detail):
            return "Failed to encode ticket JSON: \(detail)"
        }
    }
}

enum FileWriter {
    static func write(tickets: [Ticket], outputDir: String) throws {
        let outputURL = URL(fileURLWithPath: outputDir, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FileWriterError.invalidOutputDirectory(outputURL.path)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        for ticket in tickets {
            guard let ticketNumber = ticket.ticketNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !ticketNumber.isEmpty else {
                continue
            }

            let fileName = "ticket-\(sanitizeFileName(ticketNumber)).json"
            let fileURL = outputURL.appendingPathComponent(fileName)

            do {
                let data = try encoder.encode(ticket)
                try data.write(to: fileURL, options: Data.WritingOptions.atomic)
            } catch {
                throw FileWriterError.encodeFailed(error.localizedDescription)
            }
        }
    }

    private static func sanitizeFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return value.components(separatedBy: invalid).joined(separator: "_")
    }
}
