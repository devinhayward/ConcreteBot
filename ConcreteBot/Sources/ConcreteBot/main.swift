import Foundation

enum CLIError: Error, CustomStringConvertible {
    case missingCommand
    case unknownCommand(String)
    case missingArgument(String)
    case invalidArgument(String)
    case runtime(String)

    var description: String {
        switch self {
        case .missingCommand:
            return "Missing command."
        case .unknownCommand(let command):
            return "Unknown command: \(command)"
        case .missingArgument(let name):
            return "Missing required argument: \(name)"
        case .invalidArgument(let detail):
            return "Invalid argument: \(detail)"
        case .runtime(let detail):
            return detail
        }
    }
}

struct CLIOptions {
    let pdfPath: String
    let pages: String
    let outputDir: String
    let printPrompt: Bool
    let responseFile: String?
    let responseStdin: Bool
    let responseOut: String?
    let modelMode: String
    let runReport: String?
    let promptVariant: String
}

struct BatchOptions {
    let csvPath: String
    let pages: String
    let outputDir: String
    let printPrompt: Bool
}

struct EvaluateOptions {
    let fixturesDir: String
    let outputPath: String?
    let modelModes: [String]
    let promptVariants: [String]
}

enum CLICommand {
    case extract(CLIOptions)
    case batch(BatchOptions)
    case regress(RegressionOptions)
    case evaluate(EvaluateOptions)
    case dumpText(DumpTextOptions)
    case promptOverrides(PromptOverridesOptions)
}

func printUsage() {
    let usage = """
    ConcreteBot

    Usage:
      concretebot extract --pdf <path> --pages <range|auto> [--out <dir>] [--print-prompt] [--response-file <path>] [--response-stdin] [--response-out <path>] [--model-mode <auto|guided|legacy>] [--prompt-variant <adaptive|compact|minimal|none>] [--run-report <path>]
      concretebot batch --csv <path> [--pages <range|auto>] [--out <dir>] [--print-prompt]
      concretebot regress [--fixtures <dir>] [--out <path>]
      concretebot evaluate [--fixtures <dir>] [--out <path>] [--model-modes <csv>] [--prompt-variants <csv>]
      concretebot dump-text --pdf <path> --pages <range> [--out <path|dir>]
      concretebot prompt-overrides --pdf <path> --pages <range> [--out <dir>]

    Options:
      --pdf       Path to the PDF file.
      --csv       Path to a CSV file with columns: pdf,pages (pages optional).
      --pages     Page range to extract (e.g., 2-23) or "auto".
      --out       Output directory (default: current directory).
      --print-prompt   Print the rendered prompt and exit.
      --response-file  Path to a file containing model JSON response.
      --response-stdin Read model JSON response from stdin.
      --response-out   Write raw model response to a file (extract only).
      --model-mode     Extraction model mode: auto, guided, or legacy (default: auto).
      --prompt-variant Extraction prompt strategy: adaptive, compact, minimal, or none (default: adaptive).
      --run-report     Write per-page extraction telemetry JSON report (extract only).
      --fixtures  Path to regression fixtures directory (default: Tests/ConcreteBotTests/Fixtures).
      --model-modes    Comma-separated evaluate modes (default: auto,guided,legacy).
      --prompt-variants Comma-separated evaluate prompt variants (default: adaptive,compact,minimal,none).
      --out       Output path for regression report (file or directory; regress only).
      --out       Output path for evaluation report (file or directory; evaluate only).
      --out       Output path for raw text (file or directory; dump-text only).
      --out       Output directory for prompt override files (prompt-overrides only).
    """
    print(usage)
}

func parseCLI() throws -> CLICommand {
    return try parseCLI(arguments: CommandLine.arguments)
}

func parseCLI(arguments: [String]) throws -> CLICommand {
    var args = Array(arguments.dropFirst())
    guard let command = args.first else {
        throw CLIError.missingCommand
    }
    args.removeFirst()

    if command == "--help" || command == "-h" {
        printUsage()
        exit(0)
    }

    switch command {
    case "extract":
        return .extract(try parseExtractArgs(args))
    case "batch":
        return .batch(try parseBatchArgs(args))
    case "regress":
        return .regress(try parseRegressionArgs(args))
    case "evaluate":
        return .evaluate(try parseEvaluateArgs(args))
    case "dump-text":
        return .dumpText(try parseDumpTextArgs(args))
    case "prompt-overrides":
        return .promptOverrides(try parsePromptOverridesArgs(args))
    default:
        throw CLIError.unknownCommand(command)
    }
}

private func parseExtractArgs(_ args: [String]) throws -> CLIOptions {
    var pdfPath: String?
    var pages: String?
    var outputDir = FileManager.default.currentDirectoryPath
    var printPrompt = false
    var responseFile: String?
    var responseStdin = false
    var responseOut: String?
    var modelMode = "auto"
    var runReport: String?
    var promptVariant = "adaptive"

    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--pdf":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--pdf") }
            pdfPath = args[index + 1]
            index += 2
        case "--pages":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--pages") }
            pages = args[index + 1]
            index += 2
        case "--out":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--out") }
            outputDir = args[index + 1]
            index += 2
        case "--print-prompt":
            printPrompt = true
            index += 1
        case "--response-file":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--response-file") }
            responseFile = args[index + 1]
            index += 2
        case "--response-stdin":
            responseStdin = true
            index += 1
        case "--response-out":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--response-out") }
            responseOut = args[index + 1]
            index += 2
        case "--model-mode":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--model-mode") }
            let value = args[index + 1].lowercased()
            guard ["auto", "guided", "legacy"].contains(value) else {
                throw CLIError.invalidArgument("--model-mode must be one of: auto, guided, legacy.")
            }
            modelMode = value
            index += 2
        case "--run-report":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--run-report") }
            runReport = args[index + 1]
            index += 2
        case "--prompt-variant":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--prompt-variant") }
            let value = args[index + 1].lowercased()
            guard Extract.supportedPromptVariants.contains(value) else {
                throw CLIError.invalidArgument(
                    "--prompt-variant must be one of: \(Extract.supportedPromptVariants.joined(separator: ", "))."
                )
            }
            promptVariant = value
            index += 2
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw CLIError.invalidArgument(arg)
        }
    }

    guard let pdfPathValue = pdfPath else { throw CLIError.missingArgument("--pdf") }
    guard let pagesValue = pages else { throw CLIError.missingArgument("--pages") }

    return CLIOptions(
        pdfPath: pdfPathValue,
        pages: pagesValue,
        outputDir: outputDir,
        printPrompt: printPrompt,
        responseFile: responseFile,
        responseStdin: responseStdin,
        responseOut: responseOut,
        modelMode: modelMode,
        runReport: runReport,
        promptVariant: promptVariant
    )
}

private func parseBatchArgs(_ args: [String]) throws -> BatchOptions {
    var csvPath: String?
    var pages = "auto"
    var outputDir = FileManager.default.currentDirectoryPath
    var printPrompt = false

    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--csv":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--csv") }
            csvPath = args[index + 1]
            index += 2
        case "--pages":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--pages") }
            pages = args[index + 1]
            index += 2
        case "--out":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--out") }
            outputDir = args[index + 1]
            index += 2
        case "--print-prompt":
            printPrompt = true
            index += 1
        case "--response-file":
            throw CLIError.invalidArgument("--response-file is not supported in batch mode.")
        case "--response-stdin":
            throw CLIError.invalidArgument("--response-stdin is not supported in batch mode.")
        case "--response-out":
            throw CLIError.invalidArgument("--response-out is not supported in batch mode.")
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw CLIError.invalidArgument(arg)
        }
    }

    guard let csvPathValue = csvPath else { throw CLIError.missingArgument("--csv") }

    return BatchOptions(
        csvPath: csvPathValue,
        pages: pages,
        outputDir: outputDir,
        printPrompt: printPrompt
    )
}

private func parseRegressionArgs(_ args: [String]) throws -> RegressionOptions {
    var fixturesDir = "Tests/ConcreteBotTests/Fixtures"
    var outputPath: String?

    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--fixtures":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--fixtures") }
            fixturesDir = args[index + 1]
            index += 2
        case "--out":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--out") }
            outputPath = args[index + 1]
            index += 2
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw CLIError.invalidArgument(arg)
        }
    }

    return RegressionOptions(
        fixturesDir: fixturesDir,
        outputPath: outputPath
    )
}

private func parseEvaluateArgs(_ args: [String]) throws -> EvaluateOptions {
    var fixturesDir = "Tests/ConcreteBotTests/Fixtures"
    var outputPath: String?
    var modelModes = Extract.supportedModelModes
    var promptVariants = Extract.supportedPromptVariants

    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--fixtures":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--fixtures") }
            fixturesDir = args[index + 1]
            index += 2
        case "--out":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--out") }
            outputPath = args[index + 1]
            index += 2
        case "--model-modes":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--model-modes") }
            modelModes = try parseCSVArgumentList(args[index + 1], optionName: "--model-modes")
            index += 2
        case "--prompt-variants":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--prompt-variants") }
            promptVariants = try parseCSVArgumentList(args[index + 1], optionName: "--prompt-variants")
            index += 2
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw CLIError.invalidArgument(arg)
        }
    }

    let unsupportedModes = modelModes.filter { !Extract.supportedModelModes.contains($0) }
    if !unsupportedModes.isEmpty {
        throw CLIError.invalidArgument(
            "--model-modes contains unsupported values: \(unsupportedModes.joined(separator: ", "))."
        )
    }
    let unsupportedVariants = promptVariants.filter { !Extract.supportedPromptVariants.contains($0) }
    if !unsupportedVariants.isEmpty {
        throw CLIError.invalidArgument(
            "--prompt-variants contains unsupported values: \(unsupportedVariants.joined(separator: ", "))."
        )
    }

    return EvaluateOptions(
        fixturesDir: fixturesDir,
        outputPath: outputPath,
        modelModes: modelModes,
        promptVariants: promptVariants
    )
}

private func parseCSVArgumentList(_ raw: String, optionName: String) throws -> [String] {
    let parts = raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
    guard !parts.isEmpty else {
        throw CLIError.invalidArgument("\(optionName) requires at least one value.")
    }
    return parts
}

private func parseDumpTextArgs(_ args: [String]) throws -> DumpTextOptions {
    var pdfPath: String?
    var pages: String?
    var outputPath: String?

    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--pdf":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--pdf") }
            pdfPath = args[index + 1]
            index += 2
        case "--pages":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--pages") }
            pages = args[index + 1]
            index += 2
        case "--out":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--out") }
            outputPath = args[index + 1]
            index += 2
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw CLIError.invalidArgument(arg)
        }
    }

    guard let pdfPathValue = pdfPath else { throw CLIError.missingArgument("--pdf") }
    guard let pagesValue = pages else { throw CLIError.missingArgument("--pages") }

    return DumpTextOptions(
        pdfPath: pdfPathValue,
        pages: pagesValue,
        outputPath: outputPath
    )
}

private func parsePromptOverridesArgs(_ args: [String]) throws -> PromptOverridesOptions {
    var pdfPath: String?
    var pages: String?
    var outputDir = FileManager.default.currentDirectoryPath

    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--pdf":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--pdf") }
            pdfPath = args[index + 1]
            index += 2
        case "--pages":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--pages") }
            pages = args[index + 1]
            index += 2
        case "--out":
            guard index + 1 < args.count else { throw CLIError.missingArgument("--out") }
            outputDir = args[index + 1]
            index += 2
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw CLIError.invalidArgument(arg)
        }
    }

    guard let pdfPathValue = pdfPath else { throw CLIError.missingArgument("--pdf") }
    guard let pagesValue = pages else { throw CLIError.missingArgument("--pages") }

    return PromptOverridesOptions(
        pdfPath: pdfPathValue,
        pages: pagesValue,
        outputDir: outputDir
    )
}

func run() throws {
    let command = try parseCLI()
    switch command {
    case .extract(let options):
        try Extract.run(options: options)
    case .batch(let options):
        try Batch.run(options: options)
    case .regress(let options):
        try Regression.run(options: options)
    case .evaluate(let options):
        try Evaluate.run(options: options)
    case .dumpText(let options):
        try DumpText.run(options: options)
    case .promptOverrides(let options):
        try PromptOverrides.run(options: options)
    }
}

do {
    try run()
} catch {
    fputs("Error: \(error)\n", stderr)
    printUsage()
    exit(1)
}
