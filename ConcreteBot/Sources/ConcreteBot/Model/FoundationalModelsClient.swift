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
    struct RuntimeInfo: Codable {
        let hostOSVersion: String
        let frameworkAvailable: Bool
        let operatingSystemSupported: Bool
        let modelVersionLine: String?
        let availability: String?
        let contextWindowTokens: Int?
    }

    struct ToolRunMetadata: Codable {
        let toolCallCount: Int
        let toolNames: [String]
        let toolOutputCount: Int
    }

    struct TicketRunResult {
        let ticket: Ticket
        let toolMetadata: ToolRunMetadata?
    }

    struct TextRunResult {
        let text: String
        let toolMetadata: ToolRunMetadata?
    }

    static func run(prompt: String) throws -> String {
        let result = try runDetailed(prompt: prompt)
        return result.text
    }

    static func runDetailed(prompt: String) throws -> TextRunResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try runBlocking(prompt: prompt, tools: [])
        } else {
            throw FoundationalModelsError.osUnavailable
        }
        #else
        throw FoundationalModelsError.frameworkUnavailable
        #endif
    }

    static func runTicket(prompt: String) throws -> Ticket {
        let result = try runTicketDetailed(prompt: prompt)
        return result.ticket
    }

    static func runTicketDetailed(prompt: String) throws -> TicketRunResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try runTicketBlocking(prompt: prompt, tools: [])
        } else {
            throw FoundationalModelsError.osUnavailable
        }
        #else
        throw FoundationalModelsError.frameworkUnavailable
        #endif
    }

    static func promptTokenCount(prompt: String) -> Int? {
        #if canImport(FoundationModels)
        if #available(macOS 26.4, *) {
            let waiter = BlockingWaiter<Int?>()
            Task { @Sendable in
                let model = SystemLanguageModel.default
                switch model.availability {
                case .available:
                    do {
                        let count = try await model.tokenCount(for: prompt)
                        waiter.set(.success(count))
                    } catch {
                        waiter.set(.success(nil))
                    }
                case .unavailable:
                    waiter.set(.success(nil))
                }
            }
            return try? waiter.wait()
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    static func runDetailed(prompt: String, tools: [any Tool]) throws -> TextRunResult {
        try runBlocking(prompt: prompt, tools: tools)
    }

    @available(macOS 26.0, *)
    static func runTicketDetailed(prompt: String, tools: [any Tool]) throws -> TicketRunResult {
        try runTicketBlocking(prompt: prompt, tools: tools)
    }
    #endif

    static func runtimeInfo() -> RuntimeInfo {
        let hostOSVersion = ProcessInfo.processInfo.operatingSystemVersionString

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            let contextWindowTokens: Int?
            if #available(macOS 26.4, *) {
                contextWindowTokens = model.contextSize
            } else {
                contextWindowTokens = nil
            }

            return RuntimeInfo(
                hostOSVersion: hostOSVersion,
                frameworkAvailable: true,
                operatingSystemSupported: true,
                modelVersionLine: currentModelVersionLine(),
                availability: describe(model.availability),
                contextWindowTokens: contextWindowTokens
            )
        }

        return RuntimeInfo(
            hostOSVersion: hostOSVersion,
            frameworkAvailable: true,
            operatingSystemSupported: false,
            modelVersionLine: nil,
            availability: "unsupported OS",
            contextWindowTokens: nil
        )
        #else
        return RuntimeInfo(
            hostOSVersion: hostOSVersion,
            frameworkAvailable: false,
            operatingSystemSupported: false,
            modelVersionLine: nil,
            availability: "framework unavailable",
            contextWindowTokens: nil
        )
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    @Generable
    struct GeneratedExtraCharge {
        // Keep property names concise to reduce schema token cost.
        var desc: String?
        var qty: String?
    }

    @available(macOS 26.0, *)
    @Generable
    struct GeneratedMixRow {
        var qty: String?
        var custDesc: String?
        var desc: String?
        var code: String?
        var slump: String?

        func toMixRow() -> MixRow {
            MixRow(
                qty: qty,
                customerDescription: custDesc,
                description: desc,
                code: code,
                slump: slump
            )
        }
    }

    @available(macOS 26.0, *)
    @Generable
    struct GeneratedTicket {
        var ticketNo: String?
        var date: String?
        var time: String?
        var address: String?
        var customer: GeneratedMixRow
        var additional1: GeneratedMixRow?
        var additional2: GeneratedMixRow?
        var charges: [GeneratedExtraCharge]

        func toTicket() -> Ticket {
            Ticket(
                ticketNumber: ticketNo,
                deliveryDate: date,
                deliveryTime: time,
                deliveryAddress: address,
                mixCustomer: customer.toMixRow(),
                mixAdditional1: additional1?.toMixRow(),
                mixAdditional2: additional2?.toMixRow(),
                extraCharges: charges.map { charge in
                    ExtraCharge(description: charge.desc, qty: charge.qty)
                }
            )
        }
    }

    @available(macOS 26.0, *)
    private static func runBlocking(prompt: String, tools: [any Tool]) throws -> TextRunResult {
        let waiter = BlockingWaiter<TextRunResult>()
        Task { @Sendable in
            do {
                let response = try await runAvailable(prompt: prompt, tools: tools)
                waiter.set(.success(response))
            } catch {
                waiter.set(.failure(error))
            }
        }
        return try waiter.wait()
    }

    @available(macOS 26.0, *)
    private static func runTicketBlocking(prompt: String, tools: [any Tool]) throws -> TicketRunResult {
        let waiter = BlockingWaiter<TicketRunResult>()
        Task { @Sendable in
            do {
                let ticket = try await runTicketAvailable(prompt: prompt, tools: tools)
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
    private static func runTicketAvailable(
        prompt: String,
        tools: [any Tool]
    ) async throws -> TicketRunResult {
        let model = try availableModel()
        let session = LanguageModelSession(model: model, tools: tools)
        let options = GenerationOptions(sampling: .greedy, temperature: 0.0)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedTicket.self,
                includeSchemaInPrompt: true,
                options: options
            )
            return TicketRunResult(
                ticket: response.content.toTicket(),
                toolMetadata: extractToolRunMetadata(from: response.transcriptEntries)
            )
        } catch let error as LanguageModelSession.ToolCallError {
            throw FoundationalModelsError.generationFailed(
                "Tool \(error.tool.name) failed: \(error.underlyingError.localizedDescription)"
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw mapGenerationError(error)
        }
    }

    @available(macOS 26.0, *)
    private static func runAvailable(
        prompt: String,
        tools: [any Tool]
    ) async throws -> TextRunResult {
        let model = try availableModel()

        let session = LanguageModelSession(model: model, tools: tools)
        let options = GenerationOptions(sampling: .greedy, temperature: 0.0)
        let response: LanguageModelSession.Response<String>
        do {
            response = try await session.respond(to: prompt, options: options)
        } catch let error as LanguageModelSession.ToolCallError {
            throw FoundationalModelsError.generationFailed(
                "Tool \(error.tool.name) failed: \(error.underlyingError.localizedDescription)"
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw mapGenerationError(error)
        }
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw FoundationalModelsError.emptyResponse
        }
        return TextRunResult(
            text: text,
            toolMetadata: extractToolRunMetadata(from: response.transcriptEntries)
        )
    }

    @available(macOS 26.0, *)
    private static func extractToolRunMetadata(
        from entries: ArraySlice<Transcript.Entry>
    ) -> ToolRunMetadata? {
        var toolNames: [String] = []
        var seenNames = Set<String>()
        var toolCallCount = 0
        var toolOutputCount = 0

        for entry in entries {
            switch entry {
            case .toolCalls(let calls):
                for call in calls {
                    toolCallCount += 1
                    if seenNames.insert(call.toolName).inserted {
                        toolNames.append(call.toolName)
                    }
                }
            case .toolOutput:
                toolOutputCount += 1
            default:
                break
            }
        }

        guard toolCallCount > 0 || toolOutputCount > 0 else {
            return nil
        }

        return ToolRunMetadata(
            toolCallCount: toolCallCount,
            toolNames: toolNames,
            toolOutputCount: toolOutputCount
        )
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

    @available(macOS 26.0, *)
    private static func describe(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "available"
        case .unavailable(let reason):
            return "unavailable: \(describe(reason))"
        }
    }

    @available(macOS 26.0, *)
    private static func currentModelVersionLine() -> String {
        if #available(macOS 26.4, *) {
            return "26.4+"
        }
        return "26.0-26.3"
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
