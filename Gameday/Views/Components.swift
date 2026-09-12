import AppKit
import SwiftUI

struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
    }
}

/// Rounded hover highlight, the way rows and buttons respond in a document-style UI.
struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = Theme.cornerRadius
    var enabled = true
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovering && enabled ? Theme.hover : Color.clear)
            )
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = Theme.cornerRadius, enabled: Bool = true) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, enabled: enabled))
    }
}

/// Square icon button used in the header bars.
struct IconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 26
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 5)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Small text button ("Today", "Choose leagues").
struct TextButton: View {
    let title: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Fonts.captionMedium)
                .foregroundStyle(prominent ? Theme.accent : Theme.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 5)
    }
}

/// Outlined button for empty states.
struct OutlinedButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Fonts.captionMedium)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Theme.divider, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 5)
    }
}

struct Checkbox: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(isOn ? Theme.accent : Color.clear)
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .stroke(isOn ? Theme.accent : Theme.textTertiary, lineWidth: 1.25)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 15, height: 15)
    }
}

/// Soft spectrum used to mark top matches. Muted enough to sit next to grey type.
enum Spectrum {
    static let colors: [Color] = [
        Color(hex: 0xE8797A),
        Color(hex: 0xF0B26B),
        Color(hex: 0xE3D16A),
        Color(hex: 0x7FD4A8),
        Color(hex: 0x6FB6F0),
        Color(hex: 0xB48BEB),
        Color(hex: 0xE8797A),
    ]

    static var linear: LinearGradient {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    static var angular: AngularGradient {
        AngularGradient(colors: colors, center: .center, angle: .zero)
    }
}

/// One-point border whose spectrum slowly rotates. Pauses when the popover is hidden or the
/// user prefers reduced motion.
struct SpectrumBorder: View {
    var cornerRadius: CGFloat = Theme.cornerRadius
    var lineWidth: CGFloat = 1
    var animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated || reduceMotion)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let turn = (seconds / 8).truncatingRemainder(dividingBy: 1)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    AngularGradient(colors: Spectrum.colors, center: .center, angle: .degrees(turn * 360)),
                    lineWidth: lineWidth
                )
        }
    }
}

/// Plain search field: icon, text, clear button, no border.
struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textPrimary)
                .focused($isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .onAppear { isFocused = true }
    }
}

struct LiveDot: View {
    var body: some View {
        Circle()
            .fill(Theme.live)
            .frame(width: 6, height: 6)
    }
}

/// Team logo or country flag, loaded through the shared image store.
struct RemoteImage: View {
    let url: URL?
    let size: CGSize
    let cornerRadius: CGFloat
    let fallbackSymbol: String?
    @State private var image: NSImage?

    init(url: URL?, size: CGSize, cornerRadius: CGFloat = 0, fallbackSymbol: String? = nil) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius
        self.fallbackSymbol = fallbackSymbol
        _image = State(initialValue: url.flatMap { ImageStore.shared.cachedImage(for: $0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: cornerRadius > 0 ? .fill : .fit)
            } else if let fallbackSymbol {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size.height * 0.7, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                RoundedRectangle(cornerRadius: max(cornerRadius, 3), style: .continuous)
                    .fill(Theme.placeholder)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            guard let url else { image = nil; return }
            if let cached = ImageStore.shared.cachedImage(for: url) { image = cached; return }
            image = nil
            let loaded = await ImageStore.shared.image(for: url)
            if !Task.isCancelled { image = loaded }
        }
    }
}

/// A scroll view that is only as tall as its content, up to a maximum.
struct SelfSizingScrollView<Content: View>: View {
    let minHeight: CGFloat
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0
    @Environment(\.isSnapshotMode) private var isSnapshotMode

    var body: some View {
        if isSnapshotMode {
            content().frame(width: Theme.width, alignment: .top)
        } else {
            ScrollView(.vertical) {
                content()
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                        }
                    )
            }
            .scrollIndicators(.automatic)
            .onPreferenceChange(ContentHeightKey.self) { height in
                DispatchQueue.main.async { contentHeight = height }
            }
            .frame(height: max(minHeight, min(contentHeight, maxHeight)))
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Paints the popover chrome (including the arrow) in the app background colour so the
/// popover reads as one flat surface instead of a translucent system material.
struct PopoverChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ nsView: ChromeView, context: Context) {}

    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyBackground()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            applyBackground()
        }

        private func applyBackground() {
            guard let frameView = window?.contentView?.superview else { return }
            frameView.wantsLayer = true
            let color = NSColor.adaptive(light: .white, dark: NSColor(hex: 0x1E1E1E))
            effectiveAppearance.performAsCurrentDrawingAppearance {
                frameView.layer?.backgroundColor = color.cgColor
            }
        }
    }
}
