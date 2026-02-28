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
}

struct BatchOptions {
    let csvPath: String
    let pages: String
    let outputDir: String
    let printPrompt: Bool
}

enum CLICommand {
    case extract(CLIOptions)
    case batch(BatchOptions)
}

func printUsage() {
    let usage = """
    ConcreteBot

    Usage:
      concretebot extract --pdf <path> --pages <range|auto> [--out <dir>] [--print-prompt] [--response-file <path>] [--response-stdin] [--response-out <path>]
      concretebot batch --csv <path> [--pages <range|auto>] [--out <dir>] [--print-prompt]

    Options:
      --pdf       Path to the PDF file.
      --csv       Path to a CSV file with columns: pdf,pages (pages optional).
      --pages     Page range to extract (e.g., 2-23) or "auto".
      --out       Output directory (default: current directory).
      --print-prompt   Print the rendered prompt and exit.
      --response-file  Path to a file containing model JSON response.
      --response-stdin Read model JSON response from stdin.
      --response-out   Write raw model response to a file (extract only).
    """
    print(usage)
}

func parseCLI() throws -> CLICommand {
    var args = Array(CommandLine.arguments.dropFirst())
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
        responseOut: responseOut
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

func run() throws {
    let command = try parseCLI()
    switch command {
    case .extract(let options):
        try Extract.run(options: options)
    case .batch(let options):
        try Batch.run(options: options)
    }
}

do {
    try run()
} catch {
    fputs("Error: \(error)\n", stderr)
    printUsage()
    exit(1)
}
