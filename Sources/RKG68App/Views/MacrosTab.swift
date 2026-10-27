//
//  MacrosTab.swift
//  Macros por software: gatilho, sequência e o aviso honesto do que elas são.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RKCore

struct MacrosTab: View {
    @Bindable var controller: KeyboardController
    @State private var editing: Macro?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                explanation
                if !controller.accessibilityGranted { permissionBanner }
                list
            }
            .padding(.vertical, 4)
        }
        .sheet(item: $editing) { macro in
            MacroEditor(macro: macro) { saved in
                controller.saveMacro(saved)
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Macros")
                    .font(.title3.weight(.semibold))
                Spacer()
                statusPill
                Button {
                    editing = Macro(name: "Nova macro", triggerKeyCode: 0,
                                    triggerLabel: "—", steps: [])
                } label: {
                    Label("Nova macro", systemImage: "plus")
                }
            }
            Text("Estas macros **não ficam no teclado**. O protocolo de macro da RK nunca foi decifrado por ninguém, então elas funcionam por software: o app escuta a tecla de gatilho e digita a sequência.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Na prática isso quer dizer duas coisas: só valem neste Mac e com o app aberto (ao contrário do remap, que fica gravado no firmware e viaja com o teclado), e exigem autorização de Acessibilidade.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusPill: some View {
        let active = controller.macrosActive
        return HStack(spacing: 5) {
            Circle()
                .fill(active ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(active ? "escutando" : "parado")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Falta a autorização de Acessibilidade")
                    .font(.callout.weight(.semibold))
                Text("Sem ela o macOS não deixa o app ver as teclas que você digita, e nenhuma macro dispara. É uma autorização diferente do Monitoramento de Entrada que o acesso ao teclado já usa.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Pedir autorização") { controller.requestAccessibility() }
                    Button("Abrir Ajustes do Sistema") { MacroEngine.openAccessibilitySettings() }
                }
                .padding(.top, 2)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var list: some View {
        if controller.macros.isEmpty {
            ContentUnavailableView("Nenhuma macro",
                                   systemImage: "wand.and.rays",
                                   description: Text("Crie uma, escolha a tecla de gatilho pressionando-a e monte a sequência."))
                .frame(height: 220)
        } else {
            VStack(spacing: 0) {
                ForEach(controller.macros) { macro in
                    row(macro)
                    if macro.id != controller.macros.last?.id { Divider() }
                }
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func row(_ macro: Macro) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { macro.enabled },
                set: { controller.setMacroEnabled(macro, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)

            VStack(alignment: .leading, spacing: 2) {
                Text(macro.name)
                    .font(.callout.weight(.medium))
                Text(macro.steps.map(\.summary).joined(separator: " → "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(macro.triggerSummary)
                .font(.callout.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))

            Button("Editar") { editing = macro }
            Button(role: .destructive) {
                controller.deleteMacro(macro)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(macro.enabled ? 1 : 0.5)
    }
}

// MARK: - Editor

struct MacroEditor: View {
    @State private var draft: Macro
    @State private var capturingTrigger = false
    @State private var capturingStep = false
    @State private var textToAdd = ""
    @State private var delayToAdd = 100
    @State private var urlToAdd = ""
    @State private var shellToAdd = ""
    @State private var appPath = ""
    @State private var appName = ""
    @State private var appURL = ""
    @State private var terminalCommand = ""
    @State private var terminalDirectory = ""
    @State private var stepKind: StepKind = .text

    enum StepKind: String, CaseIterable, Identifiable {
        case text = "Texto"
        case keys = "Teclas"
        case url = "URL"
        case app = "Aplicativo"
        case shell = "Shell"
        case terminal = "Terminal"
        case delay = "Espera"
        var id: String { rawValue }
    }

    let onSave: (Macro) -> Void
    let onCancel: () -> Void

    init(macro: Macro, onSave: @escaping (Macro) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: macro)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var triggerIsSet: Bool { draft.triggerLabel != "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.steps.isEmpty ? "Nova macro" : "Editar macro")
                .font(.headline)

            HStack(spacing: 8) {
                Text("Nome").font(.caption).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                TextField("assinatura, e-mail, comando…", text: $draft.name)
            }

            HStack(spacing: 8) {
                Text("Gatilho").font(.caption).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                Button(capturingTrigger ? "Pressione a tecla…" : (triggerIsSet ? draft.triggerSummary : "Gravar gatilho")) {
                    capturingTrigger = true
                }
                .font(.callout.monospaced())
                KeyCaptureField(isCapturing: $capturingTrigger) { code, modifiers, label in
                    draft.triggerKeyCode = code
                    draft.triggerModifiers = modifiers
                    draft.triggerLabel = label
                }
                .frame(width: 1, height: 1)
                Text("a tecla escolhida para de funcionar normalmente enquanto a macro estiver ligada")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            Text("Sequência")
                .font(.callout.weight(.semibold))

            if draft.steps.isEmpty {
                Text("Vazia. Adicione texto, uma combinação de teclas ou uma espera.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(draft.steps.enumerated()), id: \.offset) { index, step in
                        HStack {
                            Text("\(index + 1).")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 20, alignment: .trailing)
                            Text(step.summary)
                                .font(.callout)
                            Spacer()
                            Button {
                                draft.steps.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                        if index < draft.steps.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 8) {
                Picker("Adicionar", selection: $stepKind) {
                    ForEach(StepKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                stepEditor
            }

            Text(hint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                Button("Salvar") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!triggerIsSet || draft.steps.isEmpty
                              || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    @ViewBuilder
    private var stepEditor: some View {
        switch stepKind {
        case .text:
            HStack(spacing: 8) {
                TextField("texto a digitar", text: $textToAdd)
                Button("Adicionar") {
                    draft.steps.append(.text(textToAdd))
                    textToAdd = ""
                }
                .disabled(textToAdd.isEmpty)
            }

        case .keys:
            HStack(spacing: 8) {
                Button(capturingStep ? "Pressione a combinação…" : "Gravar combinação") {
                    capturingStep = true
                }
                KeyCaptureField(isCapturing: $capturingStep) { code, modifiers, label in
                    draft.steps.append(.combo(keyCode: code, modifiers: modifiers, label: label))
                }
                .frame(width: 1, height: 1)
                Spacer()
            }

        case .url:
            HStack(spacing: 8) {
                TextField("exemplo.com ou https://…", text: $urlToAdd)
                Button("Adicionar") {
                    draft.steps.append(.openURL(urlToAdd))
                    urlToAdd = ""
                }
                .disabled(urlToAdd.isEmpty)
            }

        case .app:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button("Escolher aplicativo…") { chooseApp() }
                    Text(appName.isEmpty ? "nenhum escolhido" : appName)
                        .font(.caption)
                        .foregroundStyle(appName.isEmpty ? .tertiary : .secondary)
                    Spacer()
                }
                HStack(spacing: 8) {
                    TextField("URL opcional — abre nesse aplicativo", text: $appURL)
                    Button("Adicionar") {
                        draft.steps.append(.openApp(path: appPath, name: appName,
                                                    url: appURL.isEmpty ? nil : appURL))
                        appURL = ""
                    }
                    .disabled(appPath.isEmpty)
                }
            }

        case .shell:
            HStack(spacing: 8) {
                TextField("comando", text: $shellToAdd)
                    .font(.callout.monospaced())
                Button("Adicionar") {
                    draft.steps.append(.shell(shellToAdd))
                    shellToAdd = ""
                }
                .disabled(shellToAdd.isEmpty)
            }

        case .terminal:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button("Escolher pasta…") { chooseDirectory() }
                    TextField("pasta — ex.: Desktop/meu-projeto", text: $terminalDirectory)
                        .font(.caption.monospaced())
                }
                HStack(spacing: 8) {
                    TextField("comando a rodar — ex.: claude", text: $terminalCommand)
                        .font(.callout.monospaced())
                    Button("Adicionar") {
                        draft.steps.append(.terminal(
                            command: terminalCommand,
                            directory: terminalDirectory.isEmpty ? nil : terminalDirectory))
                        terminalCommand = ""
                    }
                    .disabled(terminalCommand.isEmpty)
                }
            }

        case .delay:
            HStack(spacing: 8) {
                Stepper("Esperar \(delayToAdd) ms", value: $delayToAdd, in: 10...5000, step: 50)
                    .fixedSize()
                Button("Adicionar") { draft.steps.append(.delay(milliseconds: delayToAdd)) }
                Spacer()
            }
        }
    }

    private var hint: String {
        switch stepKind {
        case .text:
            return "Vai como Unicode, não como keycode: acento, cedilha e emoji saem certos sem depender do layout ativo."
        case .keys:
            return "Para atalhos (⌘S, ⇥, F5) que texto não consegue representar."
        case .url:
            return "Abre no navegador padrão do sistema. Para escolher o navegador, use “Aplicativo” com a URL preenchida."
        case .app:
            return "Sem URL, só lança o aplicativo. Com URL, abre o endereço nele — é assim que se abre uma página no Chrome em vez do navegador padrão."
        case .shell:
            return "Roda em /bin/sh, invisível. Não espera terminar e não mostra a saída — serve para disparar, não para ver resultado."
        case .terminal:
            return "Abre uma janela do Terminal na pasta e roda o comando ali, com a sessão viva — é o que serve para programa interativo. Usa shell de login, então o PATH é o seu (Homebrew incluso). Caminho relativo conta a partir da sua pasta pessoal."
        case .delay:
            return "Alguns aplicativos perdem eventos enviados rápido demais depois de uma troca de foco. Uma espera depois de abrir algo costuma resolver."
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Escolher"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Guarda relativo à pasta pessoal quando dá: fica legível na lista.
        let home = NSHomeDirectory()
        terminalDirectory = url.path.hasPrefix(home + "/")
            ? String(url.path.dropFirst(home.count + 1))
            : url.path
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Escolher"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appPath = url.path
        appName = url.deletingPathExtension().lastPathComponent
    }
}
