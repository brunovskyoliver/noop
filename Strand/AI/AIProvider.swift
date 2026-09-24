import Foundation
import StrandAnalytics

// MARK: - Provider enum

enum AIProvider: String, CaseIterable, Identifiable {
    case openAI
    case anthropic
    case gemini
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:    return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini:    return "Google Gemini"
        case .custom:    return "Custom (OpenAI-compatible)"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI:    return "gpt-5-mini"
        case .anthropic: return "claude-sonnet-4-6"
        case .gemini:    return "gemini-flash-latest"   // stable alias → current Flash, no version churn (#400)
        case .custom:    return ""   // the user picks the model their server serves
        }
    }

    /// Models offered in the picker. A "Custom…" path in the UI lets the user pick any id beyond
    /// these, and `refreshModels()` can merge the provider's live list.
    var modelOptions: [String] {
        switch self {
        case .openAI:
            // Pinned ids, not aliases: OpenAI has no stable per-tier "-latest" alias the way Gemini
            // does (#400), so this list is bumped by hand. `refreshModels()` merges the live /models
            // catalogue, which stays the authority for anything released after this.
            //
            // The reasoning tiers (o3, o4-mini) and the GPT-5 family reject `temperature` and
            // `max_tokens`. Nothing special is needed for them here: the request path sends the
            // classic parameters, and on a 400 naming one of them retries with
            // `max_completion_tokens` and no temperature (see AiCoach's modernParams leg). The cost
            // is one extra round trip on the first message, not a per-model table to maintain.
            return [
                "gpt-5",
                "gpt-5-mini",
                "gpt-5-nano",
                "gpt-4.1",
                "gpt-4.1-mini",
                "gpt-4.1-nano",
                "gpt-4o",
                "gpt-4o-mini",
                "o3",
                "o4-mini"
            ]
        case .anthropic:
            return [
                "claude-opus-4-8",
                "claude-sonnet-4-6",
                "claude-haiku-4-5-20251001",
                "claude-3-7-sonnet-latest",
                "claude-3-5-sonnet-latest",
                "claude-3-5-haiku-latest",
                "claude-3-opus-latest"
            ]
        case .gemini:
            // Stable `-latest` ALIASES, not pinned versions (#400): they always resolve to the current
            // stable model in each tier, so Gemini's rapid releases never need a code bump. `refreshModels()`
            // still merges the live `/models` catalogue, so a user with a key can pin a concrete version.
            return [
                "gemini-pro-latest",
                "gemini-flash-latest",
                "gemini-flash-lite-latest"
            ]
        case .custom:
            return []   // populated from the server's /models (refreshModels) or typed in
        }
    }

    var endpoint: URL {
        switch self {
        case .openAI:    return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")!
        case .gemini:    return URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        case .custom:    return AIProvider.customURL(path: "/chat/completions")
        }
    }

    var modelsEndpoint: URL {
        switch self {
        case .openAI:    return URL(string: "https://api.openai.com/v1/models")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/models")!
        case .gemini:    return URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        case .custom:    return AIProvider.customURL(path: "/models")
        }
    }

    var client: any AIProviderClient {
        switch self {
        case .openAI:    return OpenAIClient()
        case .anthropic: return AnthropicClient()
        case .gemini:    return GeminiClient()
        case .custom:    return CustomClient()
        }
    }

    // MARK: - Custom (OpenAI-compatible) base URL

    /// UserDefaults key for the Custom provider's base URL (e.g. a local LLM server such as Ollama /
    /// LM Studio / llama.cpp: `http://localhost:11434/v1`). `AICoachEngine` exposes it for editing.
    static let customBaseURLKey = "ai.customBaseURL"
    static let customAuthHeaderKey = "ai.customAuthHeader"

    /// The user-set Custom base URL, normalised. Byte-parity with Android `AiCoach.normalizeCustomBaseUrl`.
    static var customBaseURL: String {
        normalizeCustomBaseURL(UserDefaults.standard.string(forKey: customBaseURLKey) ?? "")
    }

    /// #1074: normalise the Custom base URL so the derived `/chat/completions` and `/models` endpoints
    /// are always well-formed. The user may paste the base (`http://…:11434/v1`) OR the whole chat URL
    /// (`…/v1/chat/completions`) — the latter otherwise made the model scan hit `…/chat/completions/models`
    /// and silently return nothing. Trim, drop trailing slashes, strip one trailing OpenAI-style chat
    /// path, drop trailing slashes again. Pure — unit-tested. Byte-identical to Android normalizeCustomBaseUrl.
    static func normalizeCustomBaseURL(_ url: String) -> String {
        var base = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        for suffix in ["/chat/completions", "/completions"] {
            if base.lowercased().hasSuffix(suffix) {
                base.removeLast(suffix.count)
                while base.hasSuffix("/") { base.removeLast() }
                break
            }
        }
        return base
    }

    static var customAuthHeader: CustomAIAuthHeader {
        let raw = UserDefaults.standard.string(forKey: customAuthHeaderKey)
        return CustomAIAuthHeader(rawValue: raw ?? "") ?? .bearer
    }

    static func applyCustomAuthHeader(_ key: String, to request: inout URLRequest) {
        guard !key.isEmpty else { return }
        switch customAuthHeader {
        case .bearer:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .xAPIKey:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
    }

    /// Build a Custom endpoint by appending `path` to the user's base URL (trailing slashes tolerated).
    /// Falls back to a loopback placeholder when unset — the request then fails with a clear network
    /// error until the user sets a URL.
    static func customURL(path: String) -> URL {
        var base = customBaseURL
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + path) ?? URL(string: "http://localhost" + path)!
    }

    /// Validate the configured endpoint before model discovery, chat, or streaming.
    /// Custom providers may use HTTP or HTTPS, including public hosts and VPN addresses.
    static func guardCustomBaseURL(_ rawURL: String? = nil) throws {
        let base = rawURL.map(normalizeCustomBaseURL) ?? customBaseURL
        guard let components = URLComponents(string: base),
              components.url != nil,
              let host = components.host, !host.isEmpty,
              let scheme = components.scheme?.lowercased(), !scheme.isEmpty else {
            throw AICoachError.badCustomURL("Enter a valid server URL beginning with http:// or https://.")
        }
        guard scheme == "http" || scheme == "https" else {
            throw AICoachError.badCustomURL("Unsupported URL scheme \"\(scheme)\". Use http:// or https://.")
        }
    }

}

enum CustomAIAuthHeader: String, CaseIterable, Identifiable {
    case bearer
    case xAPIKey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bearer: return "Bearer"
        case .xAPIKey: return "x-api-key"
        }
    }
}

// MARK: - Provider protocol

protocol AIProviderClient {
    /// Send a chat turn and return the assistant reply text.
    func send(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession
    ) async throws -> String

    /// Fetch the provider's live model list and return plain model ids.
    func fetchModels(key: String, session: URLSession) async throws -> [String]

    /// Stream a chat turn, delivering each text chunk to `onDelta` on the main actor in order.
    /// All callbacks finish before the stream returns. The concatenated
    /// deltas must equal the text that `send` would return for the same inputs (byte-parity with
    /// the non-streamed path). The default implementation falls back to `send` + a single delta,
    /// so providers without streaming still work. K1.
    func stream(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession,
        onDelta: @MainActor (String) -> Void
    ) async throws

    /// K11: Stream a chat turn with an optional inline image (base64 PNG). Only Gemini implements
    /// this; the default implementation ignores the image and calls `stream`. This keeps the
    /// multimodal path opt-in without changing every provider's `stream` signature.
    func streamWithImage(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        inlineImage: String?,
        session: URLSession,
        onDelta: @MainActor (String) -> Void
    ) async throws
}

extension AIProviderClient {
    /// K11: Default — ignore the image, delegate to `stream`. Providers without multimodal support
    /// (OpenAI, Anthropic, Custom) use this; only Gemini overrides it.
    func streamWithImage(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        inlineImage: String?,
        session: URLSession,
        onDelta: @MainActor (String) -> Void
    ) async throws {
        try await stream(key: key, model: model, systemPrompt: systemPrompt,
                         messages: messages, session: session, onDelta: onDelta)
    }
}

extension AIProviderClient {
    /// Default: fall back to the non-streaming `send` and emit the full reply as one delta.
    func stream(
        key: String,
        model: String,
        systemPrompt: String,
        messages: [(role: ChatMessage.Role, content: String)],
        session: URLSession,
        onDelta: @MainActor (String) -> Void
    ) async throws {
        let reply = try await send(key: key, model: model, systemPrompt: systemPrompt,
                                    messages: messages, session: session)
        await onDelta(reply)
    }
}

// MARK: - Shared HTTP helpers

/// Execute a request, map HTTP status codes to `AICoachError`, return the decoded JSON object.
func performRequest(_ req: URLRequest, session: URLSession) async throws -> [String: Any] {
    let data: Data
    let response: URLResponse

    do {
        (data, response) = try await session.data(for: req)
    } catch {
        throw AICoachError.network(error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
        throw AICoachError.network("no HTTP response")
    }

    switch http.statusCode {
    case 200...299:
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AICoachError.decode
        }

        return obj
    case let status where AICoachError.isKeyRejection(status):
        throw AICoachError.badKey
    case 429:
        throw AICoachError.rateLimited(providerErrorMessage(from: data))
    default:
        throw AICoachError.server(http.statusCode, providerErrorMessage(from: data))
    }
}

/// Best-effort extraction of a human-readable message from a provider error body.
func providerErrorMessage(from data: Data) -> String {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }

    if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
    if let msg = obj["message"] as? String { return msg }

    return ""
}

/// #1074: the error to throw when a 200 response has no assistant content. Some OpenAI-compatible
/// servers (e.g. a hand-set model they don't offer) return the real error INSIDE the 200 body rather
/// than a 4xx; surface it instead of a blank decode error, so the cause is visible. Byte-parity with
/// Android `AiCoach.emptyReplyMessage`.
func emptyReplyError(_ json: [String: Any]) -> AICoachError {
    if let err = json["error"] as? [String: Any], let msg = err["message"] as? String, !msg.isEmpty {
        return .emptyReply("The provider returned an error: \(msg)")
    }
    return .emptyReply("The provider returned an empty reply. If you set a custom model by hand, check "
        + "that the model name is one the provider actually offers.")
}

// MARK: - SSE streaming helper (K1)

/// Execute a streaming SSE request, map HTTP status codes to `AICoachError`, and call `onLine`
/// for each `data:` payload line (prefix stripped, blank/comment/non-data lines filtered). The
/// caller's `onLine` closure uses the pure `SseDeltas` functions to extract the per-provider text
/// delta. Throws on HTTP errors (same mapping as `performRequest`). K1.
func performStreamingRequest(
    _ req: URLRequest,
    session: URLSession,
    onLine: (String) async -> Void
) async throws {
    let bytes: (URLSession.AsyncBytes, URLResponse)
    do {
        bytes = try await session.bytes(for: req)
    } catch {
        throw AICoachError.network(error.localizedDescription)
    }

    guard let http = bytes.1 as? HTTPURLResponse else {
        throw AICoachError.network("no HTTP response")
    }

    switch http.statusCode {
    case 200...299:
        // Read line-by-line from the SSE byte stream. `URLSession.AsyncBytes` splits on \n.
        for try await line in bytes.0.lines {
            if let payload = SseDeltas.dataPayload(fromLine: line) {
                await onLine(payload)
            }
        }
    case let status where AICoachError.isKeyRejection(status):
        throw AICoachError.badKey
    case 429:
        var body = ""
        for try await line in bytes.0.lines { body += line }
        throw AICoachError.rateLimited(providerErrorMessage(from: Data(body.utf8)))
    default:
        // For non-200, the body is a (non-streaming) error JSON — collect it and surface the message.
        var body = ""
        for try await line in bytes.0.lines { body += line }
        throw AICoachError.server(http.statusCode, providerErrorMessage(from: Data(body.utf8)))
    }
}
