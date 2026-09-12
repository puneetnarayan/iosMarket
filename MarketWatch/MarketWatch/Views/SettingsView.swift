import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = GoogleAuthService.shared

    @AppStorage("spreadsheetID") private var spreadsheetID = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if auth.isSignedIn {
                        Label("Signed in to Google", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Sign Out", role: .destructive) {
                            auth.signOut()
                        }
                    } else {
                        Button {
                            signIn()
                        } label: {
                            if isSigningIn {
                                ProgressView()
                            } else {
                                Text("Sign in with Google")
                            }
                        }
                        .disabled(isSigningIn || !auth.isConfigured)
                        if !auth.isConfigured {
                            Text("No Google OAuth client ID is configured — add one in project.yml (see README) and regenerate the Xcode project.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Google Account")
                } footer: {
                    Text("Needed so the app can read and update your prices Google Sheet.")
                }

                Section {
                    TextField("Spreadsheet ID", text: $spreadsheetID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Prices Google Sheet")
                } footer: {
                    Text("The long ID in the sheet's URL: docs.google.com/spreadsheets/d/[SPREADSHEET_ID]/edit. The sheet needs a tab named \"Prices\" with GOOGLEFINANCE formulas — see README for the exact layout.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func signIn() {
        isSigningIn = true
        errorMessage = nil
        Task {
            defer { isSigningIn = false }
            do {
                try await auth.signIn()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
