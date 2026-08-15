import Foundation
import Security
import SwiftUI

enum NCPanel: String, CaseIterable, Identifiable {
    case workspace
    case sourceControl
    case actions
    case github
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: return "Workspace"
        case .sourceControl: return "Source Control"
        case .actions: return "Actions"
        case .github: return "GitHub"
        case .settings: return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .workspace: return "folder"
        case .sourceControl: return "arrow.triangle.branch"
        case .actions: return "play.rectangle"
        case .github: return "network"
        case .settings: return "gearshape"
        }
    }
}

enum NCProjectSource: String {
    case none
    case local
    case github
}

enum NCAccent: String, CaseIterable, Identifiable, Hashable {
    case cyan
    case violet
    case green
    case orange

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .cyan: return NCColors.accent
        case .violet: return NCColors.violet
        case .green: return NCColors.green
        case .orange: return NCColors.orange
        }
    }
}

enum NCFileKind: String, Hashable {
    case swift
    case json
    case markdown
    case yaml
    case text
    case folder

    init(path: String, isDirectory: Bool = false) {
        if isDirectory {
            self = .folder
            return
        }

        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "swift": self = .swift
        case "json": self = .json
        case "md", "markdown": self = .markdown
        case "yml", "yaml": self = .yaml
        default: self = .text
        }
    }

    var symbolName: String {
        switch self {
        case .swift: return "swift"
        case .json: return "curlybraces"
        case .markdown: return "text.alignleft"
        case .yaml: return "list.bullet.rectangle"
        case .text: return "doc.text"
        case .folder: return "folder"
        }
    }

    var color: Color {
        switch self {
        case .swift: return NCColors.orange
        case .json: return NCColors.yellow
        case .markdown: return NCColors.accent
        case .yaml: return NCColors.pink
        case .text: return NCColors.secondary
        case .folder: return NCColors.violet
        }
    }
}

struct NCWorkspaceEntry: Identifiable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool
    let depth: Int
    let kind: NCFileKind
    var isModified: Bool

    var id: String { path }

    init(path: String, isDirectory: Bool, isModified: Bool = false) {
        self.path = path
        self.name = path.split(separator: "/").last.map(String.init) ?? path
        self.isDirectory = isDirectory
        self.depth = max(0, path.split(separator: "/").count - 1)
        self.kind = NCFileKind(path: path, isDirectory: isDirectory)
        self.isModified = isModified
    }
}

struct NCCommit: Identifiable, Hashable {
    let hash: String
    let message: String
    let author: String
    let relativeDate: String
    let additions: Int
    let deletions: Int

    var id: String { hash }
}

struct NCBranch: Identifiable, Hashable {
    let name: String
    let isProtected: Bool

    var id: String { name }
}

struct NCWorkflowRun: Identifiable, Hashable {
    let id: Int
    let name: String
    let status: Status
    let branch: String
    let duration: String
    let relativeDate: String

    enum Status: String, Hashable {
        case success
        case running
        case failure

        var color: Color {
            switch self {
            case .success: return NCColors.green
            case .running: return NCColors.yellow
            case .failure: return NCColors.red
            }
        }

        var symbolName: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .running: return "clock.arrow.circlepath"
            case .failure: return "xmark.circle.fill"
            }
        }
    }
}

@MainActor
final class NativeCodeStore: ObservableObject {
    @Published var selectedPanel: NCPanel = .workspace
    @Published var projectSource: NCProjectSource = .none
    @Published var projectName = ""
    @Published var repositoryName = "MakrSas/NativeCode"
    @Published var repositoryDraft = "MakrSas/NativeCode"
    @Published var currentBranch = ""
    @Published var workspaceEntries: [NCWorkspaceEntry] = []
    @Published var collapsedFolders: Set<String> = []
    @Published var activeFilePath: String?
    @Published var editorText = ""
    @Published var isEditing = false
    @Published var isShowingCommitComposer = false
    @Published var isShowingCommandPalette = false
    @Published var isShowingProjectImporter = false
    @Published var isRefreshing = false
    @Published var isRunningWorkflow = false
    @Published var toastMessage: String?
    @Published var tokenDraft = ""
    @Published var githubLogin = ""
    @Published var lastError: String?
    @Published var accent: NCAccent = .cyan
    @Published var hapticsEnabled = true
    @Published var reduceMotion = false

    @Published private(set) var isGitHubConnected = false
    @Published private(set) var commits: [NCCommit] = []
    @Published private(set) var branches: [NCBranch] = []
    @Published private(set) var workflowRuns: [NCWorkflowRun] = []

    private let tokenStore = NCTokenStore()
    private let github = GitHubClient()
    private var localRootURL: URL?

    var activeFile: NCWorkspaceEntry? {
        guard let activeFilePath else { return nil }
        return workspaceEntries.first(where: { $0.path == activeFilePath })
    }

    var modifiedFiles: [NCWorkspaceEntry] {
        workspaceEntries.filter { !$0.isDirectory && $0.isModified }
    }

    var visibleWorkspaceEntries: [NCWorkspaceEntry] {
        var visible: [NCWorkspaceEntry] = []
        var hiddenDepth: Int?

        for entry in workspaceEntries {
            if let depth = hiddenDepth {
                if entry.depth > depth { continue }
                hiddenDepth = nil
            }

            visible.append(entry)
            if entry.isDirectory && collapsedFolders.contains(entry.path) {
                hiddenDepth = entry.depth
            }
        }
        return visible
    }

    init() {
        isGitHubConnected = tokenStore.load() != nil
        if isGitHubConnected {
            Task { await loadGitHubSession() }
        }
    }

    func select(_ panel: NCPanel) {
        guard selectedPanel != panel else { return }
        selectedPanel = panel
        if hapticsEnabled { NCHaptics.selection() }
    }

    func toggleDirectory(_ entry: NCWorkspaceEntry) {
        guard entry.isDirectory else { return }
        if collapsedFolders.contains(entry.path) {
            collapsedFolders.remove(entry.path)
        } else {
            collapsedFolders.insert(entry.path)
        }
        if hapticsEnabled { NCHaptics.selection() }
    }

    func selectBranch(_ name: String) {
        currentBranch = name
        if projectSource == .github {
            Task { await refreshGitHub() }
        }
        if hapticsEnabled { NCHaptics.selection() }
        showToast("Switched to \(name)")
    }

    func importLocalProject(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            showToast("Could not open this folder")
            return
        }

        localRootURL?.stopAccessingSecurityScopedResource()
        localRootURL = url
        projectSource = .local
        projectName = url.lastPathComponent
        currentBranch = ""
        repositoryName = url.lastPathComponent
        repositoryDraft = "MakrSas/NativeCode"
        workspaceEntries = Self.localEntries(at: url)
        collapsedFolders = []
        commits = []
        branches = []
        workflowRuns = []
        clearActiveFile()
        showToast("Opened \(projectName)")
    }

    func closeProject() {
        localRootURL?.stopAccessingSecurityScopedResource()
        localRootURL = nil
        projectSource = .none
        projectName = ""
        workspaceEntries = []
        clearActiveFile()
        showToast("Project closed")
    }

    func selectFile(_ entry: NCWorkspaceEntry) async {
        guard !entry.isDirectory else {
            toggleDirectory(entry)
            return
        }

        activeFilePath = entry.path
        isEditing = false

        do {
            switch projectSource {
            case .local:
                guard let localRootURL else { throw NCGitHubError.invalidURL }
                editorText = try String(contentsOf: localRootURL.appendingPathComponent(entry.path), encoding: .utf8)
            case .github:
                guard let token = tokenStore.load() else { throw NCGitHubError.http(401, "GitHub is not connected") }
                editorText = try await github.fileContent(
                    token: token,
                    fullName: repositoryName,
                    path: entry.path,
                    branch: currentBranch
                ) ?? ""
            case .none:
                editorText = ""
            }
        } catch {
            editorText = ""
            lastError = error.localizedDescription
            showToast("Could not open \(entry.name)")
        }
    }

    func updateEditorText(_ value: String) {
        editorText = value
        guard let activeFilePath,
              let index = workspaceEntries.firstIndex(where: { $0.path == activeFilePath }) else { return }
        workspaceEntries[index].isModified = true
    }

    func toggleEditing() {
        if isEditing {
            saveCurrentFileIfLocal()
        } else {
            guard activeFile != nil else {
                showToast("Select a file first")
                return
            }
            isEditing = true
        }
        if hapticsEnabled { NCHaptics.selection() }
    }

    func connectGitHub() async {
        let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            showToast("Paste a GitHub token first")
            return
        }

        do {
            let viewer = try await github.viewer(token: token)
            try tokenStore.save(token)
            githubLogin = viewer.login
            isGitHubConnected = true
            tokenDraft = ""
            if hapticsEnabled { NCHaptics.success() }
            showToast("Connected as @\(viewer.login)")
            await refreshGitHub()
            selectedPanel = .workspace
        } catch {
            lastError = error.localizedDescription
            showToast("GitHub connection failed")
        }
    }

    func disconnectGitHub() {
        tokenStore.delete()
        githubLogin = ""
        isGitHubConnected = false
        commits = []
        branches = []
        workflowRuns = []
        if projectSource == .github {
            projectSource = .none
            projectName = ""
            workspaceEntries = []
            currentBranch = ""
            clearActiveFile()
        }
        showToast("GitHub disconnected")
    }

    func refreshGitHub() async {
        guard let token = tokenStore.load() else {
            showToast("Connect GitHub in Settings first")
            return
        }

        let fullName = repositoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fullName.split(separator: "/").count == 2 else {
            showToast("Use owner/repository")
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let repository = try await github.repository(token: token, fullName: fullName)
            let remoteBranches = try await github.branches(token: token, fullName: repository.fullName)
            let resolvedBranch = remoteBranches.contains(where: { $0.name == currentBranch })
                ? currentBranch
                : repository.defaultBranch
            let remoteTree = try await github.tree(token: token, fullName: repository.fullName, branch: resolvedBranch)
            let remoteCommits = try await github.commits(token: token, fullName: repository.fullName, branch: resolvedBranch)
            let remoteRuns = try await github.workflowRuns(token: token, fullName: repository.fullName)

            let unsavedPaths = Set(modifiedFiles.map(\.path))
            repositoryName = repository.fullName
            repositoryDraft = repository.fullName
            projectName = repository.fullName
            projectSource = .github
            currentBranch = resolvedBranch
            workspaceEntries = Self.entries(from: remoteTree, modifiedPaths: unsavedPaths)
            collapsedFolders = []
            branches = remoteBranches.map { NCBranch(name: $0.name, isProtected: $0.protected ?? false) }
            commits = remoteCommits.map {
                NCCommit(
                    hash: String($0.sha.prefix(7)),
                    message: $0.commit.message.components(separatedBy: .newlines).first ?? $0.commit.message,
                    author: $0.commit.author?.name ?? "GitHub",
                    relativeDate: ncRelativeDate($0.commit.author?.date),
                    additions: $0.stats?.additions ?? 0,
                    deletions: $0.stats?.deletions ?? 0
                )
            }
            workflowRuns = remoteRuns.compactMap { run in
                guard let id = run.id else { return nil }
                return NCWorkflowRun(
                    id: id,
                    name: run.name ?? "Workflow #\(run.runNumber ?? 0)",
                    status: run.resolvedStatus,
                    branch: run.headBranch ?? resolvedBranch,
                    duration: ncDuration(start: run.runStartedAt, end: run.updatedAt),
                    relativeDate: ncRelativeDate(run.updatedAt ?? run.runStartedAt)
                )
            }

            if let activeFilePath,
               let entry = workspaceEntries.first(where: { $0.path == activeFilePath && !$0.isDirectory }),
               !unsavedPaths.contains(entry.path) {
                editorText = try await github.fileContent(
                    token: token,
                    fullName: repository.fullName,
                    path: entry.path,
                    branch: resolvedBranch
                ) ?? ""
            } else if activeFilePath != nil && workspaceEntries.first(where: { $0.path == activeFilePath }) == nil {
                clearActiveFile()
            }

            showToast("Synced \(workspaceEntries.filter { !$0.isDirectory }.count) files")
        } catch {
            lastError = error.localizedDescription
            showToast("Could not refresh repository")
        }
    }

    func runWorkflow() async {
        guard let token = tokenStore.load(), isGitHubConnected else {
            showToast("Connect GitHub before running Actions")
            return
        }
        guard projectSource == .github, !currentBranch.isEmpty else {
            showToast("Open a GitHub repository first")
            return
        }

        isRunningWorkflow = true
        defer { isRunningWorkflow = false }
        do {
            try await github.dispatchWorkflow(
                token: token,
                fullName: repositoryName,
                workflowFile: "ci.yml",
                branch: currentBranch
            )
            if hapticsEnabled { NCHaptics.success() }
            showToast("Workflow queued")
            await refreshGitHub()
        } catch {
            lastError = error.localizedDescription
            showToast("Could not start workflow")
        }
    }

    func commitDraft(message: String) async {
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else {
            showToast("Add a commit message")
            return
        }
        guard let activeFile, !activeFile.isDirectory else {
            showToast("Select a file first")
            return
        }

        if projectSource == .local {
            saveCurrentFileIfLocal()
            isShowingCommitComposer = false
            showToast("Saved \(activeFile.name) locally")
            return
        }

        guard let token = tokenStore.load(), projectSource == .github else {
            showToast("Connect GitHub and open a repository first")
            return
        }

        do {
            try await github.upsertFile(
                token: token,
                fullName: repositoryName,
                path: activeFile.path,
                content: editorText,
                message: cleanMessage,
                branch: currentBranch
            )
            isShowingCommitComposer = false
            isEditing = false
            if hapticsEnabled { NCHaptics.success() }
            await refreshGitHub()
            showToast("Committed to \(currentBranch)")
        } catch {
            lastError = error.localizedDescription
            showToast("Commit failed — check token permissions")
        }
    }

    func showToast(_ message: String) {
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            if toastMessage == message { toastMessage = nil }
        }
    }

    private func loadGitHubSession() async {
        guard let token = tokenStore.load() else { return }
        if let viewer = try? await github.viewer(token: token) {
            githubLogin = viewer.login
            await refreshGitHub()
        } else {
            isGitHubConnected = false
        }
    }

    private func saveCurrentFileIfLocal() {
        guard projectSource == .local,
              let localRootURL,
              let activeFile else {
            isEditing = false
            return
        }

        do {
            try editorText.write(to: localRootURL.appendingPathComponent(activeFile.path), atomically: true, encoding: .utf8)
            markFileAsSaved(activeFile.path)
            isEditing = false
            showToast("Saved \(activeFile.name)")
        } catch {
            lastError = error.localizedDescription
            showToast("Could not save \(activeFile.name)")
        }
    }

    private func markFileAsSaved(_ path: String) {
        guard let index = workspaceEntries.firstIndex(where: { $0.path == path }) else { return }
        workspaceEntries[index].isModified = false
    }

    private func clearActiveFile() {
        activeFilePath = nil
        editorText = ""
        isEditing = false
    }

    private static func localEntries(at root: URL) -> [NCWorkspaceEntry] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var paths: [(String, Bool)] = []
        for case let url as URL in enumerator {
            let relativePath = url.path.replacingOccurrences(of: prefix, with: "")
            if relativePath == ".git" || relativePath.hasPrefix(".git/") { continue }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            let isDirectory = values?.isDirectory == true
            if isDirectory || values?.isRegularFile == true {
                paths.append((relativePath, isDirectory))
            }
        }

        return entries(from: paths)
    }

    private static func entries(from tree: [GitHubTreeEntryDTO], modifiedPaths: Set<String> = []) -> [NCWorkspaceEntry] {
        entries(from: tree.map { ($0.path, $0.type == "tree") }, modifiedPaths: modifiedPaths)
    }

    private static func entries(from paths: [(String, Bool)], modifiedPaths: Set<String> = []) -> [NCWorkspaceEntry] {
        var types: [String: Bool] = [:]
        for (path, isDirectory) in paths {
            types[path] = isDirectory
            let components = path.split(separator: "/")
            guard components.count > 1 else { continue }
            for index in 1..<(components.count) {
                let parent = components.prefix(index).joined(separator: "/")
                types[parent] = true
            }
        }

        return types.keys.sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }.map { path in
            NCWorkspaceEntry(path: path, isDirectory: types[path] == true, isModified: modifiedPaths.contains(path))
        }
    }
}

private func ncDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

private func ncRelativeDate(_ value: String?) -> String {
    guard let date = ncDate(value) else { return "—" }
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "now" }
    if seconds < 3_600 { return "\(seconds / 60)m ago" }
    if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
    return "\(seconds / 86_400)d ago"
}

private func ncDuration(start: String?, end: String?) -> String {
    guard let startDate = ncDate(start), let endDate = ncDate(end) else { return "—" }
    let totalSeconds = max(0, Int(endDate.timeIntervalSince(startDate)))
    if totalSeconds < 60 { return "\(totalSeconds)s" }
    return "\(totalSeconds / 60)m \(totalSeconds % 60)s"
}

struct NCTokenStore {
    private let service = "com.makrsas.NativeCode"
    private let account = "github-token"

    func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let status = SecItemAdd(insert as CFDictionary, nil)
            guard status == errSecSuccess else { throw NCGitHubError.keychain(status) }
        } else if updateStatus != errSecSuccess {
            throw NCGitHubError.keychain(updateStatus)
        }
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum NCGitHubError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "GitHub request URL is invalid."
        case let .http(code, message): return "GitHub returned HTTP \(code): \(message)"
        case let .keychain(status): return "Keychain error \(status)."
        }
    }
}

struct GitHubViewer: Decodable {
    let login: String
}

struct GitHubRepository: Decodable {
    let fullName: String
    let defaultBranch: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case defaultBranch = "default_branch"
    }
}

struct GitHubContent: Decodable {
    let sha: String?
    let content: String?
}

struct GitHubBranchDTO: Decodable {
    let name: String
    let protected: Bool?
}

struct GitHubTreeDTO: Decodable {
    let tree: [GitHubTreeEntryDTO]
}

struct GitHubTreeEntryDTO: Decodable {
    let path: String
    let type: String
}

struct GitHubCommitDTO: Decodable {
    let sha: String
    let commit: CommitDetails
    let stats: Stats?

    struct CommitDetails: Decodable {
        let message: String
        let author: Author?
    }

    struct Author: Decodable {
        let name: String?
        let date: String?
    }

    struct Stats: Decodable {
        let additions: Int?
        let deletions: Int?
    }
}

struct GitHubWorkflowRunsDTO: Decodable {
    let workflowRuns: [GitHubWorkflowRunDTO]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

struct GitHubWorkflowRunDTO: Decodable {
    let id: Int?
    let name: String?
    let status: String?
    let conclusion: String?
    let headBranch: String?
    let runStartedAt: String?
    let updatedAt: String?
    let runNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion
        case headBranch = "head_branch"
        case runStartedAt = "run_started_at"
        case updatedAt = "updated_at"
        case runNumber = "run_number"
    }

    var resolvedStatus: NCWorkflowRun.Status {
        if conclusion == "success" { return .success }
        if status == "queued" || status == "in_progress" || status == "waiting" {
            return .running
        }
        return .failure
    }
}

struct GitHubClient {
    private let session: URLSession
    private let decoder = JSONDecoder()

    private static let pathComponentAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func viewer(token: String) async throws -> GitHubViewer {
        try await request(path: "/user", token: token)
    }

    func repository(token: String, fullName: String) async throws -> GitHubRepository {
        try await request(path: "/repos/\(fullName)", token: token)
    }

    func branches(token: String, fullName: String) async throws -> [GitHubBranchDTO] {
        try await request(
            path: "/repos/\(fullName)/branches",
            queryItems: [URLQueryItem(name: "per_page", value: "100")],
            token: token
        )
    }

    func tree(token: String, fullName: String, branch: String) async throws -> [GitHubTreeEntryDTO] {
        guard let encodedBranch = branch.addingPercentEncoding(withAllowedCharacters: Self.pathComponentAllowed) else {
            throw NCGitHubError.invalidURL
        }
        let response: GitHubTreeDTO = try await request(
            path: "/repos/\(fullName)/git/trees/\(encodedBranch)",
            queryItems: [URLQueryItem(name: "recursive", value: "1")],
            token: token
        )
        return response.tree
    }

    func commits(token: String, fullName: String, branch: String) async throws -> [GitHubCommitDTO] {
        try await request(
            path: "/repos/\(fullName)/commits",
            queryItems: [
                URLQueryItem(name: "sha", value: branch),
                URLQueryItem(name: "per_page", value: "20")
            ],
            token: token
        )
    }

    func workflowRuns(token: String, fullName: String) async throws -> [GitHubWorkflowRunDTO] {
        let response: GitHubWorkflowRunsDTO = try await request(
            path: "/repos/\(fullName)/actions/runs",
            queryItems: [URLQueryItem(name: "per_page", value: "20")],
            token: token
        )
        return response.workflowRuns
    }

    func fileContent(token: String, fullName: String, path: String, branch: String) async throws -> String? {
        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw NCGitHubError.invalidURL
        }
        let payload: GitHubContent = try await request(
            path: "/repos/\(fullName)/contents/\(encodedPath)",
            queryItems: [URLQueryItem(name: "ref", value: branch)],
            token: token
        )
        guard let encoded = payload.content else { return nil }
        let cleaned = encoded.replacingOccurrences(of: "\n", with: "")
        guard let data = Data(base64Encoded: cleaned) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func dispatchWorkflow(token: String, fullName: String, workflowFile: String, branch: String) async throws {
        guard let url = URL(string: "https://api.github.com/repos/\(fullName)/actions/workflows/\(workflowFile)/dispatches") else {
            throw NCGitHubError.invalidURL
        }
        var request = makeRequest(url: url, token: token)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["ref": branch])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
    }

    func upsertFile(token: String, fullName: String, path: String, content: String, message: String, branch: String) async throws {
        guard let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.github.com/repos/\(fullName)/contents/\(encodedPath)") else {
            throw NCGitHubError.invalidURL
        }

        var currentSHA: String?
        let fetchURL = url.appending(queryItems: [URLQueryItem(name: "ref", value: branch)])
        do {
            let (data, response) = try await session.data(for: makeRequest(url: fetchURL, token: token))
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                currentSHA = try? decoder.decode(GitHubContent.self, from: data).sha
            }
        } catch {
            currentSHA = nil
        }

        var updateRequest = makeRequest(url: url, token: token)
        updateRequest.httpMethod = "PUT"
        updateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "message": message,
            "content": Data(content.utf8).base64EncodedString(),
            "branch": branch
        ]
        if let currentSHA { payload["sha"] = currentSHA }
        updateRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: updateRequest)
        try validate(response, data: data)
    }

    private func request<T: Decodable>(path: String, token: String) async throws -> T {
        try await request(path: path, queryItems: [], token: token)
    }

    private func request<T: Decodable>(path: String, queryItems: [URLQueryItem], token: String) async throws -> T {
        guard var components = URLComponents(string: "https://api.github.com\(path)") else {
            throw NCGitHubError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw NCGitHubError.invalidURL }
        let (data, response) = try await session.data(for: makeRequest(url: url, token: token))
        try validate(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func makeRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func validate(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NCGitHubError.http(-1, "Invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Request failed"
            throw NCGitHubError.http(http.statusCode, message)
        }
    }
}
