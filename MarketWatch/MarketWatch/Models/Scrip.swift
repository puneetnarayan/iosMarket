import Foundation
import SwiftData

enum Exchange: String, Codable, CaseIterable, Identifiable {
    case nse = "NSE"
    case bse = "BSE"

    var id: String { rawValue }
}

@Model
final class Scrip {
    var symbol: String
    var companyName: String
    var exchangeRaw: String
    var addedAt: Date

    var lastPrice: Double?
    var lastChange: Double?
    var lastPercentChange: Double?
    var lastUpdated: Date?

    var watchList: WatchList?

    var exchange: Exchange {
        get { Exchange(rawValue: exchangeRaw) ?? .nse }
        set { exchangeRaw = newValue.rawValue }
    }

    init(symbol: String, companyName: String, exchange: Exchange, addedAt: Date = .now) {
        self.symbol = symbol
        self.companyName = companyName
        self.exchangeRaw = exchange.rawValue
        self.addedAt = addedAt
    }
}
