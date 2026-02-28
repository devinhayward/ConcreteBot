import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum FoundationalModelsError: Error, CustomStringConvertible {
    case frameworkUnavailable
    case osUnavailable
    case modelUnavailable(String)
    case contextWindowExceeded
    case generationFailed(String)
    case emptyResponse

    var description: String {
        switch self {
        case .frameworkUnavailable:
            return "FoundationModels framework is not available on this system."
        case .osUnavailable:
            return "FoundationModels requires macOS 26 or newer."
        case .modelUnavailable(let detail):
            return "System language model is unavailable: \(detail)"
        case .contextWindowExceeded:
            return "Model request exceeded context window size."
        case .generationFailed(let detail):
            return "Model generation failed: \(detail)"
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

    static func runTicket(prompt: String) throws -> Ticket {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try runTicketBlocking(prompt: prompt)
        } else {
            throw FoundationalModelsError.osUnavailable
        }
        #else
        throw FoundationalModelsError.frameworkUnavailable
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    @Generable
    struct GeneratedExtraCharge {
        var description: String?
        var qty: String?
    }

    @available(macOS 26.0, *)
    @Generable
    struct GeneratedMixRow {
        var qty: String?
        var customerDescription: String?
        var description: String?
        var code: String?
        var slump: String?

        func toMixRow() -> MixRow {
            MixRow(
                qty: qty,
                customerDescription: customerDescription,
                description: description,
                code: code,
                slump: slump
            )
        }
    }

    @available(macOS 26.0, *)
    @Generable
    struct GeneratedTicket {
        var ticketNumber: String?
        var deliveryDate: String?
        var deliveryTime: String?
        var deliveryAddress: String?
        var mixCustomer: GeneratedMixRow
        var mixAdditional1: GeneratedMixRow?
        var mixAdditional2: GeneratedMixRow?
        var extraCharges: [GeneratedExtraCharge]

        func toTicket() -> Ticket {
            Ticket(
                ticketNumber: ticketNumber,
                deliveryDate: deliveryDate,
                deliveryTime: deliveryTime,
                deliveryAddress: deliveryAddress,
                mixCustomer: mixCustomer.toMixRow(),
                mixAdditional1: mixAdditional1?.toMixRow(),
                mixAdditional2: mixAdditional2?.toMixRow(),
                extraCharges: extraCharges.map { charge in
                    ExtraCharge(description: charge.description, qty: charge.qty)
                }
            )
        }
    }

    @available(macOS 26.0, *)
    private static func runBlocking(prompt: String) throws -> String {
        let waiter = BlockingWaiter<String>()
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
    private static func runTicketBlocking(prompt: String) throws -> Ticket {
        let waiter = BlockingWaiter<Ticket>()
        Task { @Sendable in
            do {
                let ticket = try await runTicketAvailable(prompt: prompt)
                waiter.set(.success(ticket))
            } catch {
                waiter.set(.failure(error))
            }
        }
        return try waiter.wait()
    }

    @available(macOS 26.0, *)
    private static func availableModel() throws -> SystemLanguageModel {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model
        case .unavailable(let reason):
            throw FoundationalModelsError.modelUnavailable(describe(reason))
        }
    }

    @available(macOS 26.0, *)
    private static func runTicketAvailable(prompt: String) async throws -> Ticket {
        let model = try availableModel()
        let session = LanguageModelSession(model: model)
        let options = GenerationOptions(sampling: .greedy, temperature: 0.0)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedTicket.self,
                includeSchemaInPrompt: true,
                options: options
            )
            return response.content.toTicket()
        } catch let error as LanguageModelSession.GenerationError {
            throw mapGenerationError(error)
        }
    }

    @available(macOS 26.0, *)
    private static func runAvailable(prompt: String) async throws -> String {
        let model = try availableModel()

        let session = LanguageModelSession(model: model)
        let options = GenerationOptions(sampling: .greedy, temperature: 0.0)
        let response: LanguageModelSession.Response<String>
        do {
            response = try await session.respond(to: prompt, options: options)
        } catch let error as LanguageModelSession.GenerationError {
            throw mapGenerationError(error)
        }
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw FoundationalModelsError.emptyResponse
        }
        return text
    }

    @available(macOS 26.0, *)
    private static func mapGenerationError(_ error: LanguageModelSession.GenerationError) -> FoundationalModelsError {
        switch error {
        case .exceededContextWindowSize:
            return .contextWindowExceeded
        default:
            return .generationFailed(error.localizedDescription)
        }
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

final class BlockingWaiter<Value>: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func set(_ response: Result<Value, Error>) {
        lock.lock()
        result = response
        lock.unlock()
        semaphore.signal()
    }

    func wait() throws -> Value {
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        guard let result else {
            throw FoundationalModelsError.emptyResponse
        }
        return try result.get()
    }
}
