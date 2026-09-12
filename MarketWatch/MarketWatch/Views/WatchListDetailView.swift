import SwiftUI
import SwiftData

struct WatchListDetailView: View {
    @Bindable var watchList: WatchList
    @Environment(\.modelContext) private var modelContext

    @AppStorage("spreadsheetID") private var spreadsheetID = ""
    @State private var isAddingScrip = false
    @State private var refreshError: String?

    private var sortedScrips: [Scrip] {
        watchList.scrips.sorted { $0.companyName < $1.companyName }
    }

    var body: some View {
        List {
            ForEach(sortedScrips) { scrip in
                ScripRow(scrip: scrip)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(scrip)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
            }
        }
        .navigationTitle(watchList.name)
        .overlay {
            if watchList.scrips.isEmpty {
                ContentUnavailableView(
                    "No Scrips Yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Tap + to search and add a company.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingScrip = true
                } label: {
                    Label("Add Scrip", systemImage: "plus")
                }
            }
        }
        .refreshable {
            await refreshPrices()
        }
        .sheet(isPresented: $isAddingScrip) {
            AddScripView(watchList: watchList)
        }
        .alert("Couldn't Refresh Prices", isPresented: Binding(
            get: { refreshError != nil },
            set: { if !$0 { refreshError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(refreshError ?? "")
        }
    }

    private func refreshPrices() async {
        do {
            let quotes = try await GoogleSheetsService.shared.fetchQuotes(spreadsheetID: spreadsheetID)
            var matchedAny = false
            for scrip in watchList.scrips {
                let key = "\(scrip.exchange.rawValue):\(scrip.symbol.uppercased())"
                guard let quote = quotes[key] else { continue }
                matchedAny = true
                scrip.lastPrice = quote.price
                scrip.lastChange = quote.change
                scrip.lastPercentChange = quote.percentChange
                scrip.lastUpdated = .now
            }
            if !matchedAny && !watchList.scrips.isEmpty {
                refreshError = "No matching rows found in the Google Sheet for these scrips. Check Settings and the Sheet layout in the README."
            }
        } catch {
            refreshError = error.localizedDescription
        }
    }
}

private struct ScripRow: View {
    let scrip: Scrip

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(scrip.companyName).font(.body)
                HStack(spacing: 6) {
                    Text(scrip.symbol)
                    Text(scrip.exchange.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let price = scrip.lastPrice {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(price, format: .number.precision(.fractionLength(2)))
                        .font(.body.monospacedDigit())
                    if let percentChange = scrip.lastPercentChange {
                        Text(String(format: "%+.2f%%", percentChange))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(percentChange >= 0 ? .green : .red)
                    }
                }
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
    }
}
