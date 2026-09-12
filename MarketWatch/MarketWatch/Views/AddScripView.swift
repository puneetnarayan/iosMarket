import SwiftUI
import SwiftData

struct AddScripView: View {
    let watchList: WatchList

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("spreadsheetID") private var spreadsheetID = ""

    @State private var query = ""
    @State private var results: [NSEService.SearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var addedSymbols: Set<String> = []

    @State private var manualCompanyName = ""
    @State private var manualSymbol = ""
    @State private var manualExchange: Exchange = .nse

    var body: some View {
        NavigationStack {
            List {
                if !query.isEmpty {
                    Section("NSE Search Results") {
                        if let searchError {
                            Text(searchError)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if results.isEmpty && !isSearching {
                            Text("No matches.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(results) { result in
                            Button {
                                addFromSearch(result)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(result.companyName)
                                        Text(result.symbol).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if addedSymbols.contains(result.symbol) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "plus.circle")
                                    }
                                }
                            }
                            .disabled(addedSymbols.contains(result.symbol))
                        }
                    }
                }

                Section {
                    TextField("Company name", text: $manualCompanyName)
                    TextField("Symbol (e.g. TCS, 500325)", text: $manualSymbol)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    Picker("Exchange", selection: $manualExchange) {
                        ForEach(Exchange.allCases) { exchange in
                            Text(exchange.rawValue).tag(exchange)
                        }
                    }
                    Button("Add") {
                        addManually()
                    }
                    .disabled(manualCompanyName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              manualSymbol.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Add Manually")
                } footer: {
                    Text("Adding a scrip appends a GOOGLEFINANCE row to your prices Google Sheet, so it needs to be configured in Settings first — otherwise the scrip is still added, just without a price row.")
                }
            }
            .searchable(text: $query, prompt: "Search NSE by company or symbol")
            .task(id: query) {
                await search()
            }
            .navigationTitle("Add to \(watchList.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            searchError = nil
            return
        }

        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        isSearching = true
        searchError = nil
        defer { isSearching = false }

        do {
            results = try await NSEService.shared.search(query)
        } catch {
            searchError = "Search failed. NSE's unofficial endpoint may be blocking requests — try again, or add the scrip manually below."
            results = []
        }
    }

    private func addFromSearch(_ result: NSEService.SearchResult) {
        let scrip = Scrip(symbol: result.symbol, companyName: result.companyName, exchange: .nse)
        scrip.watchList = watchList
        modelContext.insert(scrip)
        addedSymbols.insert(result.symbol)
        appendToPricesSheet(symbol: result.symbol, exchange: .nse)
    }

    private func addManually() {
        let name = manualCompanyName.trimmingCharacters(in: .whitespaces)
        let symbol = manualSymbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !name.isEmpty, !symbol.isEmpty else { return }

        let scrip = Scrip(symbol: symbol, companyName: name, exchange: manualExchange)
        scrip.watchList = watchList
        modelContext.insert(scrip)
        appendToPricesSheet(symbol: symbol, exchange: manualExchange)

        manualCompanyName = ""
        manualSymbol = ""
    }

    /// Best-effort: the scrip is already added locally regardless of whether this succeeds
    /// (no Google Sheet configured yet, not signed in, offline, etc.) — refreshing prices
    /// later will simply find no matching row for it until the sheet is set up.
    private func appendToPricesSheet(symbol: String, exchange: Exchange) {
        guard !spreadsheetID.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            try? await GoogleSheetsService.shared.appendScripRow(
                spreadsheetID: spreadsheetID,
                symbol: symbol,
                exchange: exchange
            )
        }
    }
}
