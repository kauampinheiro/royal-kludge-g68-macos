//
//  ContentView.swift
//

import SwiftUI
import RKCore

struct ContentView: View {
    @Bindable var controller: KeyboardController

    private var imageURL: URL? {
        guard let config = controller.config,
              let resources = try? RKResources.bundled() else { return nil }
        return resources.image(for: config)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let config = controller.config {
                TabView {
                    RemapTab(controller: controller, config: config, imageURL: imageURL)
                        .padding(16)
                        .tabItem { Label("Teclas", systemImage: "keyboard") }

                    LightingTab(controller: controller, config: config, imageURL: imageURL)
                        .padding(16)
                        .tabItem { Label("Iluminação", systemImage: "lightbulb") }

                    MacrosTab(controller: controller)
                        .padding(16)
                        .tabItem { Label("Macros", systemImage: "wand.and.rays") }

                    ProfilesTab(controller: controller, config: config)
                        .padding(16)
                        .tabItem { Label("Perfis", systemImage: "square.stack.3d.up") }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
            } else if !controller.started {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Carregando as definições do teclado…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Definições da RK não encontradas",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("O app não achou os arquivos de layout embutidos."))
            }

            Divider()
            footer
        }
        .frame(minWidth: 820, minHeight: 640)
        .task {
            // Carrega fora do init do controller, para a janela aparecer
            // mesmo que a leitura de disco demore ou peça autorização.
            await controller.start()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(controller.isConnected ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.connectionLabel)
                    .font(.headline)
                if controller.needsInputMonitoring {
                    Text("Falta autorizar o app em Ajustes do Sistema › Privacidade e Segurança › Monitoramento de Entrada.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !controller.isConnected {
                    Text("Conecte pelo cabo USB para gravar — 2.4G e Bluetooth não expõem o canal de configuração.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let info = controller.connection.keyboard?.info {
                    Text("PID 0x\(info.pidString.uppercased())  ·  \(info.product ?? "sem nome")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if controller.needsInputMonitoring {
                Button {
                    controller.requestInputMonitoring()
                } label: {
                    Label("Autorizar…", systemImage: "lock.open")
                }
                .buttonStyle(.borderedProminent)
                .help("O macOS exige Monitoramento de Entrada para o app conseguir "
                      + "falar com o teclado.")
            }
            Button {
                controller.refresh()
            } label: {
                Label("Procurar", systemImage: "arrow.clockwise")
            }

            behaviorMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// As mesmas opções do menu da barra, alcançáveis de dentro da janela —
    /// ajuste que se quer conferir não deve morar só num menu que fecha ao
    /// clicar.
    private var behaviorMenu: some View {
        Menu {
            Toggle("Abrir no login", isOn: $controller.loginItemEnabled)
            Toggle("Abrir sem janela", isOn: $controller.startInBackground)
            Toggle("Esconder ícone do Dock", isOn: $controller.hideDockIcon)
            if controller.loginItemNeedsApproval {
                Divider()
                Button("Aprovar em Ajustes do Sistema…") { LoginItem.openLoginItemsSettings() }
            }
            Divider()
            Text("Fechar a janela não encerra o app — ele fica na barra de menus, que é o que mantém as macros funcionando.")
        } label: {
            Label("Comportamento", systemImage: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if !controller.status.isEmpty {
                Image(systemName: controller.statusIsError
                      ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(controller.statusIsError ? .orange : .green)
                Text(controller.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 34)
    }
}
