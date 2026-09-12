import Foundation

/// Talks to NSE India's own website JSON endpoint (nseindia.com/api/search/autocomplete)
/// purely to help you find a company's symbol while adding it to a watchlist.
///
/// IMPORTANT: This is an UNOFFICIAL, undocumented endpoint the nseindia.com website itself
/// uses — there is no public NSE API for third-party apps. It can change shape, start
/// rejecting requests, or rate-limit without notice, and NSE's site terms may restrict
/// automated access. This is provided for personal experimentation only; verify current
/// behavior yourself (Safari/Chrome devtools -> Network tab on nseindia.com) if it stops
/// working. If search stops working, you can still add any scrip manually in AddScripView.
///
/// Live prices are NOT fetched here — see GoogleSheetsService, which reads them from a
/// Google Sheet using GOOGLEFINANCE(), covering both NSE and BSE.
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
    /// before we call the JSON endpoint. This is a commonly used workaround, not a
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
}

enum NSEServiceError: LocalizedError {
    case requestFailed

    var errorDescription: String? {
        "The request to NSE failed or was blocked."
    }
}
