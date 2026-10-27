//
//  MacroEngine.swift
//  Intercepta o gatilho e injeta a sequência, via CGEventTap.
//
//  Três cuidados que fazem a diferença entre funcionar e travar o teclado do
//  usuário inteiro:
//
//  1. **Não se ouvir.** Os eventos que o próprio motor posta passariam pelo
//     tap outra vez; uma macro cujo passo contém o gatilho viraria laço
//     infinito. Cada evento postado leva uma marca em `eventSourceUserData`, e
//     o tap ignora o que está marcado.
//  2. **Não bloquear o tap.** O callback roda na thread do run loop e o
//     sistema **desliga** o tap se ele demorar. A sequência é despachada numa
//     fila própria e o callback devolve na hora.
//  3. **Voltar depois de desligado.** Mesmo assim o macOS desabilita o tap em
//     `tapDisabledByTimeout`; sem reabilitar, as macros param em silêncio e o
//     usuário só descobre tentando.
//
//  O gatilho é engolido (callback devolve `nil`) no keyDown **e** no keyUp:
//  entregar só metade do par deixa o aplicativo de destino achando que a tecla
//  continua pressionada.
//

import AppKit
import ApplicationServices
import CoreGraphics
import RKCore

final class MacroEngine: @unchecked Sendable {
    static let shared = MacroEngine()

    /// Marca dos eventos que nós mesmos postamos — "RKG8" em hexadecimal.
    private static let marker: Int64 = 0x524B_4738

    private let lock = NSLock()
    private var macros: [Macro] = []
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let queue = DispatchQueue(label: "com.kauampinheiro.rkg68.macros", qos: .userInitiated)

    private init() {}

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return tap != nil
    }

    /// O macOS já confia neste app para controlar o computador?
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Pede a autorização, abrindo o diálogo do sistema. O macOS só mostra o
    /// diálogo uma vez por app; depois disso é preciso ir aos Ajustes à mão.
    static func requestAccessibility() {
        // A constante do ApplicationServices é `var` global e o compilador de
        // concorrência a recusa; o valor é estável e público.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Troca o conjunto em vigor. Só as habilitadas entram: filtrar aqui
    /// mantém o callback — que roda a cada tecla do sistema — no menor
    /// trabalho possível.
    func update(_ macros: [Macro]) {
        lock.lock()
        self.macros = macros.filter { $0.enabled && !$0.steps.isEmpty }
        lock.unlock()
    }

    @discardableResult
    func start() -> Bool {
        lock.lock()
        let alreadyRunning = tap != nil
        lock.unlock()
        if alreadyRunning { return true }
        guard Self.hasAccessibility else { return false }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let engine = Unmanaged<MacroEngine>.fromOpaque(refcon).takeUnretainedValue()
                return engine.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        lock.lock()
        tap = port
        runLoopSource = source
        lock.unlock()
        return true
    }

    func stop() {
        lock.lock()
        let port = tap
        let source = runLoopSource
        tap = nil
        runLoopSource = nil
        lock.unlock()

        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }

    // MARK: - Interceptação

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // O sistema desliga o tap se o callback demorar; sem reabilitar, as
        // macros simplesmente param de funcionar sem avisar ninguém.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let port = tap
            lock.unlock()
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }
        // Evento que nós mesmos postamos: deixa passar, senão uma macro que
        // contenha o próprio gatilho entra em laço.
        guard event.getIntegerValueField(.eventSourceUserData) != Self.marker else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = Self.modifiers(from: event.flags)

        lock.lock()
        let match = macros.first { $0.triggerKeyCode == keyCode && $0.triggerModifiers == modifiers }
        lock.unlock()

        guard let match else { return Unmanaged.passUnretained(event) }

        // Dispara só no keyDown; o keyUp é engolido para o aplicativo de
        // destino não ficar com meia tecla pressionada.
        if type == .keyDown { run(match) }
        return nil
    }

    private static func modifiers(from flags: CGEventFlags) -> MacroModifiers {
        var out: MacroModifiers = []
        if flags.contains(.maskShift) { out.insert(.shift) }
        if flags.contains(.maskControl) { out.insert(.control) }
        if flags.contains(.maskAlternate) { out.insert(.option) }
        if flags.contains(.maskCommand) { out.insert(.command) }
        return out
    }

    private static func flags(from modifiers: MacroModifiers) -> CGEventFlags {
        var out: CGEventFlags = []
        if modifiers.contains(.shift) { out.insert(.maskShift) }
        if modifiers.contains(.control) { out.insert(.maskControl) }
        if modifiers.contains(.option) { out.insert(.maskAlternate) }
        if modifiers.contains(.command) { out.insert(.maskCommand) }
        return out
    }

    // MARK: - Execução

    /// Fora do callback, sempre: o tap tem orçamento de tempo e a sequência
    /// pode levar centenas de milissegundos.
    private func run(_ macro: Macro) {
        queue.async { [steps = macro.steps] in
            guard let source = CGEventSource(stateID: .hidSystemState) else { return }
            // Os modificadores do gatilho ainda estão fisicamente pressionados
            // quando a sequência roda. Sem zerar, um gatilho com ⌘ faria cada
            // letra digitada virar atalho.
            source.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalKeyboardEvents, .permitLocalMouseEvents, .permitSystemDefinedEvents],
                state: .eventSuppressionStateSuppressionInterval)

            for step in steps {
                switch step {
                case .delay(let milliseconds):
                    Thread.sleep(forTimeInterval: Double(milliseconds) / 1000)
                case .text(let value):
                    Self.type(value, source: source)
                case .combo(let keyCode, let modifiers, _):
                    Self.press(keyCode: keyCode, modifiers: modifiers, source: source)
                case .openURL(let value):
                    Self.open(url: value, inAppAt: nil)
                case .openApp(let path, _, let url):
                    Self.open(url: url, inAppAt: path)
                case .shell(let command):
                    Self.runShell(command)
                case .terminal(let command, let directory):
                    Self.runInTerminal(command: command, directory: directory)
                }
            }
        }
    }

    /// Texto vai como string Unicode no evento, não como keycode: assim acento,
    /// cedilha e emoji saem certos sem depender do layout ativo.
    private static func type(_ text: String, source: CGEventSource) {
        let units = Array(text.utf16)
        // Em blocos: `keyboardSetUnicodeString` não é feito para strings longas.
        for chunk in stride(from: 0, to: units.count, by: 16).map({
            Array(units[$0..<min($0 + 16, units.count)])
        }) {
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isDown) else { continue }
                var buffer = chunk
                event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
                event.setIntegerValueField(.eventSourceUserData, value: marker)
                event.post(tap: .cgSessionEventTap)
            }
            Thread.sleep(forTimeInterval: 0.002)
        }
    }

    /// Abrir aplicativo e endereço.
    ///
    /// Com `inAppAt`, o endereço vai **naquele** aplicativo — é o que faz
    /// "abrir esta URL no Chrome" em vez de no navegador padrão. Sem URL,
    /// apenas lança o aplicativo.
    ///
    /// O `NSWorkspace` volta ao main actor de propósito: a sequência roda numa
    /// fila de trabalho, e lançar aplicativo dali é pedir comportamento
    /// errático.
    private static func open(url: String?, inAppAt path: String?) {
        let target = url.flatMap { URL(string: $0.contains("://") ? $0 : "https://\($0)") }
        let appURL = path.map { URL(fileURLWithPath: $0) }

        DispatchQueue.main.async {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true

            switch (target, appURL) {
            case (let target?, let appURL?):
                NSWorkspace.shared.open([target], withApplicationAt: appURL,
                                        configuration: configuration)
            case (let target?, nil):
                NSWorkspace.shared.open(target)
            case (nil, let appURL?):
                NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            case (nil, nil):
                break
            }
        }
    }

    /// Roda o comando e segue em frente: não espera, não captura saída.
    ///
    /// Esperar travaria a sequência num comando que não termina, e o passo
    /// seguinte provavelmente é digitar em algum lugar.
    private static func runShell(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// Abre o Terminal numa pasta e deixa o comando rodando ali.
    ///
    /// **Por que um arquivo `.command` e não AppleScript.** O caminho usual
    /// (`osascript -e 'tell application "Terminal" to do script …'`) exige a
    /// autorização de **Automação**, uma terceira do TCC além do Monitoramento
    /// de Entrada e da Acessibilidade que este app já pede. Abrir um script
    /// executável com o Terminal faz a mesma coisa sem Apple Events nenhum.
    ///
    /// O shebang é `zsh -l` de propósito: sem shell de login o `PATH` do
    /// usuário não é montado e comandos instalados por Homebrew não são
    /// encontrados.
    private static func runInTerminal(command: String, directory: String?) {
        let fileManager = FileManager.default
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let folder = support.appendingPathComponent("RKG68Mac/terminal", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        var script = "#!/bin/zsh -l\n"
        if let directory, !directory.isEmpty {
            script += "cd \(shellQuoted(expand(directory))) || exit 1\n"
        }
        script += command + "\n"

        // Nome derivado do conteúdo: a mesma macro reaproveita o arquivo em vez
        // de encher a pasta a cada disparo.
        let file = folder.appendingPathComponent("\(fnv1a(script)).command")
        guard (try? script.write(to: file, atomically: true, encoding: .utf8)) != nil else { return }
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)

        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        DispatchQueue.main.async {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: configuration)
        }
    }

    /// Aceita `~/…`, caminho absoluto e caminho relativo à pasta pessoal —
    /// quem escreve "Desktop/projeto" quer dizer a pasta pessoal.
    private static func expand(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return expanded }
        return (NSHomeDirectory() as NSString).appendingPathComponent(expanded)
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func fnv1a(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    private static func press(keyCode: UInt16, modifiers: MacroModifiers, source: CGEventSource) {
        let flags = Self.flags(from: modifiers)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cgSessionEventTap)
        }
        Thread.sleep(forTimeInterval: 0.004)
    }
}
