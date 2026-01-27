import Foundation

enum RegressionError: Error, CustomStringConvertible {
    case fixturesNotFound(String)

    var description: String {
        switch self {
        case .fixturesNotFound(let path):
            return "Fixtures directory not found: \(path)"
        }
    }
}

struct RegressionOptions {
    let fixturesDir: String
    let outputPath: String?
}

private struct FieldDiff {
    let path: String
    let expected: String
    let actual: String
}

private struct FixtureResult {
    let name: String
    var diffs: [FieldDiff] = []
    var errors: [String] = []

    var isPassing: Bool {
        errors.isEmpty && diffs.isEmpty
    }
}

enum Regression {
    static func run(options: RegressionOptions) throws {
        let fixturesPath = Extract.expandingTilde(in: options.fixturesDir)
        let rootURL = URL(fileURLWithPath: fixturesPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw RegressionError.fixturesNotFound(fixturesPath)
        }

        let resolvedOutputPath = options.outputPath.map { Extract.expandingTilde(in: $0) }
        let manager = FileManager.default
        let fixtureDirs = try manager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !fixtureDirs.isEmpty else {
            let emptyMessage = "No fixtures found in \(fixturesPath)."
            if let outputPath = resolvedOutputPath {
                let outputURL = resolveOutputURL(path: outputPath)
                try emptyMessage.write(to: outputURL, atomically: true, encoding: .utf8)
                print("Wrote regression report to \(outputURL.path)")
            } else {
                print(emptyMessage)
            }
            return
        }

        var results: [FixtureResult] = []
        results.reserveCapacity(fixtureDirs.count)
        for fixtureDir in fixtureDirs {
            results.append(runFixture(at: fixtureDir))
        }

        let report = renderReport(results: results)
        if let outputPath = resolvedOutputPath {
            let outputURL = resolveOutputURL(path: outputPath)
            try report.write(to: outputURL, atomically: true, encoding: .utf8)
            print("Wrote regression report to \(outputURL.path)")
        } else {
            print(report)
        }
    }

    private static func runFixture(at fixtureDir: URL) -> FixtureResult {
        let fixtureName = fixtureDir.lastPathComponent
        var result = FixtureResult(name: fixtureName)

        let pageTextURL = fixtureDir.appendingPathComponent("page_text.txt")
        let modelResponseURL = fixtureDir.appendingPathComponent("model_response.txt")
        let expectedURL = fixtureDir.appendingPathComponent("expected.json")

        guard FileManager.default.fileExists(atPath: pageTextURL.path) else {
            result.errors.append("Missing page_text.txt")
            return result
        }
        guard FileManager.default.fileExists(atPath: modelResponseURL.path) else {
            result.errors.append("Missing model_response.txt")
            return result
        }
        guard FileManager.default.fileExists(atPath: expectedURL.path) else {
            result.errors.append("Missing expected.json")
            return result
        }

        do {
            let pageText = try String(contentsOf: pageTextURL, encoding: .utf8)
            let modelResponse = try String(contentsOf: modelResponseURL, encoding: .utf8)
            let expectedJSON = try String(contentsOf: expectedURL, encoding: .utf8)

            let expected = try TicketValidator.decode(json: expectedJSON)
            let overrides = loadOverrides(from: fixtureDir)
            let tickets = try Extract.processPageForTest(
                pageText: pageText,
                modelResponse: modelResponse,
                overrides: overrides
            )
            guard tickets.count == 1 else {
                result.errors.append("Expected 1 ticket, got \(tickets.count)")
                return result
            }

            let actual = tickets[0]
            result.diffs = diffTickets(expected: expected, actual: actual)
        } catch {
            result.errors.append(error.localizedDescription)
        }

        return result
    }

    private static func diffTickets(expected: Ticket, actual: Ticket) -> [FieldDiff] {
        var diffs: [FieldDiff] = []

        compareString("Ticket No.", expected.ticketNumber, actual.ticketNumber, diffs: &diffs)
        compareString("Delivery Date", expected.deliveryDate, actual.deliveryDate, diffs: &diffs)
        compareString("Delivery Time", expected.deliveryTime, actual.deliveryTime, diffs: &diffs)
        compareString("Delivery Address", expected.deliveryAddress, actual.deliveryAddress, diffs: &diffs)

        compareMixRow(path: "Mix Customer", expected: expected.mixCustomer, actual: actual.mixCustomer, diffs: &diffs)
        compareMixRow(path: "Mix Additional 1", expected: expected.mixAdditional1, actual: actual.mixAdditional1, diffs: &diffs)
        compareMixRow(path: "Mix Additional 2", expected: expected.mixAdditional2, actual: actual.mixAdditional2, diffs: &diffs)

        if expected.extraCharges.count != actual.extraCharges.count {
            diffs.append(FieldDiff(
                path: "Extra Charges.count",
                expected: String(expected.extraCharges.count),
                actual: String(actual.extraCharges.count)
            ))
        }

        let maxCount = max(expected.extraCharges.count, actual.extraCharges.count)
        for index in 0..<maxCount {
            if index >= expected.extraCharges.count {
                diffs.append(FieldDiff(
                    path: "Extra Charges[\(index)]",
                    expected: "missing",
                    actual: "present"
                ))
                continue
            }
            if index >= actual.extraCharges.count {
                diffs.append(FieldDiff(
                    path: "Extra Charges[\(index)]",
                    expected: "present",
                    actual: "missing"
                ))
                continue
            }

            let expectedCharge = expected.extraCharges[index]
            let actualCharge = actual.extraCharges[index]
            compareString(
                "Extra Charges[\(index)].Description",
                expectedCharge.description,
                actualCharge.description,
                diffs: &diffs
            )
            compareString(
                "Extra Charges[\(index)].Qty",
                expectedCharge.qty,
                actualCharge.qty,
                diffs: &diffs
            )
        }

        return diffs
    }

    private static func compareMixRow(
        path: String,
        expected: MixRow?,
        actual: MixRow?,
        diffs: inout [FieldDiff]
    ) {
        guard expected != nil || actual != nil else { return }
        guard let expected, let actual else {
            diffs.append(FieldDiff(
                path: path,
                expected: describeMixRow(expected),
                actual: describeMixRow(actual)
            ))
            return
        }

        compareString("\(path).Qty", expected.qty, actual.qty, diffs: &diffs)
        compareString("\(path).Cust. Descr.", expected.customerDescription, actual.customerDescription, diffs: &diffs)
        compareString("\(path).Description", expected.description, actual.description, diffs: &diffs)
        compareString("\(path).Code", expected.code, actual.code, diffs: &diffs)
        compareString("\(path).Slump", expected.slump, actual.slump, diffs: &diffs)
    }

    private static func compareString(
        _ path: String,
        _ expected: String?,
        _ actual: String?,
        diffs: inout [FieldDiff]
    ) {
        if expected != actual {
            diffs.append(FieldDiff(
                path: path,
                expected: displayValue(expected),
                actual: displayValue(actual)
            ))
        }
    }

    private static func describeMixRow(_ row: MixRow?) -> String {
        guard let row else { return "null" }
        let qty = displayValue(row.qty)
        let cust = displayValue(row.customerDescription)
        let desc = displayValue(row.description)
        let code = displayValue(row.code)
        let slump = displayValue(row.slump)
        return "{Qty:\(qty), Cust. Descr.:\(cust), Description:\(desc), Code:\(code), Slump:\(slump)}"
    }

    private static func displayValue(_ value: String?) -> String {
        guard let value else { return "null" }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func renderReport(results: [FixtureResult]) -> String {
        var lines: [String] = []
        var passed = 0
        var failed = 0
        var totalDiffs = 0
        var summaryCounts: [String: Int] = [:]

        for result in results {
            if result.isPassing {
                passed += 1
            } else {
                failed += 1
            }
            totalDiffs += result.diffs.count

            lines.append("Fixture \(result.name): \(result.isPassing ? "PASS" : "FAIL")")
            if !result.errors.isEmpty {
                for error in result.errors {
                    lines.append("  error: \(error)")
                }
            }
            if !result.diffs.isEmpty {
                lines.append("  diffs (\(result.diffs.count)):")
                for diff in result.diffs {
                    lines.append("    - \(diff.path): expected \(diff.expected) got \(diff.actual)")
                    let normalized = normalizePathForSummary(diff.path)
                    summaryCounts[normalized, default: 0] += 1
                }
            }
            lines.append("")
        }

        lines.append("Summary:")
        lines.append("  fixtures: \(results.count)")
        lines.append("  passed: \(passed)")
        lines.append("  failed: \(failed)")
        lines.append("  diffs: \(totalDiffs)")
        if !summaryCounts.isEmpty {
            lines.append("  mismatch counts:")
            let sorted = summaryCounts.sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }
            for (path, count) in sorted {
                lines.append("    - \(path): \(count)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func normalizePathForSummary(_ path: String) -> String {
        let pattern = #"\[\d+\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return path
        }
        let range = NSRange(path.startIndex..., in: path)
        return regex.stringByReplacingMatches(in: path, options: [], range: range, withTemplate: "[]")
    }

    private static func resolveOutputURL(path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return url.appendingPathComponent("regression_report.txt")
        }
        return url
    }

    private struct OverrideFile {
        let text: String
        let modified: Date
    }

    private static func loadOverrides(from fixtureDir: URL) -> Extract.ExtractionOverrides? {
        let mixText = readOverride(in: fixtureDir, name: "mix_text.txt")
        let mixRowLines = readOverride(in: fixtureDir, name: "mix_row_lines.txt")
        var mixParsedHints = readOverride(in: fixtureDir, name: "mix_parsed_hints.txt")
        let extraChargesText = readOverride(in: fixtureDir, name: "extra_charges_text.txt")

        if mixRowLines != nil {
            mixParsedHints = nil
        }

        if mixText == nil, mixRowLines == nil, mixParsedHints == nil, extraChargesText == nil {
            return nil
        }

        return Extract.ExtractionOverrides(
            mixText: mixText?.text,
            mixRowLines: mixRowLines?.text,
            mixParsedHints: mixParsedHints?.text,
            extraChargesText: extraChargesText?.text
        )
    }

    private static func readOverride(in fixtureDir: URL, name: String) -> OverrideFile? {
        let url = fixtureDir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let modified = attributes[.modificationDate] as? Date ?? Date.distantPast
        return OverrideFile(text: text, modified: modified)
    }
}
