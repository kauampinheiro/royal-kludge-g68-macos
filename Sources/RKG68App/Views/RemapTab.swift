//
//  RemapTab.swift
//  Clica na tecla do desenho, escolhe a função, grava no firmware.
//

import SwiftUI
import RKCore

struct RemapTab: View {
    @Bindable var controller: KeyboardController
    let config: KeyboardConfig
    let imageURL: URL?

    @State private var search = ""

    private var selectedKey: KeyboardKey? {
        controller.selectedKeyIndex.flatMap { config.key(bufferIndex: $0) }
    }

    var body: some View {
        VStack(spacing: 16) {
            KeyboardMapView(
                config: config,
                imageURL: imageURL,
                remaps: controller.profile.remaps,
                keyColors: [:],
                showKeyColors: false,
                selection: $controller.selectedKeyIndex
            )
            .padding(.horizontal, 4)

            Divider()

            if let key = selectedKey {
                editor(for: key)
            } else {
                ContentUnavailableView {
                    Label("Escolha uma tecla", systemImage: "keyboard")
                } description: {
                    Text("Clique em uma tecla do desenho acima para trocar a função dela.")
                }
                .frame(maxHeight: 180)
            }
        }
    }

    @ViewBuilder
    private func editor(for key: KeyboardKey) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.keyInfo.displayLabel)
                        .font(.title3.weight(.semibold))
                    Text(currentAssignment(for: key))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if controller.profile.remaps[key.bufferIndex] != nil {
                    Button("Voltar ao original") {
                        controller.remap(keyIndex: key.bufferIndex, to: nil)
                    }
                }
            }

            TextField("Buscar função (ex.: esc, ⌘, volume, F5)", text: $search)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(filteredCategories(), id: \.0) { category, keys in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(category.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            FlowLayout(spacing: 6) {
                                ForEach(keys, id: \.vk) { target in
                                    targetChip(target, for: key)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 150)
        }
    }

    private func targetChip(_ target: KeyInfo, for key: KeyboardKey) -> some View {
        let isCurrent = controller.profile.remaps[key.bufferIndex] == target.vk
            || (controller.profile.remaps[key.bufferIndex] == nil && key.keyInfo.vk == target.vk)
        return Button {
            // Atribuir a função original equivale a limpar o remap.
            controller.remap(keyIndex: key.bufferIndex,
                             to: target.vk == key.keyInfo.vk ? nil : target.vk)
        } label: {
            Text(target.displayLabel)
                .font(.system(size: 11))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isCurrent ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
                            in: Capsule())
                .foregroundStyle(isCurrent ? .white : .primary)
                .overlay(Capsule().strokeBorder(.separator, lineWidth: isCurrent ? 0 : 0.5))
        }
        .buttonStyle(.plain)
    }

    private func currentAssignment(for key: KeyboardKey) -> String {
        if let vk = controller.profile.remaps[key.bufferIndex], let info = Keycode.info(vk: vk) {
            return "agora envia \(info.displayLabel)  ·  índice #\(key.bufferIndex)"
        }
        return "função de fábrica  ·  índice #\(key.bufferIndex)"
    }

    private func filteredCategories() -> [(KeyCategory, [KeyInfo])] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return Keycode.assignableKeys() }

        // Os apelidos do CLI também valem na busca: quem digita "volup"
        // encontra a tecla de volume.
        let aliasVKs = Set(KeyNames.aliases.filter { $0.key.contains(needle) }.map(\.value))

        return Keycode.assignableKeys().compactMap { category, keys in
            let hits = keys.filter {
                $0.displayLabel.lowercased().contains(needle)
                    || $0.label.lowercased().contains(needle)
                    || aliasVKs.contains($0.vk)
            }
            return hits.isEmpty ? nil : (category, hits)
        }
    }
}

/// Layout em linhas que quebram sozinhas — usado para a nuvem de funções.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 480
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
