import Foundation

enum TicketNormalizer {
    static func normalize(ticket: Ticket) -> Ticket {
        let normalizedExtraCharges = ticket.extraCharges.map { normalize(extraCharge: $0) }
        let orderedExtraCharges = reorderExtraCharges(normalizedExtraCharges)
        let extraChargeQtys = Set(
            orderedExtraCharges
                .compactMap { $0.qty?.trimmedNonEmpty }
        )
        let extraChargeDescriptions = Set(
            orderedExtraCharges
                .compactMap { $0.description?.trimmedNonEmpty?.lowercased() }
        )

        let deliveryAddress = normalizeDeliveryAddress(ticket.deliveryAddress)
        var mixCustomer = normalize(
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
        mixCustomer = stripAdditionalTokens(
            from: mixCustomer,
            additions: [mixAdditional1, mixAdditional2]
        )
        mixCustomer = normalizeCustomerSpec(mixCustomer)

        return Ticket(
            ticketNumber: ticket.ticketNumber,
            deliveryDate: ticket.deliveryDate,
            deliveryTime: ticket.deliveryTime,
            deliveryAddress: deliveryAddress,
            mixCustomer: mixCustomer,
            mixAdditional1: mixAdditional1,
            mixAdditional2: mixAdditional2,
            extraCharges: orderedExtraCharges
        )
    }

    private static func stripAdditionalTokens(
        from mixRow: MixRow,
        additions: [MixRow?]
    ) -> MixRow {
        let additionalTokenSet = Set(
            additions
                .compactMap { $0?.description?.trimmedNonEmpty }
                .flatMap { normalizeSpecLine($0).split(whereSeparator: { $0.isWhitespace }) }
                .map { String($0) }
                .filter { isMeaningfulAdditionalToken($0) }
        )
        guard !additionalTokenSet.isEmpty else { return mixRow }

        func strip(_ value: String?) -> String? {
            guard let value else { return nil }
            let tokens = value.split(whereSeparator: { $0.isWhitespace })
            guard !tokens.isEmpty else { return value }
            let normalizedTokens = tokens.map { normalizeSpecToken(String($0)) }
            guard let lastCoreIndex = normalizedTokens.lastIndex(where: { isCoreSpecToken($0) }) else {
                return value
            }
            var kept: [Substring] = []
            kept.reserveCapacity(tokens.count)
            for (index, token) in tokens.enumerated() {
                let normalized = normalizedTokens[index]
                if index > lastCoreIndex,
                   additionalTokenSet.contains(normalized),
                   !isCoreSpecToken(normalized) {
                    continue
                }
                kept.append(token)
            }
            let cleaned = kept.joined(separator: " ").trimmedNonEmpty
            return cleaned ?? value
        }

        return MixRow(
            qty: mixRow.qty,
            customerDescription: strip(mixRow.customerDescription),
            description: strip(mixRow.description),
            code: mixRow.code,
            slump: mixRow.slump
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
        let rawDescription = stripLeadingMixQty(from: mixRow.description)?.trimmedNonEmpty
        var customerDescription = normalizeMixSpec(mixRow.customerDescription)
        var description = stripLeadingMixQty(from: mixRow.description)?.trimmedNonEmpty
        let slumpLooksLikeExtraCharge = isExtraChargeNoise(
            slump,
            extraChargeQtys: extraChargeQtys,
            extraChargeDescriptions: extraChargeDescriptions,
            mixQtyNumeric: mixQtyNumeric
        )

        if let codeValue = code,
           let split = splitTrailingSlump(from: codeValue) {
            if slump == split.slump {
                code = split.code.trimmedNonEmpty
            } else if shouldUseCandidate(
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
        if slump == nil {
            slump = defaultSlump(for: code)
        }

        description = stripMixTokens(
            from: description,
            code: code,
            slump: slump,
            fallback: customerDescription
        )
        if let cleanedCustomer = stripMixTokens(
            from: customerDescription,
            code: code,
            slump: slump,
            fallback: nil
        ) {
            customerDescription = cleanedCustomer
        } else if customerDescription != nil {
            customerDescription = nil
        }
        description = normalizeMixSpec(description)
        description = normalizeDescriptionFromHeader(
            description,
            customerDescription: customerDescription,
            rawDescription: rawDescription
        )
        description = stripStandardFromDescription(
            description,
            customerDescription: customerDescription,
            rawDescription: rawDescription
        )
        description = ensureStandardInDescription(
            description,
            customerDescription: customerDescription,
            rawDescription: rawDescription
        )

        return MixRow(
            qty: mixRow.qty,
            customerDescription: customerDescription,
            description: description,
            code: code,
            slump: slump
        )
    }

    private static func normalizeCustomerSpec(_ mixRow: MixRow) -> MixRow {
        let customer = mixRow.customerDescription?.trimmedNonEmpty
        let description = mixRow.description?.trimmedNonEmpty
        guard customer != nil || description != nil else { return mixRow }

        let best = selectBestSpec(customer, description)
        var normalizedCustomer = customer
        var normalizedDescription = description

        if let best, description == nil || best != description {
            if let customer,
               let description,
               normalizedSpecWithoutStandard(customer) == normalizeSpecLine(description) {
                // Keep description without STANDARD when it matches the customer spec.
            } else if let customer,
                      let description,
                      preferSpecVariant(customer, description) == customer {
                // Keep the non-preferred SP variant in description when customer is HR.
            } else {
                normalizedDescription = best
            }
        }

        if let best, best.uppercased().contains("WEATHERMIX") {
            if normalizedCustomer == nil {
                let weatherVariant = replaceWeatherMix(best)
                if weatherVariant != best {
                    normalizedCustomer = weatherVariant
                } else if normalizedCustomer == nil {
                    normalizedCustomer = best
                }
            }
        } else if normalizedCustomer == nil {
            normalizedCustomer = best
        }

        return MixRow(
            qty: mixRow.qty,
            customerDescription: normalizedCustomer,
            description: normalizedDescription,
            code: mixRow.code,
            slump: mixRow.slump
        )
    }

    private static func selectBestSpec(_ first: String?, _ second: String?) -> String? {
        guard let first, let second else { return first ?? second }
        if let preferred = preferSpecVariant(first, second) {
            return preferred
        }
        let scoreFirst = specScore(first)
        let scoreSecond = specScore(second)
        if scoreFirst == scoreSecond {
            return first.count >= second.count ? first : second
        }
        return scoreFirst >= scoreSecond ? first : second
    }

    private static func preferSpecVariant(_ first: String, _ second: String) -> String? {
        let normalizedFirst = normalizeSpecLine(first)
        let normalizedSecond = normalizeSpecLine(second)
        if normalizedFirst == normalizedSecond {
            return nil
        }
        let firstTokens = normalizedFirst.split(whereSeparator: { $0.isWhitespace })
        let secondTokens = normalizedSecond.split(whereSeparator: { $0.isWhitespace })
        guard firstTokens.count == secondTokens.count, !firstTokens.isEmpty else { return nil }
        var diffIndex: Int? = nil
        for (index, token) in firstTokens.enumerated() {
            if token != secondTokens[index] {
                if diffIndex != nil {
                    return nil
                }
                diffIndex = index
            }
        }
        guard let diffIndex else { return nil }
        let firstToken = String(firstTokens[diffIndex])
        let secondToken = String(secondTokens[diffIndex])
        if firstToken == "HR" && secondToken == "SP" {
            return first
        }
        if firstToken == "SP" && secondToken == "HR" {
            return second
        }
        return nil
    }

    private static func specScore(_ value: String) -> Int {
        let tokens = value.split(whereSeparator: { $0.isWhitespace })
        var score = value.count
        let upper = value.uppercased()
        let singleLetterCount = tokens.filter { $0.count == 1 }.count
        score -= singleLetterCount * 6
        if upper.contains("MPA") {
            score += 10
        }
        if upper.contains("WEATHERMIX") {
            score += 8
        }
        if upper.contains("STANDARD") {
            score += 6
        }
        if upper.contains("WEATHER") {
            score += 4
        }
        return score
    }

    private static func replaceWeatherMix(_ value: String) -> String {
        let pattern = #"\bWEATHERMIX\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return value
        }
        let range = NSRange(value.startIndex..., in: value)
        let replaced = regex.stringByReplacingMatches(
            in: value,
            options: [],
            range: range,
            withTemplate: "WEATHER"
        )
        return replaced
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

    private static func stripMixTokens(
        from description: String?,
        code: String?,
        slump: String?,
        fallback: String?
    ) -> String? {
        guard let description else { return nil }
        let tokens = description.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return nil }
        let normalizedCode = normalizeMixToken(code)
        let normalizedSlump = normalizeSlumpToken(slump)
        var kept: [Substring] = []
        var removedAny = false

        for token in tokens {
            let tokenValue = String(token)
            if let normalizedCode,
               normalizeMixToken(tokenValue) == normalizedCode {
                removedAny = true
                continue
            }
            if let normalizedSlump,
               normalizeSlumpToken(tokenValue) == normalizedSlump {
                removedAny = true
                continue
            }
            kept.append(token)
        }

        guard removedAny else { return description }
        let cleaned = kept.joined(separator: " ").trimmedNonEmpty
        return cleaned ?? fallback
    }

    private static func normalizeMixToken(_ value: String?) -> String? {
        guard let value else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+-±/"))
        let trimmed = value.trimmingCharacters(in: allowed.inverted)
        let normalized = trimmed.uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizeSlumpToken(_ value: String?) -> String? {
        guard let value else { return nil }
        let allowed = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "+-±/"))
        var normalized = value.trimmingCharacters(in: allowed.inverted)
        normalized = normalized.replacingOccurrences(of: " ", with: "")
        normalized = normalized.replacingOccurrences(of: "±", with: "+-")
        normalized = normalized.replacingOccurrences(of: "+/-", with: "+-")
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizeMixSpec(_ value: String?) -> String? {
        guard let value else { return nil }
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = expandStandarPrefix(normalized)
        normalized = reorderStandardSpec(normalized)
        normalized = dedupeSpecTokenRuns(normalized)
        normalized = collapseRepeatedSpecSequence(normalized)
        normalized = mergeSplitWordTokens(normalized)
        normalized = moveCorInhToEnd(normalized)
        normalized = normalized.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return normalized.trimmedNonEmpty
    }

    private static func defaultSlump(for code: String?) -> String? {
        guard let code = code?.trimmedNonEmpty?.uppercased() else { return nil }
        if code.hasPrefix("RMES") {
            return "80+-30"
        }
        if code.hasPrefix("RMXS") || code.hasPrefix("RMXW") || code.hasPrefix("RMEW") {
            return "150+-30"
        }
        return nil
    }

    private static func isBrandPrefixToken(_ value: String) -> Bool {
        guard value.count >= 3 else { return false }
        guard value.allSatisfy({ $0.isLetter }) else { return false }
        return value != "STANDARD"
    }

    private static func reorderStandardSpec(_ value: String) -> String {
        let tokens = value.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return value }
        let normalizedTokens = tokens.map { normalizeSpecToken(String($0)) }
        guard let standardIndex = normalizedTokens.firstIndex(of: "STANDARD") else { return value }
        guard let mpaIndex = normalizedTokens.firstIndex(where: { $0.contains("MPA") }) else { return value }
        let prefixBrandIndices = (0..<standardIndex).filter { isBrandPrefixToken(normalizedTokens[$0]) }
        if prefixBrandIndices.isEmpty, standardIndex == 0, mpaIndex == 1 {
            return value
        }

        var afterSet = Set<String>()
        if standardIndex + 1 < normalizedTokens.count {
            for index in (standardIndex + 1)..<normalizedTokens.count {
                let token = normalizedTokens[index]
                if token == "STANDARD" || token.contains("MPA") {
                    continue
                }
                afterSet.insert(token)
            }
        }

        var reordered: [Substring] = []
        if !prefixBrandIndices.isEmpty {
            for index in prefixBrandIndices {
                reordered.append(tokens[index])
            }
        }
        reordered.append(tokens[standardIndex])
        reordered.append(tokens[mpaIndex])
        let prefixBrandSet = Set(prefixBrandIndices)

        for (index, token) in tokens.enumerated() {
            if index == standardIndex || index == mpaIndex || prefixBrandSet.contains(index) {
                continue
            }
            let tokenKey = normalizedTokens[index]
            if index < standardIndex, afterSet.contains(tokenKey) {
                continue
            }
            reordered.append(token)
        }

        return reordered.joined(separator: " ")
    }

    private static func normalizeSpecToken(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "%+-/"))
        let trimmed = value.trimmingCharacters(in: allowed.inverted)
        return trimmed.uppercased()
    }

    private static func isMeaningfulAdditionalToken(_ value: String) -> Bool {
        guard value.count >= 4 else { return false }
        return value.allSatisfy({ $0.isLetter })
    }

    private static func isCoreSpecToken(_ value: String) -> Bool {
        if value.contains("MPA") || value.contains("MM") {
            return true
        }
        if value == "CORINH" {
            return true
        }
        if value.hasPrefix("C") {
            let suffix = value.dropFirst()
            if !suffix.isEmpty, suffix.allSatisfy({ $0.isNumber }) {
                return true
            }
        }
        return false
    }

    private static func mergeSplitWordTokens(_ value: String) -> String {
        let tokens = value.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count > 1 else { return value }
        var merged: [String] = []
        merged.reserveCapacity(tokens.count)
        for token in tokens {
            let str = String(token)
            if str.count == 1, let last = merged.last, str.allSatisfy({ $0.isLetter }),
               last.allSatisfy({ $0.isLetter }), last.count >= 3 {
                merged[merged.count - 1] = last + str
            } else {
                merged.append(str)
            }
        }
        return merged.joined(separator: " ")
    }

    private static func moveCorInhToEnd(_ value: String) -> String {
        let tokens = value.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count > 1 else { return value }
        var regular: [Substring] = []
        var corInh: [Substring] = []
        for token in tokens {
            let normalized = token.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            let key = String(String.UnicodeScalarView(normalized)).uppercased()
            if key == "CORINH" {
                corInh.append(token)
            } else {
                regular.append(token)
            }
        }
        guard !corInh.isEmpty else { return value }
        return (regular + corInh).joined(separator: " ")
    }

    private static func dedupeSpecTokenRuns(_ value: String) -> String {
        let tokens = value.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count > 2 else { return value }
        var result: [Substring] = []
        result.reserveCapacity(tokens.count)

        for token in tokens {
            let key = specTokenKey(token)
            if let last = result.last, key == specTokenKey(last) {
                continue
            }
            if result.count >= 2 {
                let prev2 = result[result.count - 2]
                let middle = result[result.count - 1]
                if key == specTokenKey(prev2),
                   shouldDropSeparatedRepeat(key: key, middle: middle) {
                    continue
                }
            }
            result.append(token)
        }

        if result.count >= 4 {
            let count = result.count
            let lastPair = [specTokenKey(result[count - 2]), specTokenKey(result[count - 1])]
            let prevPair = [specTokenKey(result[count - 4]), specTokenKey(result[count - 3])]
            if lastPair == prevPair {
                return result[..<(count - 2)].joined(separator: " ")
            }
        }

        return result.joined(separator: " ")
    }

    private static func collapseRepeatedSpecSequence(_ value: String) -> String {
        let tokens = value.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count >= 2 else { return value }
        let normalizedTokens = tokens.map { normalizeSpecToken(String($0)) }

        if normalizedTokens.first == "STANDARD" {
            if let dIndex = normalizedTokens.firstIndex(of: "D"), dIndex > 1 {
                let prefix = Array(normalizedTokens[1..<dIndex])
                let suffix = Array(normalizedTokens[(dIndex + 1)...])
                if !prefix.isEmpty, prefix == suffix {
                    let spec = tokens[1..<dIndex].joined(separator: " ")
                    return "STANDARD \(spec)"
                }
            }
            let remaining = Array(normalizedTokens.dropFirst())
            if remaining.count >= 2, remaining.count % 2 == 0 {
                let half = remaining.count / 2
                if remaining[..<half].elementsEqual(remaining[half...]) {
                    let spec = tokens[1..<(half + 1)].joined(separator: " ")
                    return "STANDARD \(spec)"
                }
            }
        }

        if tokens.count % 2 == 0 {
            let half = tokens.count / 2
            if normalizedTokens[..<half].elementsEqual(normalizedTokens[half...]) {
                return tokens[..<half].joined(separator: " ")
            }
        }

        if tokens.count >= 4 {
            let count = tokens.count
            let lastPair = [normalizedTokens[count - 2], normalizedTokens[count - 1]]
            let prevPair = [normalizedTokens[count - 4], normalizedTokens[count - 3]]
            if lastPair == prevPair {
                return tokens[..<(count - 2)].joined(separator: " ")
            }
        }

        return value
    }

    private static func specTokenKey(_ token: Substring) -> String {
        let scalars = token.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars)).uppercased()
    }

    private static func shouldDropRepeatedSpecToken(_ key: String) -> Bool {
        guard key.count >= 3 else { return false }
        return key.allSatisfy { $0.isLetter }
    }

    private static func shouldDropSeparatedRepeat(key: String, middle: Substring) -> Bool {
        guard shouldDropRepeatedSpecToken(key) else { return false }
        let middleKey = specTokenKey(middle)
        guard middleKey.count <= 2, !middleKey.isEmpty else { return false }
        return middleKey.allSatisfy { $0.isLetter }
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

    private static func stripStandardFromDescription(
        _ description: String?,
        customerDescription: String?,
        rawDescription: String?
    ) -> String? {
        guard let description else { return nil }
        guard let customerDescription else { return description }
        guard let rawDescription = rawDescription?.trimmedNonEmpty else { return description }
        guard shouldRemoveStandardFromDescription(rawDescription) else { return description }
        let customerUpper = customerDescription.uppercased()
        guard customerUpper.hasPrefix("STANDARD ") else { return description }
        let descriptionUpper = description.uppercased()
        guard descriptionUpper.hasPrefix("STANDARD") else { return description }
        guard descriptionUpper.contains("MPA") else { return description }
        guard let regex = try? NSRegularExpression(pattern: #"^\s*STANDARD\b\s*"#,
                                                   options: [.caseInsensitive]) else {
            return description
        }
        let range = NSRange(description.startIndex..., in: description)
        let stripped = regex.stringByReplacingMatches(in: description, options: [], range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty
    }

    private static func ensureStandardInDescription(
        _ description: String?,
        customerDescription: String?,
        rawDescription: String?
    ) -> String? {
        guard let description else { return nil }
        guard let customerDescription else { return description }
        guard !hasStandardToken(description) else { return description }
        guard customerDescription.uppercased().hasPrefix("STANDARD ") else { return description }
        if let rawDescription = rawDescription?.trimmedNonEmpty {
            guard hasStandardToken(rawDescription) else { return description }
            guard !hasTruncatedStandardPrefix(rawDescription) else { return description }
            guard !isHeaderLikeDescription(rawDescription) else { return description }
            guard !rawDescriptionHasMixCode(rawDescription) else { return description }
            guard !rawDescriptionHasSlump(rawDescription) else { return description }
        }
        let normalizedCustomer = normalizedSpecWithoutStandard(customerDescription)
        let normalizedDescription = normalizeSpecLine(description)
        guard normalizedCustomer == normalizedDescription else { return description }
        return customerDescription
    }

    private static func normalizeDescriptionFromHeader(
        _ description: String?,
        customerDescription: String?,
        rawDescription: String?
    ) -> String? {
        guard let description else { return nil }
        guard isHeaderLikeDescription(description) else { return description }
        guard let customerDescription else { return description }
        if let stripped = stripStandardFromDescription(customerDescription,
                                                       customerDescription: customerDescription,
                                                       rawDescription: rawDescription) {
            return stripped
        }
        return customerDescription
    }

    private static func hasStandardToken(_ value: String) -> Bool {
        return value.range(of: #"\bSTANDAR[D]?\b"#,
                           options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func hasTruncatedStandardPrefix(_ value: String) -> Bool {
        return value.range(of: #"^\s*STANDAR\b"#,
                           options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func normalizedSpecWithoutStandard(_ value: String) -> String {
        let normalized = normalizeSpecLine(value)
        let tokens = normalized.split(whereSeparator: { $0.isWhitespace })
        guard let first = tokens.first, first == "STANDARD" else {
            return normalized
        }
        return tokens.dropFirst().joined(separator: " ")
    }

    private static func shouldRemoveStandardFromDescription(_ rawDescription: String) -> Bool {
        if hasTruncatedStandardPrefix(rawDescription) {
            return true
        }
        if hasStandardToken(rawDescription) {
            return false
        }
        if isHeaderLikeDescription(rawDescription) {
            return true
        }
        if rawDescriptionHasMixCode(rawDescription) || rawDescriptionHasSlump(rawDescription) {
            return true
        }
        return false
    }

    private static func rawDescriptionHasMixCode(_ value: String) -> Bool {
        return value.range(of: #"\bRMX[A-Z0-9]+\b"#,
                           options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func rawDescriptionHasSlump(_ value: String) -> Bool {
        return value.range(of: #"\b\d+(?:\.\d+)?\s*\+\-\s*\d+(?:\.\d+)?\b"#,
                           options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isHeaderLikeDescription(_ value: String) -> Bool {
        let upper = value.uppercased()
        let cleaned = upper.replacingOccurrences(
            of: #"[^A-Z0-9]+"#,
            with: " ",
            options: .regularExpression
        )
        let tokens = cleaned.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return false }
        let headerWords: Set<String> = [
            "DESCRIPTION",
            "DESC",
            "CODE",
            "CUST",
            "DESCR",
            "QTY",
            "SLUMP",
            "MIX"
        ]
        return tokens.allSatisfy { headerWords.contains(String($0)) }
    }

    private static func expandStandarPrefix(_ value: String) -> String {
        guard value.range(of: #"^\s*STANDAR\b"#, options: [.regularExpression, .caseInsensitive]) != nil else {
            return value
        }
        let upper = value.uppercased()
        guard upper.contains("MPA") else { return value }
        guard let regex = try? NSRegularExpression(pattern: #"^\s*STANDAR\b"#,
                                                   options: [.caseInsensitive]) else {
            return value
        }
        let range = NSRange(value.startIndex..., in: value)
        let expanded = regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: "STANDARD")
        return expanded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeDeliveryAddress(_ value: String?) -> String? {
        guard let value = value?.trimmedNonEmpty else { return nil }
        let lines = value.split(whereSeparator: \.isNewline)
        let filtered = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if isPurchaseOrderLine(trimmed) {
                return nil
            }
            return trimmed
        }
        guard !filtered.isEmpty else { return nil }
        let joined = filtered.joined(separator: " ")
        let collapsed = joined.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmedNonEmpty
    }

    private static func isPurchaseOrderLine(_ value: String) -> Bool {
        return value.range(of: #"^\s*P\.?O\.?\b"#,
                           options: [.regularExpression, .caseInsensitive]) != nil
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

    private static func stripLeadingMixQty(from value: String?) -> String? {
        guard let value else { return nil }
        let pattern = #"^\s*\d+(?:\.\d+)?\s*m(?:3|³)\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return value
        }
        let range = NSRange(value.startIndex..., in: value)
        let stripped = regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func reorderExtraCharges(_ charges: [ExtraCharge]) -> [ExtraCharge] {
        guard charges.count > 1 else { return charges }
        var regular: [ExtraCharge] = []
        var siteWash: [ExtraCharge] = []
        for charge in charges {
            if isSiteWashCharge(charge.description) {
                siteWash.append(charge)
            } else {
                regular.append(charge)
            }
        }
        return regular + siteWash
    }

    private static func isSiteWashCharge(_ description: String?) -> Bool {
        guard let description else { return false }
        let collapsed = description
            .uppercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.contains("SITE WASH")
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
