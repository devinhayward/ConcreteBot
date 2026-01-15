import Foundation

enum PlaywrightError: Error, CustomStringConvertible {
    case missingScript
    case processFailed(String)

    var description: String {
        switch self {
        case .missingScript:
            return "Missing Playwright runner script in resources."
        case .processFailed(let detail):
            return "Playwright runner failed: \(detail)"
        }
    }
}

enum PlaywrightClient {
    static func run(
        prompt: String,
        pdfPath: String,
        profileDir: String,
        headless: Bool,
        browserChannel: String?,
        manualLogin: Bool
    ) throws -> String {
        guard let scriptURL = Bundle.module.url(forResource: "playwright_client", withExtension: "js") else {
            throw PlaywrightError.missingScript
        }

        let promptFile = try writePromptFile(prompt)
        defer { try? FileManager.default.removeItem(at: promptFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var arguments = [
            "node",
            scriptURL.path,
            "--prompt-file",
            promptFile.path,
            "--pdf",
            pdfPath,
            "--profile",
            expandingTilde(in: profileDir),
            "--headless",
            headless ? "true" : "false"
        ]
        if let browserChannel {
            arguments.append(contentsOf: ["--channel", browserChannel])
        }
        if manualLogin {
            arguments.append("--manual-login")
        }
        process.arguments = arguments

        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: data, encoding: .utf8) ?? ""
        let stderr = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw PlaywrightError.processFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func writePromptFile(_ prompt: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("concretebot_prompt.txt")
        try prompt.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static func expandingTilde(in path: String) -> String {
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        return path
    }
}
