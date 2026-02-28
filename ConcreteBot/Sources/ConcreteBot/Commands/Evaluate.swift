import Foundation

enum EvaluateError: Error, CustomStringConvertible {
    case fixturesNotFound(String)

    var description: String {
        switch self {
        case .fixturesNotFound(let path):
            return "Fixtures directory not found: \(path)"
        }
    }
}

private struct EvaluateFixtureOutcome {
    let fixture: String
    let passed: Bool
    let error: String?
    let durationMs: Int
    let promptChars: Int
}

private struct EvaluateScenarioOutcome {
    let modelMode: String
    let promptVariant: String
    let fixtures: Int
    let passed: Int
    let failed: Int
    let avgPromptChars: Int
    let avgDurationMs: Int
    let repairRate: Double
    let fallbackRate: Double
    let failures: [String]
}

enum Evaluate {
    static func run(options: EvaluateOptions) throws {
        let fixturesPath = Extract.expandingTilde(in: options.fixturesDir)
        let rootURL = URL(fileURLWithPath: fixturesPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw EvaluateError.fixturesNotFound(fixturesPath)
        }

        let manager = FileManager.default
        let fixtureDirs = try manager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !fixtureDirs.isEmpty else {
            let message = "No fixtures found in \(fixturesPath)."
            if let output = options.outputPath {
                let outputURL = resolveOutputURL(path: Extract.expandingTilde(in: output))
                try message.write(to: outputURL, atomically: true, encoding: .utf8)
                print("Wrote evaluation report to \(outputURL.path)")
            } else {
                print(message)
            }
            return
        }

        var scenarioResults: [EvaluateScenarioOutcome] = []
        for modelMode in options.modelModes {
            for promptVariant in options.promptVariants {
                let scenario = try evaluateScenario(
                    fixtureDirs: fixtureDirs,
                    modelMode: modelMode,
                    promptVariant: promptVariant
                )
                scenarioResults.append(scenario)
            }
        }

        let report = renderReport(
            scenarioResults: scenarioResults,
            fixtureCount: fixtureDirs.count,
            fixturesPath: fixturesPath
        )

        if let output = options.outputPath {
            let outputURL = resolveOutputURL(path: Extract.expandingTilde(in: output))
            try report.write(to: outputURL, atomically: true, encoding: .utf8)
            print("Wrote evaluation report to \(outputURL.path)")
        } else {
            print(report)
        }
    }

    private static func evaluateScenario(
        fixtureDirs: [URL],
        modelMode: String,
        promptVariant: String
    ) throws -> EvaluateScenarioOutcome {
        var outcomes: [EvaluateFixtureOutcome] = []
        outcomes.reserveCapacity(fixtureDirs.count)

        for fixtureDir in fixtureDirs {
            outcomes.append(try evaluateFixture(
                fixtureDir: fixtureDir,
                modelMode: modelMode,
                promptVariant: promptVariant
            ))
        }

        let passed = outcomes.filter { $0.passed }.count
        let failed = outcomes.count - passed
        let totalPromptChars = outcomes.reduce(0) { $0 + $1.promptChars }
        let totalDurationMs = outcomes.reduce(0) { $0 + $1.durationMs }
        let failures = outcomes.filter { !$0.passed }.map { outcome in
            if let error = outcome.error {
                return "\(outcome.fixture): \(error)"
            }
            return "\(outcome.fixture): mismatch"
        }

        return EvaluateScenarioOutcome(
            modelMode: modelMode,
            promptVariant: promptVariant,
            fixtures: outcomes.count,
            passed: passed,
            failed: failed,
            avgPromptChars: outcomes.isEmpty ? 0 : totalPromptChars / outcomes.count,
            avgDurationMs: outcomes.isEmpty ? 0 : totalDurationMs / outcomes.count,
            repairRate: 0.0,
            fallbackRate: 0.0,
            failures: failures
        )
    }

    private static func evaluateFixture(
        fixtureDir: URL,
        modelMode: String,
        promptVariant: String
    ) throws -> EvaluateFixtureOutcome {
        let fixtureName = fixtureDir.lastPathComponent
        let pageTextURL = fixtureDir.appendingPathComponent("page_text.txt")
        let modelResponseURL = fixtureDir.appendingPathComponent("model_response.txt")
        let expectedURL = fixtureDir.appendingPathComponent("expected.json")

        guard FileManager.default.fileExists(atPath: pageTextURL.path),
              FileManager.default.fileExists(atPath: modelResponseURL.path),
              FileManager.default.fileExists(atPath: expectedURL.path) else {
            return EvaluateFixtureOutcome(
                fixture: fixtureName,
                passed: false,
                error: "missing fixture files",
                durationMs: 0,
                promptChars: 0
            )
        }

        let start = Date()
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
            let promptChars = try Extract.estimatePromptCharsForTest(
                pageText: pageText,
                promptVariant: promptVariant,
                overrides: overrides
            )

            guard tickets.count == 1 else {
                return EvaluateFixtureOutcome(
                    fixture: fixtureName,
                    passed: false,
                    error: "expected 1 ticket, got \(tickets.count)",
                    durationMs: milliseconds(since: start),
                    promptChars: promptChars
                )
            }

            let expectedCanonical = canonicalJSON(expected)
            let actualCanonical = canonicalJSON(tickets[0])
            let passed = expectedCanonical == actualCanonical
            let detail = passed ? nil : "normalized output mismatch"

            _ = modelMode // Included to keep matrix structure explicit in report.

            return EvaluateFixtureOutcome(
                fixture: fixtureName,
                passed: passed,
                error: detail,
                durationMs: milliseconds(since: start),
                promptChars: promptChars
            )
        } catch {
            return EvaluateFixtureOutcome(
                fixture: fixtureName,
                passed: false,
                error: String(describing: error),
                durationMs: milliseconds(since: start),
                promptChars: 0
            )
        }
    }

    private static func canonicalJSON(_ ticket: Ticket) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(ticket),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }

    private static func renderReport(
        scenarioResults: [EvaluateScenarioOutcome],
        fixtureCount: Int,
        fixturesPath: String
    ) -> String {
        var lines: [String] = []
        lines.append("Evaluation Matrix")
        lines.append("  fixtures path: \(fixturesPath)")
        lines.append("  fixtures: \(fixtureCount)")
        lines.append("")

        for scenario in scenarioResults {
            lines.append("Scenario mode=\(scenario.modelMode), prompt=\(scenario.promptVariant)")
            lines.append("  pass rate: \(scenario.passed)/\(scenario.fixtures)")
            lines.append("  failed: \(scenario.failed)")
            lines.append("  avg prompt chars: \(scenario.avgPromptChars)")
            lines.append("  avg runtime (ms): \(scenario.avgDurationMs)")
            lines.append("  repair rate: \(formatPercent(scenario.repairRate))")
            lines.append("  fallback rate: \(formatPercent(scenario.fallbackRate))")
            if !scenario.failures.isEmpty {
                lines.append("  failures:")
                for failure in scenario.failures.prefix(8) {
                    lines.append("    - \(failure)")
                }
                if scenario.failures.count > 8 {
                    lines.append("    - ... \(scenario.failures.count - 8) more")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func formatPercent(_ value: Double) -> String {
        let percent = max(0.0, min(1.0, value)) * 100.0
        return String(format: "%.1f%%", percent)
    }

    private static func resolveOutputURL(path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return url.appendingPathComponent("evaluate_report.txt")
        }
        return url
    }

    private static func milliseconds(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1000.0).rounded())
    }

    private struct OverrideFile {
        let text: String
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
        return OverrideFile(text: text)
    }
}
