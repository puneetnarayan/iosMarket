import Foundation

/// Talks to NSE India's own website JSON endpoints (nseindia.com/api/...).
///
/// IMPORTANT: These are UNOFFICIAL, undocumented endpoints the nseindia.com website itself
/// uses — there is no public NSE API for third-party apps. They can change shape, start
/// rejecting requests, or rate-limit without notice, and NSE's site terms may restrict
/// automated access. This is provided for personal experimentation only; verify current
/// behavior yourself (Safari/Chrome devtools -> Network tab on nseindia.com) if it stops
/// working, and don't build anything beyond personal use on top of it without checking
/// NSE's terms of use.
///
/// There is no equivalent implementation for BSE here — I don't have verified, current
/// knowledge of a stable unofficial BSE JSON endpoint, so BSE scrips are added manually
/// (see AddScripView) without live price fetching.
actor NSEService {
    static let shared = NSEService()

    private let session: URLSession
    private var hasWarmedUpSession = false

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    private var commonHeaders: [String: String] {
        [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "en-US,en;q=0.9",
            "Referer": "https://www.nseindia.com/"
        ]
    }

    /// NSE's API rejects cold requests that don't already carry cookies from a normal
    /// page load. Loading the homepage once per app session picks up those cookies
    /// before we call the JSON endpoints. This is a commonly used workaround, not a
    /// guaranteed contract with NSE, and may stop working if their bot-protection changes.
    private func warmUpSessionIfNeeded() async {
        guard !hasWarmedUpSession else { return }
        var request = URLRequest(url: URL(string: "https://www.nseindia.com/")!)
        commonHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        _ = try? await session.data(for: request)
        hasWarmedUpSession = true
    }

    struct SearchResult: Identifiable, Hashable {
        var id: String { symbol }
        let symbol: String
        let companyName: String
    }

    struct Quote {
        let lastPrice: Double
        let change: Double
        let percentChange: Double
    }

    func search(_ query: String) async throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        await warmUpSessionIfNeeded()

        var components = URLComponents(string: "https://www.nseindia.com/api/search/autocomplete")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        var request = URLRequest(url: components.url!)
        commonHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)

        let decoded = try JSONDecoder().decode(AutocompleteResponse.self, from: data)
        return decoded.symbols.map { SearchResult(symbol: $0.symbol, companyName: $0.symbol_info) }
    }

    func quote(for symbol: String) async throws -> Quote {
        await warmUpSessionIfNeeded()

        var components = URLComponents(string: "https://www.nseindia.com/api/quote-equity")!
        components.queryItems = [URLQueryItem(name: "symbol", value: symbol)]

        var request = URLRequest(url: components.url!)
        commonHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)

        let decoded = try JSONDecoder().decode(QuoteResponse.self, from: data)
        return Quote(
            lastPrice: decoded.priceInfo.lastPrice,
            change: decoded.priceInfo.change,
            percentChange: decoded.priceInfo.pChange
        )
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSEServiceError.requestFailed
        }
    }

    private struct AutocompleteResponse: Decodable {
        struct Symbol: Decodable {
            let symbol: String
            let symbol_info: String
        }
        let symbols: [Symbol]
    }

    private struct QuoteResponse: Decodable {
        struct PriceInfo: Decodable {
            let lastPrice: Double
            let change: Double
            let pChange: Double
        }
        let priceInfo: PriceInfo
    }
}

enum NSEServiceError: LocalizedError {
    case requestFailed

    var errorDescription: String? {
        "The request to NSE failed or was blocked."
    }
}
