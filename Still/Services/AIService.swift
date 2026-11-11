import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Where the quiet AI is allowed to run. Chosen in You → Quiet AI.
enum AIMode: String, CaseIterable, Identifiable {
    /// Apple's on-device model when it's available, otherwise Cloudflare (only if allowed).
    case automatic
    /// Apple's on-device model only. Nothing leaves the iPhone.
    case onDevice
    /// The still. Cloudflare Worker only.
    case cloud
    /// No AI at all.
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .onDevice: return "On this iPhone"
        case .cloud: return "Cloudflare"
        case .off: return "Off"
        }
    }

    var detail: String {
        switch self {
        case .automatic: return "Uses this iPhone when it can, and Cloudflare only if you allow it."
        case .onDevice: return "Apple's built-in model. Nothing you write leaves this iPhone."
        case .cloud: return "A private still. server on Cloudflare. Text is sent, answered, and discarded."
        case .off: return "No notes and no personal openers."
        }
    }
}

enum AIEngine: Equatable {
    case onDevice, cloud

    var title: String { self == .onDevice ? "On this iPhone" : "Cloudflare" }
}

/// Whether one engine can run right now, and why not if it can't.
enum EngineStatus: Equatable {
    case ready
    case needsConsent
    case unavailable(String)

    var isReady: Bool { self == .ready }

    var label: String {
        switch self {
        case .ready: return "Available"
        case .needsConsent: return "Needs your OK"
        case .unavailable(let why): return why
        }
    }
}

enum AIError: Error {
    case noEngine
    case emptyReply
    case badResponse(Int)
}

/// The two jobs the AI does. Prompts live here for the on-device model and are
/// mirrored on the server, which only accepts these two tasks.
enum AITask {
    case reflection([String])
    case openers([String])

    var path: String {
        switch self {
        case .reflection: return "reflect"
        case .openers: return "openers"
        }
    }

    var texts: [String] {
        switch self {
        case .reflection(let t), .openers(let t): return t
        }
    }

    var instructions: String {
        switch self {
        case .reflection:
            return """
            You are the quiet companion inside still., a private journal. The person just wrote \
            one or more entries. Reply with two or three short, warm sentences in plain words. \
            Listen and acknowledge how they feel; don't fix, advise, or lecture unless they ask. \
            Only refer to things they actually wrote. Never invent details or change their meaning. \
            No greetings, no sign-off, no emoji, no lists. If they mention wanting to harm themselves, \
            gently say they deserve support right now and that in the US they can call or text 988.
            """
        case .openers:
            return """
            You write gentle journaling prompts for still., a private journal. Based on the person's \
            recent writing, write four different open questions that might help them start writing \
            today. Each is under twelve words, kind, and specific to themes they've mentioned, without \
            quoting them or naming private details. Output only the four questions, one per line, \
            with no numbers or quotes.
            """
        }
    }

    func prompt(limit: Int) -> String {
        let label = { (i: Int) -> String in
            switch self {
            case .reflection: return "Entry \(i + 1)"
            case .openers: return "Recent writing \(i + 1)"
            }
        }
        return AIService.trim(texts, total: limit).enumerated()
            .map { "\(label($0.offset)):\n\($0.element)" }
            .joined(separator: "\n\n")
    }

    var maxTokens: Int {
        switch self {
        case .reflection: return 180
        case .openers: return 120
        }
    }
}

/// Picks an engine from the user's mode and what this iPhone supports, then runs the task.
enum AIService {
    static let modeKey = "ai.mode"
    static let consentKey = "ai.cloudConsent"

    static var mode: AIMode {
        AIMode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .automatic
    }

    /// Off by default. Nothing goes to Cloudflare until the user turns this on.
    static var cloudConsent: Bool {
        UserDefaults.standard.bool(forKey: consentKey)
    }

    static var onDeviceStatus: EngineStatus { AppleModel.status }

    static var cloudStatus: EngineStatus {
        guard CloudModel.endpoint != nil else { return .unavailable("Not set up") }
        return cloudConsent ? .ready : .needsConsent
    }

    /// The engine that will actually run, or nil when AI is off or nothing is available.
    static var activeEngine: AIEngine? {
        switch mode {
        case .off: return nil
        case .onDevice: return onDeviceStatus.isReady ? .onDevice : nil
        case .cloud: return cloudStatus.isReady ? .cloud : nil
        case .automatic:
            if onDeviceStatus.isReady { return .onDevice }
            if cloudStatus.isReady { return .cloud }
            return nil
        }
    }

    static var isActive: Bool { activeEngine != nil }

    static func run(_ task: AITask) async throws -> String {
        guard let engine = activeEngine else { throw AIError.noEngine }
        do {
            return try await run(task, on: engine)
        } catch {
            // In Automatic, the on-device model can decline heavy topics or run out of
            // room; fall back to Cloudflare only when the user has allowed it.
            if mode == .automatic, engine == .onDevice, cloudStatus.isReady {
                return try await run(task, on: .cloud)
            }
            throw error
        }
    }

    private static func run(_ task: AITask, on engine: AIEngine) async throws -> String {
        let raw: String
        switch engine {
        case .onDevice: raw = try await AppleModel.respond(task)
        case .cloud: raw = try await CloudModel.respond(task)
        }
        let reply = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { throw AIError.emptyReply }
        return reply
    }

    /// Keeps the newest text and caps the total so prompts fit small context windows.
    static func trim(_ texts: [String], total: Int, each: Int = 1500) -> [String] {
        var budget = total
        var kept: [String] = []
        for text in texts.reversed() {
            guard budget > 200 else { break }
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            let piece = String(clean.prefix(min(each, budget)))
            kept.append(piece)
            budget -= piece.count
        }
        return kept.reversed()
    }

    /// Turns a model's reply into clean one-line questions.
    static func parseOpeners(_ reply: String) -> [String] {
        reply.split(whereSeparator: \.isNewline)
            .map { line -> String in
                var s = line.trimmingCharacters(in: .whitespaces)
                while let f = s.first, "-•*0123456789.)\"“”' ".contains(f) { s.removeFirst() }
                while let l = s.last, "\"“”' ".contains(l) { s.removeLast() }
                return s
            }
            .filter { $0.count >= 8 && $0.count <= 90 && $0.hasSuffix("?") }
            .prefix(4)
            .map { $0 }
    }
}

// MARK: - Apple on-device model

enum AppleModel {
    static var status: EngineStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .ready
            case .unavailable(.deviceNotEligible):
                return .unavailable("Not supported")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Off in Settings")
            case .unavailable(.modelNotReady):
                return .unavailable("Downloading…")
            case .unavailable:
                return .unavailable("Unavailable")
            }
        }
        return .unavailable("Needs iOS 26")
        #else
        return .unavailable("Needs iOS 26")
        #endif
    }

    static func respond(_ task: AITask) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: task.instructions)
            let options = GenerationOptions(temperature: 0.7, maximumResponseTokens: task.maxTokens)
            // ~4K token window shared by prompt and reply, so keep the input small.
            let response = try await session.respond(to: task.prompt(limit: 5000), options: options)
            return response.content
        }
        #endif
        throw AIError.noEngine
    }
}

// MARK: - Cloudflare Worker

enum CloudModel {
    /// Set with the STILL_AI_ENDPOINT build setting (see worker/README.md).
    static var endpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "StillAIEndpoint") as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("https://") else { return nil }
        return URL(string: trimmed)
    }

    /// No cache, no cookies, nothing written to disk.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    private struct Body: Encodable { let texts: [String] }
    private struct Reply: Decodable { let text: String }

    static func respond(_ task: AITask) async throws -> String {
        guard let base = endpoint else { throw AIError.noEngine }
        var request = URLRequest(url: base.appendingPathComponent("v1").appendingPathComponent(task.path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(texts: AIService.trim(task.texts, total: 8000)))
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw AIError.badResponse(code) }
        return try JSONDecoder().decode(Reply.self, from: data).text
    }
}
