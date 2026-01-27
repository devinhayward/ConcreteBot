import Foundation
import PDFKit

enum DumpTextError: Error, CustomStringConvertible {
    case invalidPageRange(String)
    case pdfLoadFailed(String)
    case pageOutOfRange(Int, Int)
    case multiplePagesNeedDirectory(String)

    var description: String {
        switch self {
        case .invalidPageRange(let detail):
            return "Invalid page range: \(detail)"
        case .pdfLoadFailed(let path):
            return "Failed to load PDF: \(path)"
        case .pageOutOfRange(let page, let total):
            return "Page \(page) is out of range (1-\(total))."
        case .multiplePagesNeedDirectory(let path):
            return "Output path must be a directory when dumping multiple pages: \(path)"
        }
    }
}

struct DumpTextOptions {
    let pdfPath: String
    let pages: String
    let outputPath: String?
}

enum DumpText {
    static func run(options: DumpTextOptions) throws {
        let pdfPath = Extract.expandingTilde(in: options.pdfPath)
        guard let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
            throw DumpTextError.pdfLoadFailed(pdfPath)
        }

        let pageNumbers: [Int]
        do {
            pageNumbers = try PageRange.parse(options.pages)
        } catch let error as PageRangeError {
            throw DumpTextError.invalidPageRange(error.description)
        }

        let outputPath = options.outputPath.map { Extract.expandingTilde(in: $0) }
        let outputURL = outputPath.map { URL(fileURLWithPath: $0) }
        let outputIsDirectory = outputURL.map { url in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if exists {
                return isDirectory.boolValue
            }
            return url.path.hasSuffix("/")
        } ?? false

        if pageNumbers.count > 1, let outputURL, !outputIsDirectory {
            throw DumpTextError.multiplePagesNeedDirectory(outputURL.path)
        }

        for pageNumber in pageNumbers {
            let text = try extractPageText(document: document, pageNumber: pageNumber)
            if let outputURL {
                if outputIsDirectory {
                    let fileURL = outputURL.appendingPathComponent("page-\(pageNumber).txt")
                    try text.write(to: fileURL, atomically: true, encoding: .utf8)
                } else {
                    try text.write(to: outputURL, atomically: true, encoding: .utf8)
                }
            } else {
                if pageNumbers.count > 1 {
                    print("----- PAGE \(pageNumber) -----")
                }
                print(text)
            }
        }
    }

    private static func extractPageText(document: PDFDocument, pageNumber: Int) throws -> String {
        let pageCount = document.pageCount
        guard pageNumber >= 1 && pageNumber <= pageCount else {
            throw DumpTextError.pageOutOfRange(pageNumber, pageCount)
        }
        guard let page = document.page(at: pageNumber - 1) else {
            throw DumpTextError.pageOutOfRange(pageNumber, pageCount)
        }
        return page.string ?? ""
    }
}
