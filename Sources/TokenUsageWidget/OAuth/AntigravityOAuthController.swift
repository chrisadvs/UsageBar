import Foundation
import AppKit

@MainActor
class AntigravityOAuthController {
    static let shared = AntigravityOAuthController()
    
    private let clientId = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    private let scopes = "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/cclog https://www.googleapis.com/auth/experimentsandconfigs"
    
    private var server: LocalOAuthServer?
    var onLoginSuccess: (() -> Void)?
    
    func startLogin() {
        guard server == nil else { return }
        
        let localServer = LocalOAuthServer()
        let port: UInt16
        do {
            port = try localServer.start()
        } catch {
            print("Failed to start local OAuth server: \(error)")
            return
        }
        self.server = localServer
        
        let verifier = PKCE.generateCodeVerifier()
        let challenge = PKCE.generateCodeChallenge(from: verifier)
        let redirectUri = "http://127.0.0.1:\(port)/oauth-callback"
        
        localServer.onCodeReceived = { [weak self] code in
            self?.server = nil // clean up
            Task {
                do {
                    try await self?.exchangeCodeForToken(code: code, redirectUri: redirectUri, verifier: verifier)
                    DispatchQueue.main.async {
                        self?.onLoginSuccess?()
                    }
                } catch {
                    print("Failed to exchange code: \(error)")
                }
            }
        }
        
        var authComponents = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        authComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        guard let authURL = authComponents.url else { return }
        NSWorkspace.shared.open(authURL)
    }
    
    var urlSession: URLSession = .shared
    
    func exchangeCodeForToken(code: String, redirectUri: String, verifier: String) async throws {
        let tokenUrl = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri)
        ]
        
        request.httpBody = components.query?.data(using: .utf8)
        
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw APIError.invalidResponse
        }
        
        // Save tokens
        if let refreshToken = json["refresh_token"] as? String {
            AntigravityCredentialProvider.shared.saveRefreshToken(refreshToken)
        }
        
        let expiresIn = (json["expires_in"] as? Double) ?? 3599.0
        let expiryDate = Date().addingTimeInterval(expiresIn - 60) // 1 minute buffer
        AntigravityCredentialProvider.shared.setAccessToken(accessToken, expiry: expiryDate)
    }
}
