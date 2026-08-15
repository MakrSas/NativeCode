import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject private var store: NativeCodeStore

    var body: some View {
        Group {
            if store.projectSource == .none {
                NCEmptyProjectView()
            } else if store.activeFile == nil {
                NCProjectOverview()
            } else {
                NCCodeEditor()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NCColors.canvas)
    }
}

struct NCEmptyProjectView: View {
    @EnvironmentObject private var store: NativeCodeStore

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ContentUnavailableView(
                "No project open",
                systemImage: "folder.badge.plus",
                description: Text("Open a local folder or connect GitHub to load a real project tree.")
            )

            VStack(spacing: 12) {
                Button {
                    store.isShowingProjectImporter = true
                } label: {
                    Label("Open Local Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(store.accent.color)

                if !store.isGitHubConnected {
                    Button {
                        store.select(.settings)
                    } label: {
                        Label("Connect GitHub", systemImage: "link")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        Task { await store.refreshGitHub() }
                    } label: {
                        Label("Open GitHub Repository", systemImage: "network")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

struct NCProjectOverview: View {
    @EnvironmentObject private var store: NativeCodeStore

    private var fileCount: Int {
        store.workspaceEntries.filter { !$0.isDirectory }.count
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: store.projectSource == .github ? "network" : "folder.fill")
                        .font(.title2)
                        .foregroundStyle(store.projectSource == .github ? store.accent.color : NCColors.violet)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.projectName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(projectSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }

            Section("Project") {
                LabeledContent("Files", value: "\(fileCount)")
                if !store.currentBranch.isEmpty {
                    LabeledContent("Branch", value: store.currentBranch)
                }
                LabeledContent("Source", value: store.projectSource == .github ? "GitHub" : "Local folder")
            }

            Section("Editor") {
                Label("Choose a file from the project navigator", systemImage: "sidebar.left")
                    .foregroundStyle(.secondary)
                if store.projectSource == .github {
                    Label("Changes can be committed through Source Control", systemImage: "arrow.up.circle")
                } else {
                    Label("Local edits are saved directly to the selected folder", systemImage: "internaldrive")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable {
            if store.projectSource == .github { await store.refreshGitHub() }
        }
    }

    private var projectSubtitle: String {
        if store.projectSource == .github {
            return store.currentBranch.isEmpty ? "GitHub repository" : "GitHub · \(store.currentBranch)"
        }
        return "Local folder"
    }
}

struct NCCodeEditor: View {
    @EnvironmentObject private var store: NativeCodeStore

    private var activeFile: NCWorkspaceEntry? { store.activeFile }

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            editorBreadcrumb
            if store.isEditing {
                TextEditor(
                    text: Binding(
                        get: { store.editorText },
                        set: { store.updateEditorText($0) }
                    )
                )
                .font(NCFont.code)
                .foregroundStyle(.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NCColors.canvas)
            } else {
                NCCodePreview(text: store.editorText)
            }
            editorStatus
        }
        .background(NCColors.canvas)
    }

    private var editorToolbar: some View {
        HStack(spacing: 12) {
            NCFileIcon(kind: activeFile?.kind ?? .text)
            VStack(alignment: .leading, spacing: 2) {
                Text(activeFile?.name ?? "No file")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if let path = activeFile?.path {
                    Text(path)
                        .font(NCFont.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if activeFile?.isModified == true {
                Circle()
                    .fill(NCColors.yellow)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Unsaved changes")
            }
            Button {
                store.toggleEditing()
            } label: {
                Image(systemName: store.isEditing ? "checkmark" : "pencil")
            }
            .buttonStyle(.bordered)
            .tint(store.isEditing ? NCColors.green : store.accent.color)
            .accessibilityLabel(store.isEditing ? "Save file" : "Edit file")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(NCColors.grouped)
    }

    private var editorBreadcrumb: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
            Text(store.projectName)
                .lineLimit(1)
            if let path = activeFile?.path {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                Text(path)
                    .lineLimit(1)
            }
            Spacer()
        }
        .font(NCFont.metadata)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(NCColors.elevated)
    }

    private var editorStatus: some View {
        HStack(spacing: 14) {
            Text(languageName)
            Text("UTF-8")
            Spacer()
            if activeFile?.isModified == true {
                NCStatusBadge(title: "Modified", color: NCColors.yellow, symbolName: "circle.fill")
            } else {
                NCStatusBadge(title: "Synced", color: NCColors.green, symbolName: "checkmark.circle.fill")
            }
        }
        .font(NCFont.metadata)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(NCColors.grouped)
    }

    private var languageName: String {
        switch activeFile?.kind {
        case .swift: return "Swift"
        case .json: return "JSON"
        case .markdown: return "Markdown"
        case .yaml: return "YAML"
        case .text, .folder, .none: return "Text"
        }
    }
}

struct NCCodePreview: View {
    let text: String

    var body: some View {
        if text.isEmpty {
            ContentUnavailableView("No readable text", systemImage: "doc.text", description: Text("This file is empty or is not a UTF-8 text file."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { index, line in
                        NCCodeLine(number: index + 1, text: String(line))
                    }
                }
                .padding(.vertical, 12)
            }
            .background(NCColors.canvas)
        }
    }
}

struct NCCodeLine: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(format: "%4d", number))
                .font(NCFont.codeSmall)
                .foregroundStyle(.tertiary)
                .frame(width: 38, alignment: .trailing)
            highlightedText
                .font(NCFont.code)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 24)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 23, alignment: .leading)
    }

    private var highlightedText: Text {
        let keywords: Set<String> = [
            "import", "struct", "class", "enum", "protocol", "extension", "private", "public", "internal",
            "var", "let", "func", "return", "if", "else", "switch", "case", "guard", "for", "in", "some",
            "async", "await", "throws", "throw", "where"
        ]
        let tokens = text.split(separator: " ", omittingEmptySubsequences: false)
        var result = Text("")

        for (index, token) in tokens.enumerated() {
            let raw = String(token)
            let normalized = raw.trimmingCharacters(in: .punctuationCharacters)
            let color: Color
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                color = NCColors.green
            } else if raw.hasPrefix("\"") || raw.hasSuffix("\"") {
                color = NCColors.orange
            } else if keywords.contains(normalized) {
                color = NCColors.violet
            } else if ["true", "false", "nil"].contains(normalized) {
                color = NCColors.yellow
            } else if raw.first == "." {
                color = NCColors.orange
            } else {
                color = .primary
            }

            result = result + Text(raw).foregroundColor(color)
            if index < tokens.count - 1 {
                result = result + Text(" ")
            }
        }

        return result
    }
}
