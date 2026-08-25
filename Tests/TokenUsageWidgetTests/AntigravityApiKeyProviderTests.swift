import XCTest
@testable import TokenUsageWidget

final class AntigravityApiKeyProviderTests: XCTestCase {
    func testExtractBundleScriptURLFromIndexHTML() {
        let html = """
        <html>
        <head>
        <link rel="preload" href="https://www.gstatic.com/_/mss/boq-jetski/_/ss/k=boq-jetski.GoogleAntigravity.lriTLDLgc6c.L.B1.O/am=BECAAQ/d=1/ed=1/rs=AGC4Xsp1b-XO7IBEFqvdN87X862Sp7NwiA/m=_b" as="style">
        </head>
        <body>
        <script src="https://www.gstatic.com/_/mss/boq-jetski/_/js/k=boq-jetski.GoogleAntigravity.en_US.CbSRpFmazxU.2018.O/d=1/excm=_b/ed=1/dg=0/wt=2/ujg=1/rs=AGC4Xspse0sh1KdehBTcOrzvztHnRdV7Dg/dti=1/m=_b"></script>
        </body>
        </html>
        """
        let url = AntigravityFrontendKeyParser.extractBundleScriptURL(fromIndexHTML: html)
        XCTAssertEqual(url?.absoluteString, "https://www.gstatic.com/_/mss/boq-jetski/_/js/k=boq-jetski.GoogleAntigravity.en_US.CbSRpFmazxU.2018.O/d=1/excm=_b/ed=1/dg=0/wt=2/ujg=1/rs=AGC4Xspse0sh1KdehBTcOrzvztHnRdV7Dg/dti=1/m=_b")
    }

    func testExtractBundleScriptURLReturnsNilWhenAbsent() {
        let html = "<html><body>no matching script here</body></html>"
        XCTAssertNil(AntigravityFrontendKeyParser.extractBundleScriptURL(fromIndexHTML: html))
    }

    func testExtractApiKeyFromBundleJS() {
        // Trimmed, minified fixture modeled on the real bundle: two request-interceptor
        // classes assign the target key via `this.apiKey=`, and an unrelated Firebase web
        // config object elsewhere in the same file uses a *different* key with a plain
        // `apiKey:` object-literal field (no `this.` prefix) — the parser must pick the
        // former and ignore the latter.
        let js = """
        var pM = class {
            constructor(a=0) {
                this.apiKey="AIzaSyFAKEtargetFAKEtargetFAKEtar";
                this.Fc = a
            }
        }, qM = class {
            constructor(a=0) {
                this.apiKey="AIzaSyFAKEtargetFAKEtargetFAKEtar";
                this.Fc = a
            }
        };
        var SS = {
            apiKey: "AIzaSyFAKEfirebaseFAKEfirebaseFAK",
            authDomain: "antigravity-external-web.firebaseapp.com"
        };
        """
        XCTAssertEqual(AntigravityFrontendKeyParser.extractApiKey(fromBundleJS: js), "AIzaSyFAKEtargetFAKEtargetFAKEtar")
    }

    func testExtractApiKeyReturnsNilWhenAbsent() {
        let js = "var x = { apiKey: \"AIzaSyFAKEfirebaseFAKEfirebaseFAK\" };"
        XCTAssertNil(AntigravityFrontendKeyParser.extractApiKey(fromBundleJS: js))
    }

    func testGetApiKeyCachesWithinTTL() async {
        var callCount = 0
        let session = StubURLProtocol.makeSession { url in
            callCount += 1
            if url.host == "antigravity.google.com" {
                return (200, "<script src=\"https://www.gstatic.com/_/mss/boq-jetski/_/js/k=fake\"></script>")
            } else {
                return (200, "this.apiKey=\"AIzaSyFAKEFAKEFAKEFAKEFAKEFAKEFAKE\";")
            }
        }
        let provider = AntigravityApiKeyProvider(session: session)
        let now = Date()

        let first = await provider.getApiKey(now: now)
        XCTAssertEqual(first, "AIzaSyFAKEFAKEFAKEFAKEFAKEFAKEFAKE")
        XCTAssertEqual(callCount, 2) // index + bundle

        let second = await provider.getApiKey(now: now.addingTimeInterval(60))
        XCTAssertEqual(second, "AIzaSyFAKEFAKEFAKEFAKEFAKEFAKEFAKE")
        XCTAssertEqual(callCount, 2, "should reuse cache within TTL, not refetch")

        let third = await provider.getApiKey(now: now.addingTimeInterval(90000)) // past 24h TTL
        XCTAssertEqual(third, "AIzaSyFAKEFAKEFAKEFAKEFAKEFAKEFAKE")
        XCTAssertEqual(callCount, 4, "should refetch once TTL has elapsed")
    }

    func testGetApiKeyFallsBackToCachedValueOnFetchFailure() async {
        var shouldFail = false
        let session = StubURLProtocol.makeSession { url in
            if shouldFail {
                return nil
            }
            if url.host == "antigravity.google.com" {
                return (200, "<script src=\"https://www.gstatic.com/_/mss/boq-jetski/_/js/k=fake\"></script>")
            } else {
                return (200, "this.apiKey=\"AIzaSyFAKEFAKEFAKEFAKEFAKEFAKEFAKE\";")
            }
        }
        let provider = AntigravityApiKeyProvider(session: session)
        let now = Date()

        let first = await provider.getApiKey(now: now)
        XCTAssertEqual(first, "AIzaSyFAKEFAKEFAKEFAKEFAKEFAKEFAKE")

        shouldFail = true
        let second = await provider.getApiKey(force: true, now: now)
        XCTAssertEqual(second, "AIzaSyFAKEFAKEFAKEFAKEFAKEFAKEFAKE", "should fall back to last known-good value on fetch failure")
    }
}

/// Minimal `URLProtocol` stub so these tests don't hit the real network. Returning `nil` from
/// the handler simulates a request failure (matches `try?` swallowing an error in the code
/// under test).
private final class StubURLProtocol: URLProtocol {
    static var handler: ((URL) -> (Int, String)?)?

    static func makeSession(handler: @escaping (URL) -> (Int, String)?) -> URLSession {
        Self.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
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
