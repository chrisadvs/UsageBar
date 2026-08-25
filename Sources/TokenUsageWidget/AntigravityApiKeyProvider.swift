import Foundation

/// Extracts Antigravity's own public browser API key at runtime instead of shipping a frozen
/// copy in source. This key is not a secret or a per-account credential — it's a literal string
/// constant compiled into Antigravity's own JS frontend bundle (`this.apiKey="AIzaSy..."`),
/// served unauthenticated from Google's static CDN (gstatic.com) to every visitor, byte-for-byte
/// identical, before any login happens. Confirmed by fetching both resources directly and
/// finding the exact same key value Antigravity's own network traffic sends.
public enum AntigravityFrontendKeyParser {
    /// Antigravity's index page loads its compiled frontend via a `<script src="...">` tag
    /// pointing at a versioned gstatic.com bundle URL. The version segment in that URL changes
    /// whenever Google redeploys the frontend, so it must be discovered fresh each time rather
    /// than hardcoded.
    static func extractBundleScriptURL(fromIndexHTML html: String) -> URL? {
        let pattern = #"<script[^>]*src="(https://www\.gstatic\.com/_/mss/boq-jetski/[^"]+)""#
        guard let match = firstMatch(pattern: pattern, in: html) else { return nil }
        return URL(string: match)
    }

    /// Inside the bundle, the key is assigned to `this.apiKey` in two near-identical request-
    /// interceptor classes. The bundle separately contains an unrelated Firebase web config
    /// object (`apiKey: "AIzaSy..."`, no `this.` prefix, used for push notifications) — matching
    /// specifically on `this.apiKey=` excludes that unrelated key.
    static func extractApiKey(fromBundleJS js: String) -> String? {
        let pattern = #"this\.apiKey="(AIzaSy[A-Za-z0-9_-]+)""#
        return firstMatch(pattern: pattern, in: js)
    }

    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }
}

public actor AntigravityApiKeyProvider {
    public static let shared = AntigravityApiKeyProvider()

    private static let indexURL = URL(string: "https://antigravity.google.com/")!
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36"
    private static let cacheTTL: TimeInterval = 86400 // 24 hours, mirrors PricingService's refresh cadence

    private let session: URLSession
    private var cachedKey: String?
    private var lastFetchedAt: Date?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Returns the current key, fetching a fresh copy from Antigravity's live frontend if the
    /// cache is stale or empty. Falls back to whatever was last known good on fetch failure
    /// (e.g. transient network error) rather than failing outright.
    public func getApiKey(force: Bool = false, now: Date = Date()) async -> String? {
        if !force, let cached = cachedKey, let fetchedAt = lastFetchedAt, now.timeIntervalSince(fetchedAt) < Self.cacheTTL {
            return cached
        }

        guard let html = await fetchText(Self.indexURL) else {
            AppLogger.shared.log("[Antigravity] Failed to fetch index page while looking for API key.", level: .warn)
            return cachedKey
        }
        guard let bundleURL = AntigravityFrontendKeyParser.extractBundleScriptURL(fromIndexHTML: html) else {
            AppLogger.shared.log("[Antigravity] Could not locate frontend bundle script in index page.", level: .warn)
            return cachedKey
        }
        guard let js = await fetchText(bundleURL) else {
            AppLogger.shared.log("[Antigravity] Failed to fetch frontend bundle while looking for API key.", level: .warn)
            return cachedKey
        }
        guard let key = AntigravityFrontendKeyParser.extractApiKey(fromBundleJS: js) else {
            AppLogger.shared.log("[Antigravity] Could not locate API key inside frontend bundle.", level: .warn)
            return cachedKey
        }

        cachedKey = key
        lastFetchedAt = now
        AppLogger.shared.log("[Antigravity] Extracted API key dynamically from live frontend bundle.", level: .info)
        return key
    }

    private func fetchText(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}
