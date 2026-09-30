import XCTest

@testable import Omi_Computer

private final class ChatWebSearchURLCapture: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  private nonisolated(unsafe) static var requestCount = 0
  private nonisolated(unsafe) static var lastQuery: String?

  static func reset() {
    lock.lock()
    requestCount = 0
    lastQuery = nil
    lock.unlock()
  }

  static func snapshot() -> (Int, String?) {
    lock.lock()
    defer { lock.unlock() }
    return (requestCount, lastQuery)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    if let body = Self.bodyData(from: request),
      let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
      let messages = json["messages"] as? [[String: Any]],
      let content = messages.first?["content"] as? String
    {
      Self.lock.lock()
      Self.requestCount += 1
      Self.lastQuery = content
      Self.lock.unlock()
    } else {
      Self.lock.lock()
      Self.requestCount += 1
      Self.lock.unlock()
    }

    guard
      let url = request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: 200, httpVersion: nil,
        headerFields: ["Content-Type": "application/json"])
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    let body =
      #"{"choices":[{"message":{"content":"Paris is the capital of France."}}],"search_results":[]}"#
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func bodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let count = stream.read(buffer, maxLength: 4_096)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }
}

@MainActor
final class ChatToolExecutorWebSearchTests: XCTestCase {
  private let paywallKey = "desktop_isPaywalled"
  private var ownerFixture: RuntimeOwnerAuthorityTestFixture?

  override func setUp() async throws {
    ChatWebSearchURLCapture.reset()
    ownerFixture = RuntimeOwnerAuthorityTestFixture()
    await ownerFixture?.establish(authOwnerID: "chat-web-search-owner")
    UserDefaults.standard.set(false, forKey: paywallKey)
    for provider in BYOKProvider.allCases {
      UserDefaults.standard.removeObject(forKey: provider.storageKey)
    }
    APIKeyService.persistEnrolledFingerprints([:])
  }

  override func tearDown() async throws {
    ChatWebSearchURLCapture.reset()
    UserDefaults.standard.removeObject(forKey: paywallKey)
    for provider in BYOKProvider.allCases {
      UserDefaults.standard.removeObject(forKey: provider.storageKey)
    }
    APIKeyService.persistEnrolledFingerprints([:])
    await ownerFixture?.restore()
    ownerFixture = nil
  }

  func testPaywalledChatWebSearchReturnsPaidOnlyMessageWithoutNetwork() async {
    UserDefaults.standard.set(true, forKey: paywallKey)
    XCTAssertTrue(AppState.isPaywalledEffective)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ChatWebSearchURLCapture.self]
    let client = APIClient(session: URLSession(configuration: configuration))

    let result = await ChatToolExecutor.executeWebSearch(
      [
        "query": "What is the capital of France?",
        "scope": "narrow_current",
      ],
      expectedOwnerID: "chat-web-search-owner",
      api: client,
      customBaseURL: "https://desktop.example.test")

    XCTAssertEqual(result, "Web search is only available on paid Omi plans.")
    XCTAssertEqual(ChatWebSearchURLCapture.snapshot().0, 0)
  }

  func testPaidChatWebSearchReturnsPublicWebAnswer() async {
    UserDefaults.standard.set(false, forKey: paywallKey)
    XCTAssertFalse(AppState.isPaywalledEffective)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ChatWebSearchURLCapture.self]
    let client = APIClient(session: URLSession(configuration: configuration))
    await client.setTestAuthHeader("Bearer chat-web-search-token")

    let result = await ChatToolExecutor.executeWebSearch(
      [
        "query": "What is the capital of France?",
        "scope": "narrow_current",
      ],
      expectedOwnerID: "chat-web-search-owner",
      api: client,
      customBaseURL: "https://desktop.example.test")

    XCTAssertEqual(result, "Paris is the capital of France.")
    XCTAssertEqual(ChatWebSearchURLCapture.snapshot().0, 1)
    XCTAssertFalse(result.contains("unknown_realtime_invocation"))
  }

  func testExecutorDispatchHandlesWebSearchWithoutUnknownTool() async {
    UserDefaults.standard.set(true, forKey: paywallKey)

    let result = await ChatToolExecutor.execute(
      ToolCall(
        name: "web_search",
        arguments: [
          "query": "current weather in NYC",
          "scope": "narrow_current",
        ],
        thoughtSignature: nil),
      originatingSurfaceRef: .mainChat(chatId: "test"),
      expectedOwnerID: "chat-web-search-owner")

    XCTAssertEqual(result, "Web search is only available on paid Omi plans.")
    XCTAssertFalse(result.hasPrefix("Unknown tool"))
    XCTAssertFalse(result.contains("unknown_realtime_invocation"))
  }
}
