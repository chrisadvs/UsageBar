import XCTest
import WebKit
@testable import TokenUsageWidget

final class UsageAPIClientTests: XCTestCase {
    
    func testExtractLastActiveOrgFromCookieList() {
        let cookie1 = HTTPCookie(properties: [
            .domain: ".claude.ai",
            .path: "/",
            .name: "sessionKey",
            .value: "sk-123456789",
            .secure: true
        ])!
        
        let cookie2 = HTTPCookie(properties: [
            .domain: ".claude.ai",
            .path: "/",
            .name: "lastActiveOrg",
            .value: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            .secure: true
        ])!

        let orgId = UsageAPIClient.extractOrgId(from: [cookie1, cookie2])
        XCTAssertEqual(orgId, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    }
    
    func testExtractLastActiveOrgWhenMissing() {
        let cookie1 = HTTPCookie(properties: [
            .domain: ".claude.ai",
            .path: "/",
            .name: "sessionKey",
            .value: "sk-123456789",
            .secure: true
        ])!
        
        let orgId = UsageAPIClient.extractOrgId(from: [cookie1])
        XCTAssertNil(orgId)
    }
    
    func testExtractLastActiveOrgWhenEmptyValue() {
        let cookie1 = HTTPCookie(properties: [
            .domain: ".claude.ai",
            .path: "/",
            .name: "lastActiveOrg",
            .value: "",
            .secure: true
        ])!
        
        let orgId = UsageAPIClient.extractOrgId(from: [cookie1])
        XCTAssertNil(orgId)
    }
    
    func testExtractLastActiveOrgFromCookieString() {
        let cookieString = "sessionKey=sk-abc; lastActiveOrg=org-uuid-12345; test=1"
        let orgId = UsageAPIClient.extractOrgId(fromCookieString: cookieString)
        XCTAssertEqual(orgId, "org-uuid-12345")
    }
}
