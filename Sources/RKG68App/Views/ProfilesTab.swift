//
//  ProfilesTab.swift
//  O teclado não devolve o que está gravado nele, então o perfil em disco é
//  a única memória do que foi aplicado.
//

import SwiftUI
import RKCore

struct ProfilesTab: View {
    @Bindable var controller: KeyboardController
    let config: KeyboardConfig

    @State private var newName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                current
                Divider()
                saved
                Divider()
                explanation
            }
            .padding(.vertical, 4)
        }
    }

    private var current: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Perfil em uso")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Text(controller.profile.name).font(.title3.weight(.semibold))
                Spacer()
                Button("Regravar no teclado") { controller.applyCurrentProfile() }
                    .disabled(!controller.isConnected)
            }
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)

            if !controller.profile.remaps.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(controller.profile.remaps.sorted(by: { $0.key < $1.key }), id: \.key) { index, vk in
                        let from = config.key(bufferIndex: index)?.keyInfo.displayLabel ?? "#\(index)"
                        let to = Keycode.info(vk: vk)?.displayLabel ?? "VK 0x\(String(vk, radix: 16))"
                        Text("\(from)  →  \(to)").font(.caption.monospaced())
                    }
                }
                Button("Remover todos os remaps") { controller.clearAllRemaps() }
                    .disabled(!controller.isConnected)
            }

            HStack {
                TextField("Salvar como…", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Button("Salvar") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    controller.saveProfile(as: name)
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var saved: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Perfis salvos")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if controller.profileNames.isEmpty {
                Text("Nenhum perfil salvo ainda.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.profileNames, id: \.self) { name in
                    HStack {
                        Image(systemName: name == controller.profile.name ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(.tertiary)
                        Text(name)
                        Spacer()
                        Button("Aplicar") { controller.loadProfile(name) }
                            .disabled(!controller.isConnected)
                        Button(role: .destructive) { controller.deleteProfile(name) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Como isso funciona")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("""
            Remaps e iluminação ficam gravados no próprio teclado: valem em \
            qualquer computador, mesmo sem este app aberto e mesmo via Bluetooth \
            ou 2.4G. O que exige o cabo USB é apenas o momento de gravar.

            O firmware não devolve o que está gravado nele, então estes perfis \
            são o registro do que foi enviado — se você gravar pelo app oficial \
            no Windows, o perfil daqui não acompanha.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summary: String {
        var parts: [String] = []
        parts.append("\(controller.profile.remaps.count) remap(s)")
        if let light = controller.profile.lighting {
            let name = config.lightingModes.first { $0.index == light.modeIndex }?.name ?? "modo \(light.modeIndex)"
            parts.append("luz: \(name)")
        }
        if !controller.profile.perKeyColors.isEmpty {
            parts.append("\(controller.profile.perKeyColors.count) cor(es) por tecla")
        }
        return parts.joined(separator: "  ·  ")
    }
}
