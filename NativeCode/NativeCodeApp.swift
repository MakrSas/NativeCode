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
    @State private var edgeDragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = min(350, geometry.size.width * 0.84)
            let surfaceOffset = isSidebarPresented ? drawerWidth : edgeDragOffset
            let isSurfaceDimmed = isSidebarPresented || edgeDragOffset > 0

            ZStack(alignment: .leading) {
                // The navigator is the bottom layer. The editor surface above it
                // moves as one full-size piece; it is never re-laid out to fit
                // beside the drawer.
                Color.black
                    .ignoresSafeArea()

                ZStack(alignment: .top) {
                    Color.black

                    NCProjectSidebar {
                        withAnimation(store.reduceMotion ? nil : .snappy(duration: 0.28)) {
                            isSidebarPresented = false
                            edgeDragOffset = 0
                        }
                    }
                    .frame(width: drawerWidth, height: geometry.size.height, alignment: .top)
                }
                .frame(width: drawerWidth, height: geometry.size.height, alignment: .top)
                .background(Color.black)
                .clipped()
                .ignoresSafeArea()

                NavigationStack {
                    activeView
                        .navigationTitle(navigationTitle)
                        .navigationBarTitleDisplayMode(.large)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    withAnimation(store.reduceMotion ? nil : .snappy(duration: 0.28)) {
                                        isSidebarPresented.toggle()
                                        edgeDragOffset = 0
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
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(NCColors.canvas)
                // ContainerRelativeShape follows the device container, while the
                // surface itself remains the original screen width when shifted.
                .clipShape(ContainerRelativeShape())
                .offset(x: surfaceOffset)
                .colorMultiply(isSurfaceDimmed ? Color(white: 0.78) : .white)
                .shadow(
                    color: isSurfaceDimmed ? .black.opacity(0.38) : .clear,
                    radius: isSurfaceDimmed ? 24 : 0,
                    x: isSurfaceDimmed ? -10 : 0,
                    y: 0
                )
                .zIndex(1)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 16)
                        .onChanged { value in
                            guard !isSidebarPresented,
                                  value.startLocation.x <= 44,
                                  value.translation.width > 0 else { return }
                            edgeDragOffset = min(drawerWidth, value.translation.width)
                        }
                        .onEnded { value in
                            let animation = store.reduceMotion ? nil : Animation.snappy(duration: 0.28)

                            if isSidebarPresented {
                                guard value.translation.width < -70 else { return }
                                withAnimation(animation) {
                                    isSidebarPresented = false
                                    edgeDragOffset = 0
                                }
                                return
                            }

                            let startedAtLeadingEdge = value.startLocation.x <= 44
                            let openThreshold = max(70, drawerWidth * 0.22)
                            let shouldOpen = startedAtLeadingEdge && value.translation.width >= openThreshold
                            withAnimation(animation) {
                                isSidebarPresented = shouldOpen
                                edgeDragOffset = 0
                            }
                        }
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
        }
        .ignoresSafeArea()
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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                sidebarHeader

                Divider()
                    .padding(.horizontal, 6)

                sidebarSectionTitle("Workspace")
                VStack(spacing: 5) {
                    destinationRow(.workspace, title: "Editor")
                    destinationRow(.sourceControl, title: "Source Control", badge: store.modifiedFiles.count)
                    destinationRow(.actions, title: "Actions")
                }

                sidebarSectionTitle("Project")
                VStack(spacing: 5) {
                    if store.projectSource == .none {
                        Button {
                            store.isShowingProjectImporter = true
                            dismiss()
                        } label: {
                            Label("Open a project", systemImage: "folder.badge.plus")
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .sidebarRow()
                    } else {
                        HStack(spacing: 11) {
                            Image(systemName: store.projectSource == .github ? "network" : "folder.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(store.projectSource == .github ? NCColors.accent : NCColors.violet)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.projectName)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(1)
                                Text(store.projectSource == .github ? "GitHub repository" : "Local folder")
                                    .font(.caption)
                                    .foregroundStyle(NCColors.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(NCColors.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .sidebarRow()

                        ForEach(store.visibleWorkspaceEntries) { entry in
                            projectEntryRow(entry)
                        }

                        Button("Close project", role: .destructive) {
                            store.closeProject()
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        .sidebarRow(tint: NCColors.red.opacity(0.10))
                    }
                }

                sidebarSectionTitle("GitHub")
                VStack(spacing: 5) {
                    if store.isGitHubConnected {
                        destinationRow(.github, title: "Repository")
                        HStack(spacing: 11) {
                            Image(systemName: "person.crop.circle")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(NCColors.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("@\(store.githubLogin)")
                                    .font(.body.weight(.medium))
                                Text(store.repositoryName)
                                    .font(.caption)
                                    .foregroundStyle(NCColors.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Circle()
                                .fill(NCColors.green)
                                .frame(width: 8, height: 8)
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .sidebarRow()

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
                                HStack(spacing: 11) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(NCColors.yellow)
                                        .frame(width: 24)
                                    Text(store.currentBranch)
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(NCColors.tertiary)
                                }
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .sidebarRow()
                        }
                    } else {
                        Button {
                            store.select(.settings)
                            dismiss()
                        } label: {
                            Label("Connect GitHub", systemImage: "link")
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .sidebarRow(tint: NCColors.accent.opacity(0.12))
                    }
                }

                sidebarSectionTitle("Preferences")
                destinationRow(.settings, title: "Settings")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 30)
        }
        .background(Color.black)
        .foregroundStyle(.primary)
        .safeAreaPadding(.top, 8)
        .safeAreaPadding(.bottom, 8)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 12) {
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.09), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close project navigator")

            VStack(alignment: .leading, spacing: 2) {
                Text("NativeCode")
                    .font(.title2.weight(.bold))
                Text(store.projectName.isEmpty ? "Project navigator" : store.projectName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(NCColors.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

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
                    .frame(width: 38, height: 38)
                    .background(NCColors.accent.opacity(0.16), in: Circle())
                    .foregroundStyle(NCColors.accent)
            }
            .accessibilityLabel("Add project")
        }
        .padding(.horizontal, 6)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func sidebarSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.top, 22)
            .padding(.bottom, 7)
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
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sidebarRow(selected: store.selectedPanel == panel)
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
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sidebarRow(selected: entry.path == store.activeFilePath)
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
