import Foundation

enum TicketNormalizer {
    static func normalize(ticket: Ticket) -> Ticket {
        let normalizedExtraCharges = ticket.extraCharges.map { normalize(extraCharge: $0) }
        let extraChargeQtys = Set(
            normalizedExtraCharges
                .compactMap { $0.qty?.trimmedNonEmpty }
        )
        let extraChargeDescriptions = Set(
            normalizedExtraCharges
                .compactMap { $0.description?.trimmedNonEmpty?.lowercased() }
        )

        let mixCustomer = normalize(
            mixRow: ticket.mixCustomer,
            extraChargeQtys: extraChargeQtys,
            extraChargeDescriptions: extraChargeDescriptions
        )

        let mixAdditional1 = ticket.mixAdditional1.map { mixRow in
            normalize(
                mixRow: mixRow,
                extraChargeQtys: extraChargeQtys,
                extraChargeDescriptions: extraChargeDescriptions
            )
        }
        let mixAdditional2 = ticket.mixAdditional2.map { mixRow in
            normalize(
                mixRow: mixRow,
                extraChargeQtys: extraChargeQtys,
                extraChargeDescriptions: extraChargeDescriptions
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
            extraCharges: normalizedExtraCharges
        )
    }

    private static func normalize(extraCharge: ExtraCharge) -> ExtraCharge {
        let qty = extraCharge.qty?.trimmedNonEmpty
        let description = extraCharge.description?.trimmedNonEmpty
        guard let qty, let description else {
            return extraCharge
        }

        let qtyNumeric = numericPrefix(in: qty)
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if let (number, remainder) = splitLeadingNumber(from: trimmed),
           let qtyNumeric,
           number == qtyNumeric,
           let remainder = remainder.trimmedNonEmpty {
            return ExtraCharge(description: remainder, qty: qty)
        }

        return extraCharge
    }

    private static func splitLeadingNumber(from value: String) -> (number: String, remainder: String)? {
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
        let remainder = String(value[remainderRange])
        return (number, remainder)
    }

    private static func normalize(
        mixRow: MixRow,
        extraChargeQtys: Set<String>,
        extraChargeDescriptions: Set<String>
    ) -> MixRow {
        let mixQtyNumeric = numericPrefix(in: mixRow.qty)
        var code = mixRow.code?.trimmedNonEmpty
        var slump = mixRow.slump?.trimmedNonEmpty
        let slumpLooksLikeExtraCharge = isExtraChargeNoise(
            slump,
            extraChargeQtys: extraChargeQtys,
            extraChargeDescriptions: extraChargeDescriptions,
            mixQtyNumeric: mixQtyNumeric
        )

        if let codeValue = code,
           let split = splitTrailingSlump(from: codeValue) {
            if shouldUseCandidate(
                currentSlump: slump,
                candidate: split.slump,
                extraChargeQtys: extraChargeQtys,
                extraChargeDescriptions: extraChargeDescriptions,
                mixQtyNumeric: mixQtyNumeric,
                currentSlumpIsNoise: slumpLooksLikeExtraCharge
            ) {
                code = split.code.trimmedNonEmpty
                slump = split.slump
            }
        }

        if let slumpValue = slump,
           isExtraChargeNoise(
            slumpValue,
            extraChargeQtys: extraChargeQtys,
            extraChargeDescriptions: extraChargeDescriptions,
            mixQtyNumeric: mixQtyNumeric
           ) {
            slump = nil
        }

        return MixRow(
            qty: mixRow.qty,
            customerDescription: mixRow.customerDescription,
            description: mixRow.description,
            code: code,
            slump: slump
        )
    }

    private static func shouldUseCandidate(
        currentSlump: String?,
        candidate: String,
        extraChargeQtys: Set<String>,
        extraChargeDescriptions: Set<String>,
        mixQtyNumeric: String?,
        currentSlumpIsNoise: Bool
    ) -> Bool {
        guard currentSlump != candidate else { return false }
        if currentSlump == nil {
            return true
        }
        if currentSlumpIsNoise {
            return true
        }
        return isExtraChargeNoise(currentSlump ?? "",
                                  extraChargeQtys: extraChargeQtys,
                                  extraChargeDescriptions: extraChargeDescriptions,
                                  mixQtyNumeric: mixQtyNumeric)
    }

    private static func isExtraChargeNoise(
        _ value: String?,
        extraChargeQtys: Set<String>,
        extraChargeDescriptions: Set<String>,
        mixQtyNumeric: String?
    ) -> Bool {
        guard let value, !value.isEmpty else { return false }
        if extraChargeQtys.contains(value) {
            return true
        }
        if let mixQtyNumeric, mixQtyNumeric == value {
            return true
        }
        let lowerValue = value.lowercased()
        for description in extraChargeDescriptions {
            if lowerValue.contains(description) {
                return true
            }
        }
        for qty in extraChargeQtys {
            if lowerValue.hasPrefix(qty.lowercased() + " ") {
                return true
            }
        }
        return false
    }

    private static func splitTrailingSlump(from code: String) -> (code: String, slump: String)? {
        let tokens = code.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count >= 2 else { return nil }
        let lastToken = String(tokens.last ?? "")
        guard isSlumpCandidate(lastToken) else { return nil }
        let codeValue = tokens.dropLast().joined(separator: " ")
        return (code: codeValue, slump: lastToken)
    }

    private static func isSlumpCandidate(_ value: String) -> Bool {
        guard value.rangeOfCharacter(from: .decimalDigits) != nil else { return false }
        if value.contains("+") || value.contains("-") || value.contains("±") {
            return true
        }
        return false
    }

    private static func numericPrefix(in value: String?) -> String? {
        guard let value else { return nil }
        let pattern = #"\d+(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = regex.firstMatch(in: value, range: range) else { return nil }
        guard let matchRange = Range(match.range, in: value) else { return nil }
        return String(value[matchRange])
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
