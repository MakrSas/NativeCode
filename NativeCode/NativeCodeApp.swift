import SwiftUI
import UniformTypeIdentifiers

@main
struct NativeCodeApp: App {
    @StateObject private var store = NativeCodeStore()

    var body: some Scene {
        WindowGroup {
            NativeCodeShell()
                .environmentObject(store)
        }
    }
}

struct NativeCodeShell: View {
    @EnvironmentObject private var store: NativeCodeStore
    @State private var isSidebarPresented = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                NavigationStack {
                    activeView
                        .navigationTitle(navigationTitle)
                        .navigationBarTitleDisplayMode(.large)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    withAnimation(store.reduceMotion ? nil : .snappy(duration: 0.28)) {
                                        isSidebarPresented.toggle()
                                    }
                                } label: {
                                    Image(systemName: "sidebar.left")
                                }
                                .accessibilityLabel("Project navigator")
                            }

                            ToolbarItemGroup(placement: .topBarTrailing) {
                                if !store.branches.isEmpty {
                                    Menu {
                                        Section("Branches") {
                                            ForEach(store.branches) { branch in
                                                Button {
                                                    store.selectBranch(branch.name)
                                                } label: {
                                                    Label(
                                                        branch.name,
                                                        systemImage: branch.name == store.currentBranch ? "checkmark" : "arrow.triangle.branch"
                                                    )
                                                }
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "arrow.triangle.branch")
                                    }
                                    .accessibilityLabel("Branches")
                                }

                                Button {
                                    Task { await store.refreshGitHub() }
                                } label: {
                                    Image(systemName: store.isRefreshing ? "hourglass" : "arrow.clockwise")
                                }
                                .disabled(store.isRefreshing)
                                .accessibilityLabel("Refresh project")

                                Menu {
                                    Button {
                                        store.isShowingCommandPalette = true
                                    } label: {
                                        Label("Command Palette", systemImage: "command")
                                    }
                                    Button {
                                        store.isShowingCommitComposer = true
                                    } label: {
                                        Label("Commit Changes", systemImage: "arrow.up.circle")
                                    }
                                    .disabled(store.modifiedFiles.isEmpty)
                                    Button {
                                        store.select(.settings)
                                    } label: {
                                        Label("Settings", systemImage: "gearshape")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .accessibilityLabel("More actions")
                            }
                        }
                        .toolbarBackground(.visible, for: .navigationBar)
                        .toolbarBackground(NCColors.canvas, for: .navigationBar)
                }
                .background(NCColors.canvas)

                if isSidebarPresented {
                    Color.black.opacity(0.42)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(store.reduceMotion ? nil : .snappy(duration: 0.28)) {
                                isSidebarPresented = false
                            }
                        }

                    NCProjectSidebar {
                        withAnimation(store.reduceMotion ? nil : .snappy(duration: 0.28)) {
                            isSidebarPresented = false
                        }
                    }
                    .frame(width: min(350, geometry.size.width * 0.88))
                    .frame(maxHeight: .infinity)
                    .background(.regularMaterial)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 26,
                            topTrailingRadius: 26,
                            style: .continuous
                        )
                    )
                    .shadow(color: .black.opacity(0.34), radius: 28, x: 12, y: 0)
                    .transition(.move(edge: .leading))
                    .gesture(
                        DragGesture(minimumDistance: 16)
                            .onEnded { value in
                                guard value.translation.width < -70 else { return }
                                withAnimation(store.reduceMotion ? nil : .snappy(duration: 0.28)) {
                                    isSidebarPresented = false
                                }
                            }
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $store.isShowingProjectImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { store.importLocalProject(from: url) }
            case .failure(let error):
                store.lastError = error.localizedDescription
            }
        }
        .sheet(isPresented: $store.isShowingCommitComposer) {
            NCCommitComposer()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $store.isShowingCommandPalette) {
            NCCommandPalette()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .bottom) {
            if let toastMessage = store.toastMessage {
                NCToast(message: toastMessage)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(store.reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.toastMessage)
        .onChange(of: store.selectedPanel) { _ in
            if isSidebarPresented {
                withAnimation(store.reduceMotion ? nil : .snappy(duration: 0.28)) {
                    isSidebarPresented = false
                }
            }
        }
    }

    private var navigationTitle: String {
        if store.selectedPanel == .workspace, !store.projectName.isEmpty {
            return store.projectName
        }
        return store.selectedPanel.title
    }

    @ViewBuilder
    private var activeView: some View {
        switch store.selectedPanel {
        case .workspace:
            WorkspaceView()
        case .sourceControl:
            SourceControlView()
        case .actions:
            ActionsView()
        case .github:
            GitHubOverviewView()
        case .settings:
            SettingsView()
        }
    }
}

struct NCProjectSidebar: View {
    @EnvironmentObject private var store: NativeCodeStore
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(NCColors.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)

                Text("NativeCode")
                    .font(.title2.weight(.bold))

                Spacer()

                Menu {
                    Button {
                        store.isShowingProjectImporter = true
                        dismiss()
                    } label: {
                        Label("Open Local Folder", systemImage: "folder.badge.plus")
                    }
                    Button {
                        store.select(.settings)
                        dismiss()
                    } label: {
                        Label("Connect GitHub", systemImage: "link")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Add project")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            List {
                Section("Workspace") {
                    destinationRow(.workspace, title: "Editor")
                    destinationRow(.sourceControl, title: "Source Control", badge: store.modifiedFiles.count)
                    destinationRow(.actions, title: "Actions")
                }

                Section("Project") {
                    if store.projectSource == .none {
                        Button {
                            store.isShowingProjectImporter = true
                            dismiss()
                        } label: {
                            Label("Open a project", systemImage: "folder.badge.plus")
                        }
                        .ncListRow()
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: store.projectSource == .github ? "network" : "folder.fill")
                                .foregroundStyle(store.projectSource == .github ? NCColors.accent : NCColors.violet)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.projectName)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(1)
                                Text(store.projectSource == .github ? "GitHub repository" : "Local folder")
                                    .font(.caption)
                                    .foregroundStyle(NCColors.secondary)
                            }
                            Spacer()
                        }
                        .ncListRow()

                        ForEach(store.visibleWorkspaceEntries) { entry in
                            projectEntryRow(entry)
                        }

                        Button("Close project", role: .destructive) {
                            store.closeProject()
                        }
                        .ncListRow()
                    }
                }

                Section("GitHub") {
                    if store.isGitHubConnected {
                        destinationRow(.github, title: "Repository")
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(NCColors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("@\(store.githubLogin)")
                                    .font(.body.weight(.medium))
                                Text(store.repositoryName)
                                    .font(.caption)
                                    .foregroundStyle(NCColors.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Circle()
                                .fill(NCColors.green)
                                .frame(width: 8, height: 8)
                        }
                        .ncListRow()

                        if !store.currentBranch.isEmpty {
                            Menu {
                                ForEach(store.branches) { branch in
                                    Button {
                                        store.selectBranch(branch.name)
                                    } label: {
                                        Label(
                                            branch.name,
                                            systemImage: branch.name == store.currentBranch ? "checkmark" : "arrow.triangle.branch"
                                        )
                                    }
                                }
                            } label: {
                                Label(store.currentBranch, systemImage: "arrow.triangle.branch")
                                    .foregroundStyle(.primary)
                            }
                            .ncListRow()
                        }
                    } else {
                        Button {
                            store.select(.settings)
                            dismiss()
                        } label: {
                            Label("Connect GitHub", systemImage: "link")
                        }
                        .ncListRow()
                    }
                }

                Section {
                    destinationRow(.settings, title: "Settings")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func destinationRow(_ panel: NCPanel, title: String, badge: Int = 0) -> some View {
        Button {
            store.select(panel)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: panel.symbolName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(store.selectedPanel == panel ? store.accent.color : NCColors.secondary)
                    .frame(width: 22)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NCColors.yellow)
                }
            }
        }
        .buttonStyle(.plain)
        .ncListRow()
    }

    @ViewBuilder
    private func projectEntryRow(_ entry: NCWorkspaceEntry) -> some View {
        Button {
            if entry.isDirectory {
                store.toggleDirectory(entry)
            } else {
                Task {
                    await store.selectFile(entry)
                    dismiss()
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: entry.isDirectory && !store.collapsedFolders.contains(entry.path) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(entry.isDirectory ? NCColors.secondary : .clear)
                    .frame(width: 10)
                NCFileIcon(kind: entry.kind, isExpanded: entry.isDirectory && !store.collapsedFolders.contains(entry.path))
                Text(entry.name)
                    .font(entry.isDirectory ? .body.weight(.medium) : NCFont.codeSmall)
                    .foregroundStyle(entry.path == store.activeFilePath ? .primary : NCColors.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if entry.isModified {
                    Circle()
                        .fill(NCColors.yellow)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.leading, CGFloat(entry.depth) * 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ncListRow()
    }
}

struct NCCommand: Identifiable {
    let id: String
    let title: String
    let symbolName: String
    let panel: NCPanel?
    let action: Action

    enum Action: Equatable {
        case navigate
        case commit
        case run
    }
}

struct NCCommandPalette: View {
    @EnvironmentObject private var store: NativeCodeStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var commands: [NCCommand] {
        let base = [
            NCCommand(id: "editor", title: "Open Editor", symbolName: "folder", panel: .workspace, action: .navigate),
            NCCommand(id: "source-control", title: "Open Source Control", symbolName: "arrow.triangle.branch", panel: .sourceControl, action: .navigate),
            NCCommand(id: "actions", title: "Open Actions", symbolName: "play.rectangle", panel: .actions, action: .navigate),
            NCCommand(id: "github", title: "Open GitHub", symbolName: "network", panel: .github, action: .navigate),
            NCCommand(id: "settings", title: "Open Settings", symbolName: "gearshape", panel: .settings, action: .navigate),
            NCCommand(id: "commit", title: "Commit Changes", symbolName: "arrow.up.circle", panel: nil, action: .commit),
            NCCommand(id: "run", title: "Run GitHub Actions", symbolName: "play.fill", panel: .actions, action: .run)
        ]
        return base.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(commands) { command in
                Button {
                    perform(command)
                } label: {
                    Label(command.title, systemImage: command.symbolName)
                }
                .disabled(command.action == .commit && store.modifiedFiles.isEmpty)
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Search commands")
            .navigationTitle("Command Palette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func perform(_ command: NCCommand) {
        switch command.action {
        case .navigate:
            if let panel = command.panel { store.select(panel) }
        case .commit:
            store.isShowingCommitComposer = true
        case .run:
            store.select(.actions)
            Task { await store.runWorkflow() }
        }
        dismiss()
    }
}

struct NCCommitComposer: View {
    @EnvironmentObject private var store: NativeCodeStore
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Commit message") {
                    TextField("Describe this change", text: $message, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Files") {
                    if store.modifiedFiles.isEmpty {
                        ContentUnavailableView("No changes", systemImage: "checkmark.circle", description: Text("Edit a file before creating a commit."))
                    } else {
                        ForEach(store.modifiedFiles) { file in
                            Label(file.path, systemImage: file.kind.symbolName)
                                .foregroundStyle(file.kind.color)
                        }
                    }
                }

                if store.projectSource == .local {
                    Section {
                        Label("Local projects are saved to their folder. GitHub commits require a GitHub project.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Commit Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.isShowingCommitComposer = false
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commit") {
                        Task { await store.commitDraft(message: message) }
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.modifiedFiles.isEmpty)
                }
            }
        }
    }
}
