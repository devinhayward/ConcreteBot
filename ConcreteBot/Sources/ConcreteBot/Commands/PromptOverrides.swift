import Foundation
import PDFKit

enum PromptOverridesError: Error, CustomStringConvertible {
    case invalidPageRange(String)
    case pdfLoadFailed(String)
    case pageOutOfRange(Int, Int)
    case outputPathNotDirectory(String)

    var description: String {
        switch self {
        case .invalidPageRange(let detail):
            return "Invalid page range: \(detail)"
        case .pdfLoadFailed(let path):
            return "Failed to load PDF: \(path)"
        case .pageOutOfRange(let page, let total):
            return "Page \(page) is out of range (1-\(total))."
        case .outputPathNotDirectory(let path):
            return "Output path must be a directory: \(path)"
        }
    }
}

struct PromptOverridesOptions {
    let pdfPath: String
    let pages: String
    let outputDir: String
}

enum PromptOverrides {
    static func run(options: PromptOverridesOptions) throws {
        let pdfPath = Extract.expandingTilde(in: options.pdfPath)
        let outputDir = Extract.expandingTilde(in: options.outputDir)
        let outputURL = URL(fileURLWithPath: outputDir, isDirectory: true)

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw PromptOverridesError.outputPathNotDirectory(outputURL.path)
            }
        } else {
            try FileManager.default.createDirectory(
                at: outputURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        guard let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            throw PromptOverridesError.pdfLoadFailed(pdfPath)
        }

        let pageNumbers: [Int]
        do {
            pageNumbers = try PageRange.parse(options.pages)
        } catch let error as PageRangeError {
            throw PromptOverridesError.invalidPageRange(error.description)
        }

        for pageNumber in pageNumbers {
            let pageText = try extractPageText(document: document, pageNumber: pageNumber)
            let overrides = Extract.buildOverrides(from: pageText)
            let targetURL = pageNumbers.count > 1
                ? outputURL.appendingPathComponent("page-\(pageNumber)", isDirectory: true)
                : outputURL
            try writeOverrides(overrides, to: targetURL)
        }
    }

    private static func extractPageText(document: PDFDocument, pageNumber: Int) throws -> String {
        let pageCount = document.pageCount
        guard pageNumber >= 1 && pageNumber <= pageCount else {
            throw PromptOverridesError.pageOutOfRange(pageNumber, pageCount)
        }
        guard let page = document.page(at: pageNumber - 1) else {
            throw PromptOverridesError.pageOutOfRange(pageNumber, pageCount)
        }
        return page.string ?? ""
    }

    private static func writeOverrides(_ overrides: Extract.ExtractionOverrides, to directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try write(text: overrides.mixText ?? "", to: directory.appendingPathComponent("mix_text.txt"))
        try write(text: overrides.mixRowLines ?? "", to: directory.appendingPathComponent("mix_row_lines.txt"))
        try write(text: overrides.mixParsedHints ?? "", to: directory.appendingPathComponent("mix_parsed_hints.txt"))
        try write(text: overrides.extraChargesText ?? "", to: directory.appendingPathComponent("extra_charges_text.txt"))
    }

    private static func write(text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
