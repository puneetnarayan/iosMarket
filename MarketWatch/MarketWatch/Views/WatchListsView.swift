import SwiftUI
import SwiftData

struct WatchListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WatchList.createdAt) private var watchLists: [WatchList]

    @State private var isAddingList = false
    @State private var newListName = ""
    @State private var renamingList: WatchList?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(watchLists) { list in
                    NavigationLink(value: list) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(list.name).font(.headline)
                            Text("\(list.scrips.count) scrip\(list.scrips.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            modelContext.delete(list)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            renameText = list.name
                            renamingList = list
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
            .navigationTitle("Watchlists")
            .navigationDestination(for: WatchList.self) { list in
                WatchListDetailView(watchList: list)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newListName = ""
                        isAddingList = true
                    } label: {
                        Label("New List", systemImage: "plus")
                    }
                }
            }
            .overlay {
                if watchLists.isEmpty {
                    ContentUnavailableView(
                        "No Watchlists",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Tap + to create your first watchlist.")
                    )
                }
            }
            .alert("New Watchlist", isPresented: $isAddingList) {
                TextField("Name", text: $newListName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { createList() }
                    .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .alert("Rename Watchlist", isPresented: renamingBinding) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveRename() }
                    .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renamingList != nil }, set: { if !$0 { renamingList = nil } })
    }

    private func createList() {
        let trimmed = newListName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(WatchList(name: trimmed))
    }

    private func saveRename() {
        guard let list = renamingList else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        list.name = trimmed
        renamingList = nil
    }
}
