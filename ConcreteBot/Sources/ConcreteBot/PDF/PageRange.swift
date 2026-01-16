import Foundation

enum PageRangeError: Error, CustomStringConvertible {
    case empty
    case invalidToken(String)
    case invalidRange(String)

    var description: String {
        switch self {
        case .empty:
            return "Page range is empty."
        case .invalidToken(let token):
            return "Invalid page token: \(token)"
        case .invalidRange(let token):
            return "Invalid page range: \(token)"
        }
    }
}

enum PageRange {
    static func parse(_ value: String) throws -> [Int] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PageRangeError.empty
        }

        var pages: [Int] = []
        let parts = trimmed.replacingOccurrences(of: " ", with: "").split(separator: ",")
        for part in parts {
            if part.contains("-") {
                let bounds = part.split(separator: "-", omittingEmptySubsequences: false)
                guard bounds.count == 2,
                      let start = Int(bounds[0]),
                      let end = Int(bounds[1]),
                      start > 0,
                      end > 0,
                      end >= start else {
                    throw PageRangeError.invalidRange(String(part))
                }
                pages.append(contentsOf: start...end)
            } else {
                guard let page = Int(part), page > 0 else {
                    throw PageRangeError.invalidToken(String(part))
                }
                pages.append(page)
            }
        }

        return pages
    }
}
