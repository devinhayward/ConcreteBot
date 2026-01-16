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
}

func printUsage() {
    let usage = """
    ConcreteBot

    Usage:
      concretebot extract --pdf <path> --pages <range> [--out <dir>] [--print-prompt] [--response-file <path>] [--response-stdin]

    Options:
      --pdf       Path to the PDF file.
      --pages     Page range to extract (e.g., 2-23).
      --out       Output directory (default: current directory).
      --print-prompt   Print the rendered prompt and exit.
      --response-file  Path to a file containing model JSON response.
      --response-stdin Read model JSON response from stdin.
    """
    print(usage)
}

func parseCLI() throws -> (command: String, options: CLIOptions) {
    var args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else {
        throw CLIError.missingCommand
    }
    args.removeFirst()

    if command == "--help" || command == "-h" {
        printUsage()
        exit(0)
    }

    guard command == "extract" else {
        throw CLIError.unknownCommand(command)
    }

    var pdfPath: String?
    var pages: String?
    var outputDir = FileManager.default.currentDirectoryPath
    var printPrompt = false
    var responseFile: String?
    var responseStdin = false

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
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw CLIError.invalidArgument(arg)
        }
    }

    guard let pdfPathValue = pdfPath else { throw CLIError.missingArgument("--pdf") }
    guard let pagesValue = pages else { throw CLIError.missingArgument("--pages") }

    return (
        command,
        CLIOptions(
            pdfPath: pdfPathValue,
            pages: pagesValue,
            outputDir: outputDir,
            printPrompt: printPrompt,
            responseFile: responseFile,
            responseStdin: responseStdin
        )
    )
}

func run() throws {
    let (command, options) = try parseCLI()
    switch command {
    case "extract":
        try Extract.run(options: options)
    default:
        throw CLIError.unknownCommand(command)
    }
}

do {
    try run()
} catch {
    fputs("Error: \(error)\n", stderr)
    printUsage()
    exit(1)
}
