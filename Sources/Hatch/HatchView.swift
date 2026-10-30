import SwiftUI

struct HatchView: View {
    @ObservedObject var model: HatchModel
    @FocusState private var focused: Bool

    var body: some View {
        let t = model.theme
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundColor(t.dim)
                TextField(model.scope.map { "Search \($0.title.lowercased())…" } ?? "Search apps, calculate, run scripts… (: for types)",
                          text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .foregroundColor(t.fg)
                    .focused($focused)
                if let scope = model.scope {
                    HStack(spacing: 5) {
                        Image(systemName: scope.symbol).font(.system(size: 12))
                        Text(scope.title).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(t.tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: t.rowRadius).fill(t.tint.opacity(0.18)))
                }
            }
            .padding(.horizontal, 18)
            .frame(height: Layout.inputHeight)

            if !model.results.isEmpty {
                Rectangle().fill(t.dim.opacity(0.2)).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                                ResultRow(item: item, selected: index == model.selection, theme: t, monochrome: model.monochromeIcons)
                                    .id(item.id)
                                    .onTapGesture {
                                        model.selection = index
                                        model.activate()
                                    }
                            }
                        }
                        .padding(.vertical, Layout.listInset)
                    }
                    .onChange(of: model.selection) { _, new in
                        guard model.results.indices.contains(new) else { return }
                        proxy.scrollTo(model.results[new].id)
                    }
                }
            }
        }
        .frame(width: Layout.width, height: Layout.height(forRows: model.results.count), alignment: .top)
        .background(t.bg.opacity(model.opacity))
        .clipShape(RoundedRectangle(cornerRadius: t.radius))
        .overlay(RoundedRectangle(cornerRadius: t.radius).stroke(t.dim.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .animation(.easeOut(duration: 0.12), value: model.results.count)
        // The window is a fixed size; only this card grows and shrinks.
        .padding(Layout.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
        .onChange(of: model.focusTick) { _, _ in focused = true }
    }
}

private struct ResultRow: View {
    let item: ResultItem
    let selected: Bool
    let theme: Theme
    let monochrome: Bool

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 30, height: 30)
            if item.emphasized {
                Text(item.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(theme.tint)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(theme.dim)
                    .lineLimit(1)
            } else {
                Text(item.title)
                    .font(.system(size: 15))
                    .foregroundColor(theme.fg)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(theme.dim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(item.kind)
                .font(.system(size: 12))
                .foregroundColor(theme.dim)
        }
        .padding(.horizontal, 12)
        .frame(height: Layout.rowHeight)
        .background(RoundedRectangle(cornerRadius: theme.rowRadius).fill(selected ? theme.sel : .clear))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var icon: some View {
        if let path = item.iconPath {
            let image = Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
            if monochrome {
                // Grayscale keeps the icon's detail; multiplying by the accent turns white into the theme color.
                image.saturation(0).colorMultiply(theme.tint)
            } else {
                image
            }
        } else if let symbol = item.symbol {
            Image(systemName: symbol).font(.system(size: 18)).foregroundColor(theme.tint)
        }
    }
}
