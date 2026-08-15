import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: NativeCodeStore

    var body: some View {
        Form {
            Section {
                if store.isGitHubConnected {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("@\(store.githubLogin)")
                                .font(.body.weight(.semibold))
                            Text("GitHub token is stored in the iOS Keychain")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(NCColors.green)
                    }
                } else {
                    SecureField("github_pat_…", text: $store.tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                TextField("owner/repository", text: $store.repositoryDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(NCFont.codeSmall)

                if store.isGitHubConnected {
                    Button {
                        Task { await store.refreshGitHub() }
                    } label: {
                        Label("Load repository", systemImage: "arrow.down.circle")
                    }
                    .disabled(store.isRefreshing)

                    Button("Disconnect GitHub", role: .destructive) {
                        store.disconnectGitHub()
                    }
                } else {
                    Button {
                        Task { await store.connectGitHub() }
                    } label: {
                        HStack {
                            Label("Connect GitHub", systemImage: "link")
                            Spacer()
                            if store.isRefreshing { ProgressView() }
                        }
                    }
                }
            } header: {
                Text("GitHub")
            } footer: {
                Text("Use a fine-grained token with Metadata read access, Contents read/write and Actions read/write. The token never enters the project or a commit.")
            }

            Section("Project") {
                Button {
                    store.isShowingProjectImporter = true
                } label: {
                    Label("Open local folder", systemImage: "folder.badge.plus")
                }

                if store.projectSource != .none {
                    LabeledContent("Open", value: store.projectName)
                    LabeledContent("Source", value: store.projectSource == .github ? "GitHub" : "Local folder")
                    Button("Close project", role: .destructive) {
                        store.closeProject()
                    }
                }
            }

            Section("Appearance") {
                Picker("Accent", selection: $store.accent) {
                    ForEach(NCAccent.allCases) { accent in
                        Label(accent.rawValue.capitalized, systemImage: "circle.fill")
                            .foregroundStyle(accent.color)
                            .tag(accent)
                    }
                }
                .tint(store.accent.color)

                Toggle("Haptic feedback", isOn: $store.hapticsEnabled)
                Toggle("Reduce motion", isOn: $store.reduceMotion)
            }

            Section("About") {
                LabeledContent("NativeCode", value: "Native iOS workspace")
                LabeledContent("Interface", value: "SwiftUI")
                Label("No web view is used by the app.", systemImage: "iphone")
                    .foregroundStyle(.secondary)
            }

            if let lastError = store.lastError, !lastError.isEmpty {
                Section("Last error") {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(NCColors.red)
                }
            }
        }
        .tint(store.accent.color)
        .scrollContentBackground(.hidden)
    }
}
