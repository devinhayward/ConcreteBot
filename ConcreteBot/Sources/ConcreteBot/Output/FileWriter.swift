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

        for ticket in tickets {
            guard let ticketNumber = ticket.ticketNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !ticketNumber.isEmpty else {
                continue
            }

            let fileName = "ticket-\(sanitizeFileName(ticketNumber)).json"
            let fileURL = outputURL.appendingPathComponent(fileName)

            let json = serialize(ticket: ticket)
            guard let data = json.data(using: .utf8) else {
                throw FileWriterError.encodeFailed("Failed to encode UTF-8 JSON string.")
            }
            do {
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

    private static func serialize(ticket: Ticket) -> String {
        var lines: [String] = []
        lines.append("{")
        lines.append(formatField("Ticket No.", value: ticket.ticketNumber, level: 1, trailingComma: true))
        lines.append(formatField("Delivery Date", value: ticket.deliveryDate, level: 1, trailingComma: true))
        lines.append(formatField("Delivery Time", value: ticket.deliveryTime, level: 1, trailingComma: true))
        lines.append(formatField("Delivery Address", value: ticket.deliveryAddress, level: 1, trailingComma: true))
        lines.append(formatMixRowField("Mix Customer", row: ticket.mixCustomer, level: 1, trailingComma: true))
        if let mixVendor = ticket.mixVendor {
            lines.append(formatMixRowField("Mix Vendor", row: mixVendor, level: 1, trailingComma: true))
        } else {
            lines.append(formatNullField("Mix Vendor", level: 1, trailingComma: true))
        }
        lines.append(formatExtraChargesField("Extra Charges", charges: ticket.extraCharges, level: 1, trailingComma: false))
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private static func formatField(_ key: String, value: String?, level: Int, trailingComma: Bool) -> String {
        let indent = String(repeating: "  ", count: level)
        let suffix = trailingComma ? "," : ""
        return "\(indent)\"\(escape(key))\": \(jsonValue(value))\(suffix)"
    }

    private static func formatNullField(_ key: String, level: Int, trailingComma: Bool) -> String {
        let indent = String(repeating: "  ", count: level)
        let suffix = trailingComma ? "," : ""
        return "\(indent)\"\(escape(key))\": null\(suffix)"
    }

    private static func formatMixRowField(_ key: String, row: MixRow, level: Int, trailingComma: Bool) -> String {
        let indent = String(repeating: "  ", count: level)
        let suffix = trailingComma ? "," : ""
        let rowLines = formatMixRow(row, level: level + 1)
        return "\(indent)\"\(escape(key))\": \(rowLines)\(suffix)"
    }

    private static func formatMixRow(_ row: MixRow, level: Int) -> String {
        let indent = String(repeating: "  ", count: level)
        let closingIndent = String(repeating: "  ", count: level - 1)
        var lines: [String] = []
        lines.append("{")
        lines.append("\(indent)\"Qty\": \(jsonValue(row.qty)),")
        lines.append("\(indent)\"Cust. Descr.\": \(jsonValue(row.customerDescription)),")
        lines.append("\(indent)\"Description\": \(jsonValue(row.description)),")
        lines.append("\(indent)\"Code\": \(jsonValue(row.code)),")
        lines.append("\(indent)\"Slump\": \(jsonValue(row.slump))")
        lines.append("\(closingIndent)}")
        return lines.joined(separator: "\n")
    }

    private static func formatExtraChargesField(_ key: String, charges: [ExtraCharge], level: Int, trailingComma: Bool) -> String {
        let indent = String(repeating: "  ", count: level)
        let suffix = trailingComma ? "," : ""
        let arrayValue = formatExtraCharges(charges, level: level + 1)
        return "\(indent)\"\(escape(key))\": \(arrayValue)\(suffix)"
    }

    private static func formatExtraCharges(_ charges: [ExtraCharge], level: Int) -> String {
        guard !charges.isEmpty else { return "[]" }
        let indent = String(repeating: "  ", count: level)
        let closingIndent = String(repeating: "  ", count: level - 1)
        var lines: [String] = []
        lines.append("[")
        for (index, charge) in charges.enumerated() {
            let isLast = index == charges.count - 1
            lines.append("\(indent){")
            lines.append("\(indent)  \"Description\": \(jsonValue(charge.description)),")
            lines.append("\(indent)  \"Qty\": \(jsonValue(charge.qty))")
            lines.append("\(indent)}\(isLast ? "" : ",")")
        }
        lines.append("\(closingIndent)]")
        return lines.joined(separator: "\n")
    }

    private static func jsonValue(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "null" }
        return "\"\(escape(value))\""
    }

    private static func escape(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22:
                escaped.append("\\\"")
            case 0x5C:
                escaped.append("\\\\")
            case 0x08:
                escaped.append("\\b")
            case 0x0C:
                escaped.append("\\f")
            case 0x0A:
                escaped.append("\\n")
            case 0x0D:
                escaped.append("\\r")
            case 0x09:
                escaped.append("\\t")
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16, uppercase: true)
                    escaped.append("\\u")
                    escaped.append(String(repeating: "0", count: max(0, 4 - hex.count)))
                    escaped.append(hex)
                } else {
                    escaped.append(String(scalar))
                }
            }
        }
        return escaped
    }
}
