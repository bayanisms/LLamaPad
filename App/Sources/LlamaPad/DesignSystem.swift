import SwiftUI
import UIKit

enum LlamaStyle {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.53, blue: 0.36, alpha: 1)
            : UIColor(red: 0.76, green: 0.27, blue: 0.15, alpha: 1)
    })
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let quiet = Color(uiColor: .tertiarySystemGroupedBackground)
    static let onAccent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .black : .white })
    static func memory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
    static func thermal(_ value: Int) -> String {
        [0: "Nominal", 1: "Warm", 2: "Hot", 3: "Critical"][value] ?? "Unknown"
    }
}

struct BrandMark: View {
    var size: CGFloat = 48
    private static let image: UIImage? = Bundle.module.url(forResource: "BrandMark", withExtension: "png")
        .flatMap { UIImage(contentsOfFile: $0.path) }
    var body: some View {
        Image(uiImage: Self.image ?? UIImage(systemName: "ipad") ?? UIImage()).resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct Surface<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(LlamaStyle.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct PageLayout<Content: View>: View {
    var subtitle: String
    let content: Content
    init(_ subtitle: String, @ViewBuilder content: () -> Content) { self.subtitle = subtitle; self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                content
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }.background(LlamaStyle.background)
    }
}

struct SectionHeading: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}

struct StatusBadge: View {
    let title: String
    let state: String
    private var color: Color {
        switch state {
        case "running": .green
        case "starting", "stopping": .orange
        case "failed": .red
        default: .secondary
        }
    }
    var body: some View {
        Label { Text(title).font(.subheadline.weight(.semibold)) } icon: {
            Image(systemName: state == "failed" ? "exclamationmark.circle.fill" : "circle.fill")
                .font(.system(size: state == "failed" ? 13 : 7))
        }
        .foregroundStyle(color).padding(.horizontal, 12).padding(.vertical, 8)
        .background(color.opacity(0.10), in: Capsule())
        .accessibilityLabel("Service status: \(title)")
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    var detail: String? = nil
    var color: Color = .primary
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
                Text(value).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit().foregroundStyle(color)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }.accessibilityElement(children: .combine)
    }
}

struct CopyButton: View {
    let value: String
    var label = "Copy"
    var accessibilityName: String? = nil
    @State private var copied = false
    var body: some View {
        Button { UIPasteboard.general.string = value; copied = true } label: {
            Label(copied ? "Copied" : label, systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.bordered).controlSize(.small)
        .accessibilityLabel(copied ? "Copied to clipboard" : accessibilityName ?? label)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = false
        }.sensoryFeedback(.success, trigger: copied)
    }
}

struct CommandBlock: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                CopyButton(value: value, accessibilityName: "Copy \(title)")
            }
            Text(value).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(LlamaStyle.quiet, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct InfoNote: View {
    let text: String
    var symbol = "info.circle"
    var color: Color = .secondary
    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol) }
            .font(.footnote).foregroundStyle(color)
    }
}
