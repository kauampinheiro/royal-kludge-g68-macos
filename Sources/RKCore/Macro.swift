//
//  Macro.swift
//  Macros por software — gatilho e sequência, guardados fora do firmware.
//
//  **Por que não no teclado.** O protocolo de macro da RK nunca foi reproduzido
//  por ninguém. Ele vive noutra família de comandos (`CDev3632::SetMacro`, com
//  CRC e pacotes confirmados), diferente do comando simples de 65 bytes que o
//  resto deste projeto usa, e decifrá-lo exige captura do software oficial
//  rodando no Windows.
//
//  O que dá para fazer hoje é interceptar no macOS: um event tap escuta o
//  gatilho e injeta a sequência. Funciona, e tem dois custos que precisam
//  estar claros para quem usa:
//
//  1. **Não viaja com o teclado.** Ao contrário do remap, que fica gravado no
//     firmware e vale em qualquer computador, a macro só existe enquanto este
//     app estiver rodando neste Mac.
//  2. **Exige Acessibilidade**, outra autorização do sistema além do
//     Monitoramento de Entrada que o acesso HID já pede.
//
//  **O gatilho é gravado, não traduzido.** O layout da RK identifica teclas por
//  VK do Windows, e o event tap fala em keycode do macOS — são tabelas
//  diferentes. Em vez de manter a tradução entre as duas (fonte garantida de
//  erro em tecla morta, layout ABNT e modificador), o gatilho é capturado
//  pressionando a tecla: o que entra é exatamente o que o sistema vai ver.
//

import Foundation

/// Modificadores do gatilho e dos passos. Espelha os bits do `CGEventFlags`
/// que interessam, sem depender do CoreGraphics aqui no núcleo.
public struct MacroModifiers: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift   = MacroModifiers(rawValue: 1 << 0)
    public static let control = MacroModifiers(rawValue: 1 << 1)
    public static let option  = MacroModifiers(rawValue: 1 << 2)
    public static let command = MacroModifiers(rawValue: 1 << 3)

    /// Como aparece na interface, na ordem convencional do macOS.
    public var symbols: String {
        var out = ""
        if contains(.control) { out += "⌃" }
        if contains(.option)  { out += "⌥" }
        if contains(.shift)   { out += "⇧" }
        if contains(.command) { out += "⌘" }
        return out
    }
}

/// Um passo da sequência.
public enum MacroStep: Codable, Sendable, Equatable, Identifiable {
    /// Digita texto literal. Vai como string Unicode, sem depender de keycode —
    /// então acento, emoji e layout diferente funcionam igual.
    case text(String)
    /// Pressiona uma combinação de teclas, em keycode do macOS.
    case combo(keyCode: UInt16, modifiers: MacroModifiers, label: String)
    /// Espera, em milissegundos. Alguns aplicativos perdem eventos enviados
    /// rápido demais seguidos de troca de foco.
    case delay(milliseconds: Int)
    /// Abre um endereço no navegador padrão.
    case openURL(String)
    /// Abre um aplicativo. Com `url`, abre o endereço **nele** — é como se
    /// manda um link para um navegador específico em vez do padrão.
    case openApp(path: String, name: String, url: String?)
    /// Roda um comando no shell. Sai de vista: nada de saída é capturado, e o
    /// passo não espera o comando terminar.
    case shell(String)
    /// Abre uma janela do Terminal numa pasta e roda o comando **ali**, com a
    /// sessão viva — é o que permite deixar um programa interativo rodando.
    case terminal(command: String, directory: String?)

    public var id: String {
        switch self {
        case .text(let value): return "t:\(value)"
        case .combo(let code, let mods, _): return "c:\(code):\(mods.rawValue)"
        case .delay(let ms): return "d:\(ms)"
        case .openURL(let url): return "u:\(url)"
        case .openApp(let path, _, let url): return "a:\(path):\(url ?? "")"
        case .shell(let command): return "s:\(command)"
        case .terminal(let command, let dir): return "x:\(dir ?? ""):\(command)"
        }
    }

    public var summary: String {
        switch self {
        case .text(let value):
            return "digitar “\(Self.short(value))”"
        case .combo(_, let mods, let label):
            return "tecla \(mods.symbols)\(label)"
        case .delay(let ms):
            return "esperar \(ms) ms"
        case .openURL(let url):
            return "abrir \(Self.short(url))"
        case .openApp(_, let name, let url):
            return url.map { "abrir \(Self.short($0)) no \(name)" } ?? "abrir o \(name)"
        case .shell(let command):
            return "shell: \(Self.short(command))"
        case .terminal(let command, let dir):
            guard let dir, !dir.isEmpty else { return "Terminal: \(Self.short(command))" }
            return "Terminal em \((dir as NSString).lastPathComponent): \(Self.short(command))"
        }
    }

    private static func short(_ value: String, limit: Int = 44) -> String {
        value.count > limit ? String(value.prefix(limit)) + "…" : value
    }
}

public struct Macro: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var enabled: Bool

    /// Keycode do macOS capturado ao gravar o gatilho.
    public var triggerKeyCode: UInt16
    public var triggerModifiers: MacroModifiers
    /// Rótulo legível da tecla de gatilho, como ela foi gravada.
    public var triggerLabel: String

    public var steps: [MacroStep]

    public init(id: UUID = UUID(), name: String, enabled: Bool = true,
                triggerKeyCode: UInt16, triggerModifiers: MacroModifiers = [],
                triggerLabel: String, steps: [MacroStep] = []) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.triggerKeyCode = triggerKeyCode
        self.triggerModifiers = triggerModifiers
        self.triggerLabel = triggerLabel
        self.steps = steps
    }

    public var triggerSummary: String {
        triggerModifiers.symbols + triggerLabel
    }

    /// Duas macros com o mesmo gatilho: a segunda nunca dispararia.
    public func conflicts(with other: Macro) -> Bool {
        id != other.id
            && triggerKeyCode == other.triggerKeyCode
            && triggerModifiers == other.triggerModifiers
    }
}

public struct MacroSet: Codable, Sendable {
    public var macros: [Macro]

    public init(macros: [Macro] = []) {
        self.macros = macros
    }
}

public struct MacroStore: Sendable {
    public let url: URL

    public init(directory: URL? = nil) {
        let base = directory ?? {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            return support.appendingPathComponent("RKG68Mac", isDirectory: true)
        }()
        self.url = base.appendingPathComponent("macros.json")
    }

    public func load() -> MacroSet {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(MacroSet.self, from: data) else {
            return MacroSet()
        }
        return value
    }

    public func save(_ set: MacroSet) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(set).write(to: url, options: .atomic)
    }
}
