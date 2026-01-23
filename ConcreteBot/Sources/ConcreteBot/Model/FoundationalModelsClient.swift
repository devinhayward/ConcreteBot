import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum FoundationalModelsError: Error, CustomStringConvertible {
    case frameworkUnavailable
    case osUnavailable
    case modelUnavailable(String)
    case emptyResponse

    var description: String {
        switch self {
        case .frameworkUnavailable:
            return "FoundationModels framework is not available on this system."
        case .osUnavailable:
            return "FoundationModels requires macOS 26 or newer."
        case .modelUnavailable(let detail):
            return "System language model is unavailable: \(detail)"
        case .emptyResponse:
            return "Model response was empty."
        }
    }
}

enum FoundationalModelsClient {
    static func run(prompt: String) throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try runBlocking(prompt: prompt)
        } else {
            throw FoundationalModelsError.osUnavailable
        }
        #else
        throw FoundationalModelsError.frameworkUnavailable
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func runBlocking(prompt: String) throws -> String {
        let waiter = BlockingWaiter()
        Task { @Sendable in
            do {
                let response = try await runAvailable(prompt: prompt)
                waiter.set(.success(response))
            } catch {
                waiter.set(.failure(error))
            }
        }
        return try waiter.wait()
    }

    @available(macOS 26.0, *)
    private static func runAvailable(prompt: String) async throws -> String {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw FoundationalModelsError.modelUnavailable(describe(reason))
        }

        let session = LanguageModelSession(model: model)
        let options = GenerationOptions(sampling: .greedy, temperature: 0.0)
        let response = try await session.respond(to: prompt, options: options)
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw FoundationalModelsError.emptyResponse
        }
        return text
    }

    @available(macOS 26.0, *)
    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "device not eligible"
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence not enabled"
        case .modelNotReady:
            return "model not ready"
        @unknown default:
            return "unknown reason"
        }
    }
    #endif
}

final class BlockingWaiter: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<String, Error>?

    func set(_ response: Result<String, Error>) {
        lock.lock()
        result = response
        lock.unlock()
        semaphore.signal()
    }

    func wait() throws -> String {
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        guard let result else {
            throw FoundationalModelsError.emptyResponse
        }
        return try result.get()
    }
}
