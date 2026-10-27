//
//  RKG68App.swift
//  Configurador do Royal Kludge G68 para macOS.
//

import SwiftUI
import ServiceManagement
import RKCore

@main
struct RKG68App: App {
    @State private var controller = KeyboardController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("RK G68", id: "main") {
            ContentView(controller: controller)
                .onAppear { WindowOpener.action = { openMainWindow() } }
        }
        .defaultSize(width: 880, height: 700)
        .commands {
            CommandGroup(replacing: .help) {
                Link("Protocolo e limitações conhecidas",
                     destination: URL(string: "https://github.com/rnayabed/rangoli")!)
            }
        }

        MenuBarExtra("RK G68", systemImage: "keyboard") {
            MenuBarContent(controller: controller)
        }
    }

    @Environment(\.openWindow) private var openWindow

    private func openMainWindow() {
        openWindow(id: "main")
    }
}

struct MenuBarContent: View {
    @Bindable var controller: KeyboardController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(controller.connectionLabel)
        Divider()

        if !controller.profileNames.isEmpty {
            Menu("Aplicar perfil") {
                ForEach(controller.profileNames, id: \.self) { name in
                    Button(name) { controller.loadProfile(name) }
                        .disabled(!controller.isConnected)
                }
            }
        }

        Button("Regravar perfil atual") { controller.applyCurrentProfile() }
            .disabled(!controller.isConnected)

        Divider()
        Button("Abrir janela…") { WindowOpener.open() }

        Toggle("Abrir no login", isOn: $controller.loginItemEnabled)
        Toggle("Abrir sem janela", isOn: $controller.startInBackground)
        Toggle("Esconder ícone do Dock", isOn: $controller.hideDockIcon)
        if controller.loginItemNeedsApproval {
            Button("Aprovar em Ajustes do Sistema…") { LoginItem.openLoginItemsSettings() }
        }

        Divider()
        Button("Encerrar") { NSApplication.shared.terminate(nil) }
    }
}
