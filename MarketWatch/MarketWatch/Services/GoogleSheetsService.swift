import Foundation

/// Reads and appends rows in a Google Sheet that prices scrips with GOOGLEFINANCE(),
/// via Google's official, documented Sheets API v4 (https://sheets.googleapis.com/v4/...).
/// That API surface is stable — what's NOT guaranteed is GOOGLEFINANCE itself: it's a
/// Sheets formula function, not covered by any API stability contract, and its coverage
/// of individual NSE/BSE symbols can be incomplete or change without notice.
///
/// Expected sheet layout — a tab named "Prices", header in row 1, data from row 2:
///   A: Symbol   B: Exchange (NSE/BSE)   C: Price   D: Change   E: %Change
/// `appendScripRow` writes rows shaped like:
///   TCS | NSE | =GOOGLEFINANCE("NSE:TCS","price") | =GOOGLEFINANCE("NSE:TCS","change") | =GOOGLEFINANCE("NSE:TCS","changepct")
/// See README for how to create the sheet and share it with your Google account.
actor GoogleSheetsService {
    static let shared = GoogleSheetsService()

    private let sheetTab = "Prices"

    struct Quote {
        let price: Double
        let change: Double
        let percentChange: Double
    }

    func fetchQuotes(spreadsheetID: String) async throws -> [String: Quote] {
        guard !spreadsheetID.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw GoogleSheetsError.missingSpreadsheetID
        }
        let token = try await GoogleAuthService.shared.validAccessToken()

        var components = URLComponents(
            string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(sheetTab)!A2:E1000"
        )!
        components.queryItems = [URLQueryItem(name: "valueRenderOption", value: "UNFORMATTED_VALUE")]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)

        let decoded = try JSONDecoder().decode(ValuesResponse.self, from: data)
        var quotes: [String: Quote] = [:]
        for row in decoded.values ?? [] {
            guard row.count >= 5,
                  case let .string(symbol) = row[0],
                  case let .string(exchange) = row[1],
                  let price = row[2].doubleValue else { continue }
            let key = "\(exchange.uppercased()):\(symbol.uppercased())"
            quotes[key] = Quote(
                price: price,
                change: row[3].doubleValue ?? 0,
                percentChange: row[4].doubleValue ?? 0
            )
        }
        return quotes
    }

    func appendScripRow(spreadsheetID: String, symbol: String, exchange: Exchange) async throws {
        guard !spreadsheetID.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw GoogleSheetsError.missingSpreadsheetID
        }
        let token = try await GoogleAuthService.shared.validAccessToken()

        let ticker = "\(exchange.rawValue):\(symbol.uppercased())"
        let row: [String] = [
            symbol.uppercased(),
            exchange.rawValue,
            "=GOOGLEFINANCE(\"\(ticker)\",\"price\")",
            "=GOOGLEFINANCE(\"\(ticker)\",\"change\")",
            "=GOOGLEFINANCE(\"\(ticker)\",\"changepct\")"
        ]

        var components = URLComponents(
            string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetID)/values/\(sheetTab)!A:E:append"
        )!
        components.queryItems = [
            URLQueryItem(name: "valueInputOption", value: "USER_ENTERED"),
            URLQueryItem(name: "insertDataOption", value: "INSERT_ROWS")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AppendBody(values: [row]))

        let (_, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleSheetsError.requestFailed
        }
    }

    private struct AppendBody: Encodable {
        let values: [[String]]
    }

    private struct ValuesResponse: Decodable {
        let values: [[SheetValue]]?
    }

    private enum SheetValue: Decodable {
        case string(String)
        case number(Double)
        case other

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let stringValue = try? container.decode(String.self) {
                self = .string(stringValue)
            } else if let doubleValue = try? container.decode(Double.self) {
                self = .number(doubleValue)
            } else {
                self = .other
            }
        }

        var doubleValue: Double? {
            switch self {
            case .number(let value): return value
            case .string(let value): return Double(value)
            case .other: return nil
            }
        }
    }
}

enum GoogleSheetsError: LocalizedError {
    case missingSpreadsheetID
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .missingSpreadsheetID: return "No Google Sheet is configured yet — add its Spreadsheet ID in Settings."
        case .requestFailed: return "The request to Google Sheets failed."
        }
    }
}
