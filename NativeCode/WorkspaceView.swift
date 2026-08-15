import SwiftUI
import UIKit

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
                NCNativeCodeTextView(
                    text: Binding(
                        get: { store.editorText },
                        set: { store.updateEditorText($0) }
                    ),
                    language: store.effectiveLanguage,
                    diagnostics: store.diagnostics
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NCColors.canvas)
            } else {
                NCCodePreview(text: store.editorText)
            }
            if !store.diagnostics.isEmpty {
                NCProblemsPanel(diagnostics: store.diagnostics)
            }
            if store.executionState != .idle {
                NCExecutionPanel()
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
                Task { await store.runCurrentFile() }
            } label: {
                Image(systemName: store.executionState == .running ? "hourglass" : "play.fill")
            }
            .buttonStyle(.bordered)
            .tint(store.accent.color)
            .disabled(activeFile == nil || store.executionState == .running)
            .accessibilityLabel("Run file")
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
            languageMenu
            Text("UTF-8")
            Spacer()
            if !store.diagnostics.isEmpty {
                NCStatusBadge(
                    title: "\(store.diagnostics.count) Problems",
                    color: NCColors.red,
                    symbolName: "xmark.octagon.fill"
                )
            } else if activeFile?.isModified == true {
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

    private var languageMenu: some View {
        Menu {
            Section("Language") {
                ForEach(NCLanguage.allCases) { language in
                    Button {
                        store.chooseLanguage(language)
                    } label: {
                        Label(language.title, systemImage: language.symbolName)
                        if store.selectedLanguage == language {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(store.effectiveLanguage.title, systemImage: store.effectiveLanguage.symbolName)
                .lineLimit(1)
        }
        .accessibilityLabel("Language: \(store.effectiveLanguage.title)")
    }
}

struct NCProblemsPanel: View {
    let diagnostics: [NCDiagnostic]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(NCColors.red)
                Text("Problems")
                    .font(.subheadline.weight(.semibold))
                Text("\(diagnostics.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NCColors.red)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            ScrollView(.vertical, showsIndicators: diagnostics.count > 4) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(diagnostics) { diagnostic in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: diagnostic.severity.symbolName)
                                .font(.caption)
                                .foregroundStyle(diagnostic.severity.color)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(diagnostic.message)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                Text("L\(diagnostic.line):\(diagnostic.column)")
                                    .font(NCFont.metadata)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: 132)
        }
        .background(NCColors.elevated)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

struct NCExecutionPanel: View {
    @EnvironmentObject private var store: NativeCodeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if store.executionState == .running {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: stateSymbol)
                        .foregroundStyle(stateColor)
                }
                Text("Run")
                    .font(.subheadline.weight(.semibold))
                Text(store.executionState.title)
                    .font(.caption)
                    .foregroundStyle(stateColor)
                Spacer()
            }
            Text(store.executionOutput)
                .font(NCFont.metadata)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NCColors.elevated)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var stateColor: Color {
        switch store.executionState {
        case .success: return NCColors.green
        case .failure: return NCColors.red
        case .unavailable: return NCColors.yellow
        case .idle, .running: return store.accent.color
        }
    }

    private var stateSymbol: String {
        switch store.executionState {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .unavailable: return "questionmark.circle.fill"
        case .idle, .running: return "play.circle.fill"
        }
    }
}

struct NCCodePreview: View {
    @EnvironmentObject private var store: NativeCodeStore
    let text: String

    var body: some View {
        if text.isEmpty {
            ContentUnavailableView("No readable text", systemImage: "doc.text", description: Text("This file is empty or is not a UTF-8 text file."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { index, line in
                        NCCodeLine(
                            number: index + 1,
                            text: String(line),
                            language: store.effectiveLanguage,
                            diagnostics: store.diagnostics
                        )
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
    let language: NCLanguage
    let diagnostics: [NCDiagnostic]

    private var lineDiagnostics: [NCDiagnostic] {
        diagnostics.filter { $0.line == number }
    }

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
        .frame(maxWidth: .infinity, minHeight: 23, alignment: .leading)
        .background(
            lineDiagnostics.contains(where: { $0.severity == .error })
                ? NCColors.red.opacity(0.10)
                : lineDiagnostics.isEmpty ? .clear : NCColors.yellow.opacity(0.08)
        )
        .overlay(alignment: .trailing) {
            if let diagnostic = lineDiagnostics.first {
                Image(systemName: diagnostic.severity.symbolName)
                    .font(.caption2)
                    .foregroundStyle(diagnostic.severity.color)
                    .padding(.trailing, 12)
            }
        }
    }

    private var highlightedText: Text {
        let string = text as NSString
        let tokens = NCSyntaxTokenizer.tokenize(text, language: language)
        var result = Text("")
        var cursor = 0

        for token in tokens {
            guard token.range.location >= cursor else { continue }
            if token.range.location > cursor {
                result = result + Text(string.substring(with: NSRange(location: cursor, length: token.range.location - cursor)))
            }
            result = result + Text(string.substring(with: token.range)).foregroundColor(token.kind.swiftUIColor)
            cursor = token.range.location + token.range.length
        }

        if cursor < string.length {
            result = result + Text(string.substring(from: cursor))
        }

        return result
    }
}

private enum NCSyntaxPalette {
    static let keyword = UIColor(red: 0.72, green: 0.55, blue: 1.0, alpha: 1)
    static let string = UIColor(red: 1.0, green: 0.64, blue: 0.30, alpha: 1)
    static let number = UIColor(red: 1.0, green: 0.80, blue: 0.35, alpha: 1)
    static let comment = UIColor(red: 0.40, green: 0.84, blue: 0.56, alpha: 1)
    static let type = UIColor(red: 0.38, green: 0.83, blue: 0.93, alpha: 1)
    static let function = UIColor(red: 0.42, green: 0.76, blue: 1.0, alpha: 1)
    static let property = UIColor(red: 0.41, green: 0.88, blue: 0.83, alpha: 1)
    static let builtin = UIColor(red: 0.94, green: 0.51, blue: 0.92, alpha: 1)
    static let literal = UIColor(red: 1.0, green: 0.46, blue: 0.64, alpha: 1)
    static let key = UIColor(red: 0.98, green: 0.72, blue: 0.32, alpha: 1)
    static let decorator = UIColor(red: 0.78, green: 0.57, blue: 1.0, alpha: 1)
    static let `operator` = UIColor(red: 0.96, green: 0.48, blue: 0.70, alpha: 1)
    static let punctuation = UIColor.secondaryLabel
    static let diagnostic = UIColor(red: 1.0, green: 0.28, blue: 0.34, alpha: 1)
}

private struct NCSyntaxToken {
    enum Kind: Hashable {
        case plain
        case keyword
        case string
        case number
        case comment
        case type
        case function
        case property
        case builtin
        case literal
        case key
        case decorator
        case markup
        case `operator`
        case punctuation

        var uiColor: UIColor {
            switch self {
            case .plain: return UIColor.label
            case .keyword: return NCSyntaxPalette.keyword
            case .string: return NCSyntaxPalette.string
            case .number: return NCSyntaxPalette.number
            case .comment: return NCSyntaxPalette.comment
            case .type: return NCSyntaxPalette.type
            case .function: return NCSyntaxPalette.function
            case .property: return NCSyntaxPalette.property
            case .builtin: return NCSyntaxPalette.builtin
            case .literal: return NCSyntaxPalette.literal
            case .key: return NCSyntaxPalette.key
            case .decorator: return NCSyntaxPalette.decorator
            case .markup: return NCSyntaxPalette.keyword
            case .operator: return NCSyntaxPalette.`operator`
            case .punctuation: return NCSyntaxPalette.punctuation
            }
        }

        var swiftUIColor: Color {
            switch self {
            case .plain: return .primary
            case .keyword, .markup: return NCColors.violet
            case .string: return NCColors.orange
            case .number: return NCColors.yellow
            case .comment: return NCColors.green
            case .type: return NCColors.accent
            case .function: return Color(red: 0.42, green: 0.76, blue: 1.0)
            case .property: return Color(red: 0.41, green: 0.88, blue: 0.83)
            case .builtin: return NCColors.pink
            case .literal: return NCColors.pink
            case .key: return Color(red: 0.98, green: 0.72, blue: 0.32)
            case .decorator: return NCColors.violet
            case .operator: return NCColors.pink
            case .punctuation: return NCColors.secondary
            }
        }
    }

    let range: NSRange
    let kind: Kind
}

private enum NCSyntaxTokenizer {
    static func tokenize(_ text: String, language: NCLanguage) -> [NCSyntaxToken] {
        guard !text.isEmpty else { return [] }

        var tokens: [NCSyntaxToken] = []
        var index = text.startIndex
        var lineStart = true
        var previousWord: String?
        var previousCharacter: Character?

        while index < text.endIndex {
            let character = text[index]

            if character == "\n" {
                lineStart = true
                previousWord = nil
                previousCharacter = nil
                index = text.index(after: index)
                continue
            }

            if isCommentStart(in: text, at: index, language: language) {
                let start = index
                let isMarkdownHeading = language == .markdown && lineStart && character == "#"
                index = consumeUntilNewline(text, from: index)
                tokens.append(NCSyntaxToken(
                    range: nsRange(from: start, to: index, in: text),
                    kind: isMarkdownHeading ? .markup : .comment
                ))
                lineStart = false
                previousCharacter = "#"
                continue
            }

            if isBlockCommentStart(in: text, at: index) {
                let start = index
                index = consumeDelimited(text, from: index, opening: "/*", closing: "*/")
                tokens.append(NCSyntaxToken(range: nsRange(from: start, to: index, in: text), kind: .comment))
                lineStart = false
                previousCharacter = "/"
                continue
            }

            if let delimiter = stringDelimiter(in: text, at: index, language: language) {
                let start = index
                index = consumeDelimited(text, from: index, opening: delimiter, closing: delimiter)
                let kind: NCSyntaxToken.Kind
                if language == .json && nextSignificantCharacter(in: text, from: index) == ":" {
                    kind = .key
                } else {
                    kind = .string
                }
                tokens.append(NCSyntaxToken(range: nsRange(from: start, to: index, in: text), kind: kind))
                lineStart = false
                previousWord = nil
                previousCharacter = "\""
                continue
            }

            if character == "@" && supportsDecorators(language) {
                let start = index
                index = text.index(after: index)
                while index < text.endIndex && isIdentifierPart(text[index]) {
                    index = text.index(after: index)
                }
                tokens.append(NCSyntaxToken(range: nsRange(from: start, to: index, in: text), kind: .decorator))
                lineStart = false
                previousWord = nil
                previousCharacter = "@"
                continue
            }

            if isNumberStart(in: text, at: index) {
                let start = index
                index = consumeNumber(text, from: index)
                tokens.append(NCSyntaxToken(range: nsRange(from: start, to: index, in: text), kind: .number))
                lineStart = false
                previousWord = nil
                previousCharacter = "0"
                continue
            }

            if isIdentifierStart(character) {
                let start = index
                index = text.index(after: index)
                while index < text.endIndex && isIdentifierPart(text[index]) {
                    index = text.index(after: index)
                }

                let word = String(text[start..<index])
                let nextCharacter = nextSignificantCharacter(in: text, from: index)
                let kind = classify(
                    word: word,
                    language: language,
                    previousWord: previousWord,
                    previousCharacter: previousCharacter,
                    nextCharacter: nextCharacter
                )
                tokens.append(NCSyntaxToken(range: nsRange(from: start, to: index, in: text), kind: kind))
                previousWord = word
                previousCharacter = word.last
                lineStart = false
                continue
            }

            if isOperator(character) {
                let start = index
                index = text.index(after: index)
                while index < text.endIndex && isOperator(text[index]) {
                    index = text.index(after: index)
                }
                tokens.append(NCSyntaxToken(range: nsRange(from: start, to: index, in: text), kind: .operator))
                lineStart = false
                previousCharacter = character
                continue
            }

            if isPunctuation(character) {
                let start = index
                index = text.index(after: index)
                tokens.append(NCSyntaxToken(range: nsRange(from: start, to: index, in: text), kind: .punctuation))
                lineStart = false
                previousCharacter = character
                continue
            }

            lineStart = false
            previousCharacter = character
            index = text.index(after: index)
        }

        return tokens
    }

    private static func classify(
        word: String,
        language: NCLanguage,
        previousWord: String?,
        previousCharacter: Character?,
        nextCharacter: Character?
    ) -> NCSyntaxToken.Kind {
        let literals: Set<String> = [
            "true", "false", "null", "nil", "None", "True", "False", "undefined", "NaN", "inf"
        ]
        if literals.contains(word) { return .literal }
        if language.keywords.contains(word) { return .keyword }
        if builtins(for: language).contains(word) { return .builtin }
        if previousWord == "def" || previousWord == "func" || previousWord == "function" {
            return .function
        }
        if previousWord == "class" || previousWord == "struct" || previousWord == "enum" || previousWord == "protocol" || previousWord == "interface" {
            return .type
        }
        if word.first?.isUppercase == true { return .type }
        if previousCharacter == "." { return .property }
        if language == .json && nextCharacter == ":" { return .key }
        if nextCharacter == "(" { return .function }
        return .plain
    }

    private static func builtins(for language: NCLanguage) -> Set<String> {
        switch language {
        case .python:
            return ["print", "len", "range", "str", "int", "float", "list", "dict", "set", "tuple", "open", "super", "isinstance", "enumerate", "zip", "map", "filter", "sorted", "sum", "min", "max", "abs", "Exception", "ValueError", "RuntimeError"]
        case .swift:
            return ["print", "fatalError", "precondition", "assert", "dump", "String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Date", "URL"]
        case .javascript, .typescript:
            return ["console", "log", "Math", "JSON", "Promise", "Array", "Object", "String", "Number", "Boolean", "setTimeout", "setInterval"]
        case .shell:
            return ["echo", "printf", "read", "cd", "pwd", "export", "source"]
        case .auto, .json, .markdown, .yaml, .plaintext:
            return []
        }
    }

    private static func isCommentStart(in text: String, at index: String.Index, language: NCLanguage) -> Bool {
        let rest = text[index...]
        if rest.hasPrefix("//") { return language == .swift || language == .javascript || language == .typescript }
        if rest.hasPrefix("#") { return language == .python || language == .shell || language == .yaml || language == .markdown }
        if rest.hasPrefix("<!--") { return language == .markdown }
        return false
    }

    private static func isBlockCommentStart(in text: String, at index: String.Index) -> Bool {
        text[index...].hasPrefix("/*")
    }

    private static func stringDelimiter(in text: String, at index: String.Index, language: NCLanguage) -> String? {
        let rest = text[index...]
        if language == .python && (rest.hasPrefix("\"\"\"") || rest.hasPrefix("'''")) {
            return String(rest.prefix(3))
        }
        if text[index] == "\"" || text[index] == "'" || (text[index] == "`" && (language == .javascript || language == .typescript || language == .shell)) {
            return String(text[index])
        }
        return nil
    }

    private static func consumeDelimited(_ text: String, from start: String.Index, opening: String, closing: String) -> String.Index {
        var index = text.index(start, offsetBy: opening.count, limitedBy: text.endIndex) ?? text.endIndex
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            if opening.count == 1 && escaped {
                escaped = false
                index = text.index(after: index)
                continue
            }
            if opening.count == 1 && character == "\\" {
                escaped = true
                index = text.index(after: index)
                continue
            }
            if text[index...].hasPrefix(closing) {
                return text.index(index, offsetBy: closing.count, limitedBy: text.endIndex) ?? text.endIndex
            }
            index = text.index(after: index)
        }
        return text.endIndex
    }

    private static func consumeUntilNewline(_ text: String, from start: String.Index) -> String.Index {
        var index = start
        while index < text.endIndex, text[index] != "\n" {
            index = text.index(after: index)
        }
        return index
    }

    private static func consumeNumber(_ text: String, from start: String.Index) -> String.Index {
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if isIdentifierPart(character) || character == "." {
                index = text.index(after: index)
            } else {
                break
            }
        }
        return index
    }

    private static func isNumberStart(in text: String, at index: String.Index) -> Bool {
        if isDecimal(text[index]) { return true }
        guard text[index] == "." else { return false }
        let next = text.index(after: index)
        return next < text.endIndex && isDecimal(text[next])
    }

    private static func nextSignificantCharacter(in text: String, from start: String.Index) -> Character? {
        var index = start
        while index < text.endIndex, isWhitespace(text[index]) {
            index = text.index(after: index)
        }
        return index < text.endIndex ? text[index] : nil
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
    }

    private static func isIdentifierPart(_ character: Character) -> Bool {
        isIdentifierStart(character) || isDecimal(character)
    }

    private static func isDecimal(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func isOperator(_ character: Character) -> Bool {
        "=+-*/%<>!&|^~?:".contains(character)
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        "{}[](),.;".contains(character)
    }

    private static func supportsDecorators(_ language: NCLanguage) -> Bool {
        language == .python || language == .swift || language == .javascript || language == .typescript
    }

    private static func nsRange(from start: String.Index, to end: String.Index, in text: String) -> NSRange {
        NSRange(start..<end, in: text)
    }
}

private enum NCSyntaxHighlighter {
    static func attributedText(
        _ text: String,
        language: NCLanguage,
        diagnostics: [NCDiagnostic]
    ) -> NSAttributedString {
        let font = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.label
            ]
        )

        for token in NCSyntaxTokenizer.tokenize(text, language: language) {
            result.addAttribute(.foregroundColor, value: token.kind.uiColor, range: token.range)
        }

        for diagnostic in diagnostics {
            guard let range = range(for: diagnostic, in: text) else { continue }
            result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            result.addAttribute(.underlineColor, value: diagnostic.severity == .error ? NCSyntaxPalette.diagnostic : NCSyntaxPalette.number, range: range)
        }

        return result
    }

    private static func range(for diagnostic: NCDiagnostic, in text: String) -> NSRange? {
        let lines = text.components(separatedBy: "\n")
        guard diagnostic.line > 0, diagnostic.line <= lines.count else { return nil }

        var location = 0
        for line in lines.prefix(diagnostic.line - 1) {
            location += (line as NSString).length + 1
        }

        let target = lines[diagnostic.line - 1] as NSString
        guard target.length > 0 else { return nil }
        let column = min(max(diagnostic.column - 1, 0), target.length - 1)
        return NSRange(location: location + column, length: 1)
    }
}

struct NCNativeCodeTextView: UIViewRepresentable {
    @Binding var text: String
    let language: NCLanguage
    let diagnostics: [NCDiagnostic]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.tintColor = UIColor(red: 0.25, green: 0.82, blue: 0.88, alpha: 1)
        textView.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 14, bottom: 16, right: 14)
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.keyboardDismissMode = .interactive
        textView.attributedText = NCSyntaxHighlighter.attributedText(text, language: language, diagnostics: diagnostics)
        context.coordinator.lastRenderedText = text
        context.coordinator.lastLanguage = language
        context.coordinator.lastDiagnostics = diagnostics
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.lastRenderedText != text
                || context.coordinator.lastLanguage != language
                || context.coordinator.lastDiagnostics != diagnostics else { return }

        let selectedRange = textView.selectedRange
        context.coordinator.isApplying = true
        textView.attributedText = NCSyntaxHighlighter.attributedText(text, language: language, diagnostics: diagnostics)
        textView.selectedRange = NSRange(
            location: min(selectedRange.location, (text as NSString).length),
            length: 0
        )
        context.coordinator.isApplying = false
        context.coordinator.lastRenderedText = text
        context.coordinator.lastLanguage = language
        context.coordinator.lastDiagnostics = diagnostics
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NCNativeCodeTextView
        var isApplying = false
        var lastRenderedText = ""
        var lastLanguage: NCLanguage = .auto
        var lastDiagnostics: [NCDiagnostic] = []

        init(_ parent: NCNativeCodeTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplying else { return }
            parent.text = textView.text
        }
    }
}
