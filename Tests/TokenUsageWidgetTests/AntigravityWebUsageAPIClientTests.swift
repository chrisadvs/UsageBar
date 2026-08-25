import XCTest
@testable import TokenUsageWidget

final class AntigravityWebUsageAPIClientTests: XCTestCase {
    func testUnauthorizedResponseForcesApiKeyRefresh() async {
        let credentialProvider = StubCredentialProvider()

        // A single stub session shared by both the API key provider and the usage client —
        // URLProtocol registration is process-wide per class, so two independently-configured
        // sessions using the same protocol class would silently clobber each other's routing.
        // Routing by host/path here keeps the two concerns (key-fetch traffic vs. RPC traffic)
        // correctly separated within one handler.
        var indexFetchCount = 0
        let session = AntigravityStubURLProtocol.makeSession { url in
            if url.host == "antigravity.google.com", url.path.contains("/$rpc/") {
                return (401, "unauthorized")
            } else if url.host == "antigravity.google.com" {
                indexFetchCount += 1
                return (200, "<script src=\"https://www.gstatic.com/_/mss/boq-jetski/_/js/k=fake\"></script>")
            } else {
                return (200, "this.apiKey=\"AIzaSyFAKEFAKEFAKEFAKEFAKEFAKEFAKE\";")
            }
        }

        let apiKeyProvider = AntigravityApiKeyProvider(session: session)
        let client = AntigravityWebUsageAPIClient(
            credentialProvider: credentialProvider,
            apiKeyProvider: apiKeyProvider,
            session: session
        )

        do {
            _ = try await client.fetchUsage()
            XCTFail("Expected fetchUsage to throw on a 401 response")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Expected APIError.unauthorized, got \(error)")
        }

        // One fetch to seed the initial cached key, one more triggered by the
        // 401 handler forcing a refresh — proves the key cache actually gets
        // invalidated on auth failure instead of only the cookie cache.
        XCTAssertEqual(indexFetchCount, 2, "401 handling should force a fresh API key fetch, not just invalidate the cookie cache")
    }
}

private final class StubCredentialProvider: CredentialProvider {
    func getCredential() async -> String? {
        let creds = AntigravityCredentials(sapisid: "fake-sapisid", cookieString: "SAPISID=fake-sapisid")
        guard let data = try? JSONEncoder().encode(creds) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveCredential(_ credential: String) {}
}

/// Separate stub from AntigravityApiKeyProviderTests' StubURLProtocol (that one is file-private),
/// scoped to this file so the two test files don't collide on a shared static handler.
private final class AntigravityStubURLProtocol: URLProtocol {
    static var handler: ((URL) -> (Int, String)?)?

    static func makeSession(handler: @escaping (URL) -> (Int, String)?) -> URLSession {
        Self.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AntigravityStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let result = Self.handler?(url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (status, body) = result
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
