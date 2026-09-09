import XCTest
@testable import Strand

@MainActor
final class AIStreamingThreadTests: XCTestCase {
    func testCustomStreamDeliversOrderedDeltasOnMainThread() async throws {
        try await checkStream(provider: .custom)
    }

    func testOpenAIStreamDeliversOnMainThread() async throws {
        try await checkStream(provider: .openAI)
    }

    func testAnthropicStreamDeliversOnMainThread() async throws {
        try await checkStream(provider: .anthropic)
    }

    func testGeminiStreamDeliversOnMainThread() async throws {
        try await checkStream(provider: .gemini)
    }

    func testGeminiImageStreamDeliversOnMainThread() async throws {
        try await checkStream(provider: .gemini, image: "dGVzdA==")
    }

    func testNonStreamingFallbackDeliversOnMainThread() async throws {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        var received = ""
        try await NonStreamingClient().stream(key: "", model: "test", systemPrompt: "test",
                                             messages: [], session: session) { delta in
            XCTAssertTrue(Thread.isMainThread, "The Coach callback updates UI state")
            received += delta
        }
        XCTAssertEqual(received, "Hello world")
    }

    private func checkStream(provider: AIProvider, image: String? = nil) async throws {
        let defaults = UserDefaults.standard
        let oldURL = defaults.object(forKey: AIProvider.customBaseURLKey)
        defaults.set("http://coach-stream.test/v1", forKey: AIProvider.customBaseURLKey)
        defer {
            if let oldURL { defaults.set(oldURL, forKey: AIProvider.customBaseURLKey) }
            else { defaults.removeObject(forKey: AIProvider.customBaseURLKey) }
        }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        var deltas: [String] = []
        // The same protocol dispatch used by AICoachEngine.send and its morning brief.
        try await provider.client.streamWithImage(key: "test-key", model: "test-model",
                                                 systemPrompt: "test", messages: [], inlineImage: image,
                                                 session: session) { delta in
            XCTAssertTrue(Thread.isMainThread, "Streaming must not publish UI changes from the network executor")
            deltas.append(delta)
        }
        XCTAssertEqual(deltas, ["Hello", " world"], "Delivery must finish in order before the stream returns")
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CoachStreamURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class CoachStreamURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let chunks = ["Hello", " world"].map { text -> String in
            let payload: [String: Any]
            switch request.url?.host {
            case "api.anthropic.com":
                payload = ["type": "content_block_delta", "delta": ["type": "text_delta", "text": text]]
            case "generativelanguage.googleapis.com":
                payload = ["candidates": [["content": ["parts": [["text": text]]]]]]
            default:
                payload = ["choices": [["delta": ["content": text]]]]
            }
            let data = try! JSONSerialization.data(withJSONObject: payload)
            return "data: \(String(decoding: data, as: UTF8.self))\n\n"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in chunks { client?.urlProtocol(self, didLoad: Data(chunk.utf8)) }
        client?.urlProtocol(self, didLoad: Data("data: [DONE]\n\n".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct NonStreamingClient: AIProviderClient {
    func send(key: String, model: String, systemPrompt: String,
              messages: [(role: ChatMessage.Role, content: String)], session: URLSession) async throws -> String {
        "Hello world"
    }
    func fetchModels(key: String, session: URLSession) async throws -> [String] { [] }
}
