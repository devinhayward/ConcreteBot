import Foundation

enum TicketValidationError: Error, CustomStringConvertible {
    case decodeFailed(String)
    case missingTicketNumber

    var description: String {
        switch self {
        case .decodeFailed(let detail):
            return "Failed to decode ticket JSON: \(detail)"
        case .missingTicketNumber:
            return "Ticket No. is required to name output files."
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

    static func validate(ticket: Ticket) throws {
        let trimmedNumber = ticket.ticketNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNumber?.isEmpty ?? true {
            throw TicketValidationError.missingTicketNumber
        }
    }
}
