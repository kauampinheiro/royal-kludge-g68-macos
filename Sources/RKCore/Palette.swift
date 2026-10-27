//
//  Palette.swift
//  Cores validadas a olho no teclado físico.
//
//  A calibração por canal (ver `Calibration.swift`) acerta o eixo neutro —
//  branco e cinzas — e melhora o resto por tabela. Mas ela é um modelo de três
//  ganhos e um expoente, e o LED não obedece a modelo nenhum com fidelidade:
//  matizes que dependem dos três canais em proporções desiguais continuam
//  saindo de onde deveriam, e não existe ganho que conserte todos ao mesmo
//  tempo.
//
//  Daí a paleta: em vez de calcular a cor, **registrar a que foi aprovada
//  olhando o teclado**. Duas consequências de projeto, as duas deliberadas:
//
//  1. **O preset guarda os bytes crus, não a cor pedida.** Uma cor validada é
//     uma afirmação sobre o hardware ("estes bytes acendem laranja neste
//     teclado"), e tem de sobreviver a mudança de calibração. Se guardasse a
//     cor pedida, recalibrar mudaria a aparência de todos os presets de uma vez
//     e jogaria fora o trabalho de validação.
//  2. **O preset guarda com quantos LEDs acesos foi julgado.** A mesma tripla
//     muda de cor com a carga — foi medido. Um laranja aprovado com o teclado
//     cheio não é o mesmo laranja com três teclas acesas, e fingir que é seria
//     repetir o erro que fazia o branco virar ciano.
//

import Foundation

/// Uma cor aprovada a olho, com a condição em que foi aprovada.
public struct PaletteEntry: Codable, Sendable, Equatable, Identifiable {
    /// Nome que o usuário deu. É a identidade do preset.
    public var name: String

    /// Bytes exatos enviados ao teclado. **Não passa pela calibração**: já é o
    /// resultado validado.
    public var color: RKColor

    /// Quantos LEDs estavam acesos quando a cor foi julgada. `nil` = não
    /// anotado (presets antigos).
    public var litCount: Int?

    /// O que o olho viu, nas palavras de quem validou.
    public var note: String?

    /// Quando entrou na paleta.
    public var created: Date

    public var id: String { name }

    public init(name: String, color: RKColor, litCount: Int? = nil,
                note: String? = nil, created: Date = Date()) {
        self.name = name
        self.color = color
        self.litCount = litCount
        self.note = note
        self.created = created
    }

    /// Chave de comparação: nome sem caixa nem acento, para `laranja` e
    /// `Laranja` serem o mesmo preset.
    public var key: String { PaletteEntry.normalize(name) }

    public static func normalize(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespaces)
    }

    /// Como aparece numa listagem.
    public var summary: String {
        var parts = [color.hex]
        if let litCount { parts.append("validada com \(litCount) LED(s)") }
        if let note, !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

public struct Palette: Codable, Sendable {
    public var entries: [PaletteEntry]

    public init(entries: [PaletteEntry] = []) {
        self.entries = entries
    }

    public func entry(named name: String) -> PaletteEntry? {
        let needle = PaletteEntry.normalize(name)
        return entries.first { $0.key == needle }
    }

    /// Insere ou substitui pelo nome. Devolve `true` se substituiu.
    @discardableResult
    public mutating func put(_ entry: PaletteEntry) -> Bool {
        if let index = entries.firstIndex(where: { $0.key == entry.key }) {
            entries[index] = entry
            return true
        }
        entries.append(entry)
        entries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return false
    }

    @discardableResult
    public mutating func remove(named name: String) -> PaletteEntry? {
        let needle = PaletteEntry.normalize(name)
        guard let index = entries.firstIndex(where: { $0.key == needle }) else { return nil }
        return entries.remove(at: index)
    }
}

public struct PaletteStore: Sendable {
    public let url: URL

    public init(directory: URL? = nil) {
        let base = directory ?? {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            return support.appendingPathComponent("RKG68Mac", isDirectory: true)
        }()
        self.url = base.appendingPathComponent("palette.json")
    }

    public func load() -> Palette {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let value = try? decoder.decode(Palette.self, from: data) else {
            return Palette()
        }
        return value
    }

    public func save(_ palette: Palette) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(palette).write(to: url, options: .atomic)
    }
}
