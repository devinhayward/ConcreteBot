import Foundation

enum TicketValidationError: Error, CustomStringConvertible {
    case decodeFailed(String)
    case invalidFields([TicketValidationIssue])

    var description: String {
        switch self {
        case .decodeFailed(let detail):
            return "Failed to decode ticket JSON: \(detail)"
        case .invalidFields(let issues):
            let details = issues.map { $0.description }.joined(separator: " | ")
            return "Invalid ticket fields: \(details)"
        }
    }
}

enum TicketValidator {
    static func decode(json: String) throws -> Ticket {
        guard let data = json.data(using: .utf8) else {
            throw TicketValidationError.decodeFailed("Invalid UTF-8 JSON string.")
        }

        do {
            return try JSONDecoder().decode(Ticket.self, from: data)
        } catch {
            throw TicketValidationError.decodeFailed(error.localizedDescription)
        }
    }

    static func validate(ticket: Ticket, ignoringPaths: Set<String> = []) throws {
        let issues = issues(ticket: ticket).filter { issue in
            !ignoringPaths.contains(issue.path)
        }
        if !issues.isEmpty {
            throw TicketValidationError.invalidFields(issues)
        }
    }

    static func issues(ticket: Ticket) -> [TicketValidationIssue] {
        var issues: [TicketValidationIssue] = []
        let trimmedNumber = ticket.ticketNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedNumber.isEmpty {
            issues.append(TicketValidationIssue(path: "Ticket No.", message: "Missing ticket number"))
        }

        if let deliveryDate = ticket.deliveryDate?.trimmingCharacters(in: .whitespacesAndNewlines),
           !deliveryDate.isEmpty,
           !isValidDate(deliveryDate) {
            issues.append(TicketValidationIssue(path: "Delivery Date", message: "Unrecognized date format"))
        }

        if let deliveryTime = ticket.deliveryTime?.trimmingCharacters(in: .whitespacesAndNewlines),
           !deliveryTime.isEmpty,
           !isValidTime(deliveryTime) {
            issues.append(TicketValidationIssue(path: "Delivery Time", message: "Unrecognized time format"))
        }

        validateMixRow(ticket.mixCustomer, name: "Mix Customer", issues: &issues)
        if let additional = ticket.mixAdditional1 {
            validateMixRow(additional, name: "Mix Additional 1", issues: &issues)
        }
        if let additional = ticket.mixAdditional2 {
            validateMixRow(additional, name: "Mix Additional 2", issues: &issues)
        }

        for (index, charge) in ticket.extraCharges.enumerated() {
            let qty = charge.qty?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = charge.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !qty.isEmpty, !isValidQty(qty) {
                issues.append(TicketValidationIssue(
                    path: "Extra Charges[\(index)].Qty",
                    message: "Qty must be numeric with up to 2 decimals"
                ))
            }
            if qty.isEmpty, !description.isEmpty {
                issues.append(TicketValidationIssue(
                    path: "Extra Charges[\(index)].Qty",
                    message: "Missing qty for extra charge"
                ))
            }
            if description.isEmpty, !qty.isEmpty {
                issues.append(TicketValidationIssue(
                    path: "Extra Charges[\(index)].Description",
                    message: "Missing description for extra charge"
                ))
            }
        }

        return issues
    }

    private static func validateMixRow(_ row: MixRow, name: String, issues: inout [TicketValidationIssue]) {
        if let qty = row.qty?.trimmingCharacters(in: .whitespacesAndNewlines),
           !qty.isEmpty,
           !isValidMixQty(qty) {
            issues.append(TicketValidationIssue(
                path: "\(name).Qty",
                message: "Qty must be numeric with optional m3 unit"
            ))
        }
        if let slump = row.slump?.trimmingCharacters(in: .whitespacesAndNewlines),
           !slump.isEmpty,
           !isValidSlump(slump) {
            issues.append(TicketValidationIssue(
                path: "\(name).Slump",
                message: "Slump must be a number or X+-Y format"
            ))
        }
    }

    private static func isValidDate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let normalized = normalizeDateString(trimmed)
        let candidates = [trimmed, normalized].filter { !$0.isEmpty }
        let formatters = dateFormatters()
        return candidates.contains { candidate in
            formatters.contains { formatter in
                formatter.date(from: candidate) != nil
            }
        }
    }

    private static func dateFormatters() -> [DateFormatter] {
        let formats = [
            "EEE, MMM d yyyy",
            "EEE, MMM dd yyyy",
            "EEE, MMM d, yyyy",
            "EEE, MMM dd, yyyy",
            "EEE MMM d yyyy",
            "EEE MMM dd yyyy",
            "MMM d yyyy",
            "MMM dd yyyy",
            "MMM d, yyyy",
            "MMM dd, yyyy",
            "MM/dd/yyyy",
            "yyyy-MM-dd"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter
        }
    }

    private static func normalizeDateString(_ value: String) -> String {
        var normalized = value
        normalized = normalized.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"(\b\d{1,2}),"#,
            with: "$1",
            options: .regularExpression
        )
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isValidTime(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return false
        }
        return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59
    }

    private static func isValidMixQty(_ value: String) -> Bool {
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        return matches(normalized, pattern: #"^\d+(?:\.\d{1,2})?\s*(m3|m³)?$"#)
    }

    private static func isValidQty(_ value: String) -> Bool {
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        return matches(normalized, pattern: #"^\d+(?:\.\d{1,2})?$"#)
    }

    private static func isValidSlump(_ value: String) -> Bool {
        let normalized = value.replacingOccurrences(of: " ", with: "")
        if matches(normalized, pattern: #"^\d+(?:\.\d+)?$"#) {
            return true
        }
        return matches(normalized, pattern: #"^\d+(?:\.\d+)?\+\-\d+(?:\.\d+)?$"#)
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}

struct TicketValidationIssue: CustomStringConvertible, Hashable {
    let path: String
    let message: String

    var description: String {
        "\(path): \(message)"
    }
}
