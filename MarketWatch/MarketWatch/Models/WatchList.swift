import Foundation
import SwiftData

@Model
final class WatchList {
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Scrip.watchList)
    var scrips: [Scrip] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}
