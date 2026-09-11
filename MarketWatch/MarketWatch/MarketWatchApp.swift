import SwiftUI
import SwiftData

@main
struct MarketWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchListsView()
        }
        .modelContainer(for: [WatchList.self, Scrip.self])
    }
}
