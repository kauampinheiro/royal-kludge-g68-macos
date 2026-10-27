//
//  AppBehavior.swift
//  Como o app se comporta fora da janela: Dock, segundo plano e login.
//
//  Isto deixou de ser detalhe de conforto quando as macros entraram: macro por
//  software só funciona com o app vivo. Um configurador que você abre, usa e
//  fecha pode sumir sem prejuízo; um que segura as macros, não.
//

import AppKit
import ServiceManagement
import SwiftUI

/// Preferências de comportamento, em `UserDefaults`.
///
/// Não entram no perfil nem na calibração de propósito: não são do teclado,
/// são de como *este* Mac usa o app.
@MainActor
enum AppPreferences {
    private static let dockKey = "hideDockIcon"
    private static let backgroundKey = "startInBackground"

    /// Sem ícone no Dock — o app vive só na barra de menus.
    static var hideDockIcon: Bool {
        get { UserDefaults.standard.bool(forKey: dockKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: dockKey)
            applyActivationPolicy()
        }
    }

    /// Abre sem janela. Combinado com "abrir no login", o app sobe junto com o
    /// sistema e fica disponível sem aparecer na frente de ninguém.
    static var startInBackground: Bool {
        get { UserDefaults.standard.bool(forKey: backgroundKey) }
        set { UserDefaults.standard.set(newValue, forKey: backgroundKey) }
    }

    /// `.accessory` tira o ícone do Dock e o menu do app; `.regular` devolve.
    /// A troca vale em tempo de execução, sem reiniciar.
    static func applyActivationPolicy() {
        NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)
    }
}

/// Abrir no login via `SMAppService`. Precisa do app assinado e num lugar
/// estável; com assinatura ad-hoc o macOS pode recusar, e o erro é mostrado em
/// vez de silenciado.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// O macOS diz "requer aprovação" quando o item foi registrado mas o
    /// usuário ainda não confirmou em Ajustes › Itens de Início.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func set(_ enabled: Bool, report: (String, Bool) -> Void) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                report(needsApproval
                       ? "Registrado — falta aprovar em Ajustes do Sistema › Geral › Itens de Início"
                       : "O app abrirá junto com o login", needsApproval)
            } else {
                try SMAppService.mainApp.unregister()
                report("O app não abrirá mais no login", false)
            }
        } catch {
            report("Não foi possível alterar a abertura no login: \(error.localizedDescription)", true)
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// O delegate existe por três comportamentos que a cena do SwiftUI não cobre.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppPreferences.applyActivationPolicy()

            // Fechar a janela já montada é o jeito de "não abrir" numa cena
            // `Window` do SwiftUI em macOS 14 — `defaultLaunchBehavior` só
            // existe do 15 em diante.
            if AppPreferences.startInBackground {
                DispatchQueue.main.async {
                    NSApp.windows.forEach { $0.close() }
                }
            }
        }
    }

    /// Sem isto o app morreria ao fechar a janela — e com ele morreriam as
    /// macros, que dependem do processo vivo.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicar no ícone do Dock com nenhuma janela aberta tem de trazer a
    /// janela de volta, senão o app fica inalcançável por ali.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            MainActor.assumeIsolated { WindowOpener.open() }
        }
        return true
    }
}

/// Abrir a janela de fora da hierarquia do SwiftUI.
///
/// Em `.accessory` o app não é ativado sozinho, então a janela subiria atrás
/// de quem estiver na frente: ativar explicitamente é obrigatório.
@MainActor
enum WindowOpener {
    static var action: (() -> Void)?

    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        action?()
    }
}
