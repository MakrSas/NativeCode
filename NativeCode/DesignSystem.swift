import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum NCColors {
    static let canvas = Color(uiColor: .systemBackground)
    static let grouped = Color(uiColor: .secondarySystemBackground)
    static let elevated = Color(uiColor: .tertiarySystemBackground)
    static let separator = Color(uiColor: .separator)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let tertiary = Color(uiColor: .tertiaryLabel)
    static let text = Color.primary

    static let accent = Color(red: 0.25, green: 0.82, blue: 0.88)
    static let accentDim = Color(red: 0.13, green: 0.48, blue: 0.56)
    static let violet = Color(red: 0.61, green: 0.49, blue: 0.95)
    static let pink = Color(red: 0.94, green: 0.48, blue: 0.71)
    static let green = Color(red: 0.32, green: 0.82, blue: 0.52)
    static let yellow = Color(red: 0.96, green: 0.72, blue: 0.28)
    static let orange = Color(red: 0.98, green: 0.55, blue: 0.25)
    static let red = Color(red: 0.96, green: 0.30, blue: 0.36)
}

enum NCFont {
    static let code = Font.system(.body, design: .monospaced)
    static let codeSmall = Font.system(.footnote, design: .monospaced)
    static let metadata = Font.system(.caption, design: .monospaced)
}

struct NCNativeGlass<Content: View>: View {
    let cornerRadius: CGFloat
    private let content: () -> Content

    init(cornerRadius: CGFloat = 24, @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                content()
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                content()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
    }
}

struct NCFileIcon: View {
    let kind: NCFileKind
    var isExpanded = false

    var body: some View {
        Image(systemName: kind == .folder && isExpanded ? "folder.fill" : kind.symbolName)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(kind.color)
            .frame(width: 22, alignment: .center)
    }
}

struct NCStatusBadge: View {
    let title: String
    let color: Color
    let symbolName: String

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
    }
}

struct NCToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.7) }
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }
}

enum NCHaptics {
    static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func light() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

extension View {
    @ViewBuilder
    func ncListRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    func sidebarRow(selected: Bool = false, tint: Color? = nil) -> some View {
        let fill = tint ?? (selected ? NCColors.accent.opacity(0.15) : Color.white.opacity(0.045))

        self
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        Color.white.opacity(selected ? 0.13 : 0.06),
                        lineWidth: 0.7
                    )
            }
    }
}
