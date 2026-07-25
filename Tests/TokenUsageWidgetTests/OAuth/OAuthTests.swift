import XCTest
@testable import TokenUsageWidget

class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    
    override class func canInit(with request: URLRequest) -> Bool { return true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { return request }
    
    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Handler is unavailable.")
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
}

final class OAuthTests: XCTestCase {
    var session: URLSession!
    
    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
    }
    
    func testCodeVerifierAndChallenge() {
        let verifier = PKCE.generateCodeVerifier()
        XCTAssertFalse(verifier.isEmpty)
        XCTAssertFalse(verifier.contains("+"))
        XCTAssertFalse(verifier.contains("/"))
        XCTAssertFalse(verifier.contains("="))
        
        let challenge = PKCE.generateCodeChallenge(from: verifier)
        XCTAssertFalse(challenge.isEmpty)
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
        XCTAssertFalse(challenge.contains("="))
    }
    
    @MainActor
    func testExchangeCodeForToken() async throws {
        let jsonString = """
        {
            "access_token": "ya29.fake_access_token",
            "expires_in": 3599,
            "refresh_token": "1//fake_refresh_token",
            "scope": "https://www.googleapis.com/auth/cloud-platform",
            "token_type": "Bearer"
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://oauth2.googleapis.com/token")
            XCTAssertEqual(request.httpMethod, "POST")
            
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, jsonString.data(using: .utf8)!)
        }
        
        let controller = AntigravityOAuthController.shared
        controller.urlSession = session
        
        try await controller.exchangeCodeForToken(code: "fake_code", redirectUri: "http://127.0.0.1:12345/oauth-callback", verifier: "fake_verifier")
        
        // Note: Keychain access is not tested here due to code signing restrictions in test runner
    }
    
    func testRefreshAccessToken() async throws {
        let jsonString = """
        {
            "access_token": "ya29.new_fake_access_token",
            "expires_in": 3599,
            "scope": "https://www.googleapis.com/auth/cloud-platform",
            "token_type": "Bearer"
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://oauth2.googleapis.com/token")
            XCTAssertEqual(request.httpMethod, "POST")
            
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, jsonString.data(using: .utf8)!)
        }
        
        let provider = AntigravityCredentialProvider.shared
        provider.urlSession = session
        
        let newToken = try await provider.refreshAccessToken(refreshToken: "1//fake_refresh_token")
        XCTAssertEqual(newToken, "ya29.new_fake_access_token")
        
        // Also check if currentAccessToken is set in memory
        let token = await provider.getCredential()
        XCTAssertEqual(token, "ya29.new_fake_access_token")
    }
}
