import SwiftUI

struct SourceControlView: View {
    @EnvironmentObject private var store: NativeCodeStore

    var body: some View {
        List {
            Section("Working Tree") {
                if store.modifiedFiles.isEmpty {
                    Label("Working tree clean", systemImage: "checkmark.circle")
                        .foregroundStyle(NCColors.green)
                } else {
                    ForEach(store.modifiedFiles) { file in
                        Button {
                            Task {
                                await store.selectFile(file)
                                store.select(.workspace)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                NCFileIcon(kind: file.kind)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.path)
                                        .font(NCFont.codeSmall)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("Modified")
                                        .font(.caption)
                                        .foregroundStyle(NCColors.yellow)
                                }
                                Spacer()
                                Text("M")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(NCColors.yellow)
                            }
                        }
                    }
                }
            }

            Section("Branches") {
                if store.branches.isEmpty {
                    Label("No branches loaded", systemImage: "arrow.triangle.branch")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.branches) { branch in
                        Button {
                            store.selectBranch(branch.name)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: branch.name == store.currentBranch ? "checkmark.circle.fill" : "arrow.triangle.branch")
                                    .foregroundStyle(branch.name == store.currentBranch ? store.accent.color : NCColors.secondary)
                                Text(branch.name)
                                    .font(NCFont.codeSmall)
                                Spacer()
                                if branch.isProtected {
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section("Recent Commits") {
                if store.commits.isEmpty {
                    Label("No commits loaded", systemImage: "clock")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.commits) { commit in
                        NCCommitRow(commit: commit)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable {
            await store.refreshGitHub()
        }
    }
}

struct NCCommitRow: View {
    let commit: NCCommit

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(commit.message)
                .font(.body.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(commit.hash)
                    .font(NCFont.metadata)
                    .foregroundStyle(NCColors.accent)
                Text(commit.author)
                Text(commit.relativeDate)
                Spacer()
                if commit.additions > 0 || commit.deletions > 0 {
                    Text("+\(commit.additions)")
                        .foregroundStyle(NCColors.green)
                    Text("−\(commit.deletions)")
                        .foregroundStyle(NCColors.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

struct ActionsView: View {
    @EnvironmentObject private var store: NativeCodeStore

    var body: some View {
        List {
            Section {
                if store.workflowRuns.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ContentUnavailableView(
                            "No workflow runs",
                            systemImage: "play.rectangle",
                            description: Text("Runs from the selected GitHub repository will appear here.")
                        )
                        if store.isGitHubConnected {
                            Button {
                                Task { await store.runWorkflow() }
                            } label: {
                                Label("Run ci.yml", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(store.accent.color)
                        }
                    }
                } else {
                    ForEach(store.workflowRuns) { run in
                        NCWorkflowRow(run: run)
                    }
                }
            } header: {
                HStack {
                    Text("Workflow Runs")
                    Spacer()
                    if store.isRunningWorkflow {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable {
            await store.refreshGitHub()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.runWorkflow() }
                } label: {
                    Image(systemName: "play.fill")
                }
                .disabled(store.isRunningWorkflow || !store.isGitHubConnected)
                .accessibilityLabel("Run workflow")
            }
        }
    }
}

struct NCWorkflowRow: View {
    let run: NCWorkflowRun

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: run.status.symbolName)
                .font(.title3)
                .foregroundStyle(run.status.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(run.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(run.branch)
                    Text(run.relativeDate)
                    if run.duration != "—" { Text(run.duration) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }
}

struct GitHubOverviewView: View {
    @EnvironmentObject private var store: NativeCodeStore

    var body: some View {
        Group {
            if store.isGitHubConnected {
                List {
                    Section("Account") {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("@\(store.githubLogin)")
                                    .font(.body.weight(.semibold))
                                Text("Connected through the iOS Keychain")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(store.accent.color)
                        }
                    }

                    Section("Repository") {
                        Button {
                            store.select(.workspace)
                        } label: {
                            HStack {
                                Label(store.repositoryName, systemImage: "network")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent("Branch", value: store.currentBranch.isEmpty ? "—" : store.currentBranch)
                        LabeledContent("Files", value: "\(store.workspaceEntries.filter { !$0.isDirectory }.count)")
                        LabeledContent("Commits loaded", value: "\(store.commits.count)")
                    }

                    Section("Actions") {
                        Button {
                            Task { await store.refreshGitHub() }
                        } label: {
                            Label("Refresh repository", systemImage: "arrow.clockwise")
                        }
                        Button {
                            store.select(.settings)
                        } label: {
                            Label("Repository settings", systemImage: "gearshape")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            } else {
                VStack(spacing: 18) {
                    Spacer()
                    ContentUnavailableView(
                        "GitHub is not connected",
                        systemImage: "link",
                        description: Text("Add a fine-grained token in Settings to load repositories, branches, commits and Actions.")
                    )
                    Button {
                        store.select(.settings)
                    } label: {
                        Label("Open GitHub Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(store.accent.color)
                    Spacer()
                }
                .padding(.horizontal, 24)
            }
        }
    }
}
