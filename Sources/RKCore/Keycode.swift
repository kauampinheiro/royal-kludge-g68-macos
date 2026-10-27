//
//  Keycode.swift
//  Tabela VK (Windows) -> firmware code da Royal Kludge.
//
//  Os códigos de firmware NÃO são HID USB puros: a RK empacota o usage HID
//  no byte alto (`hid << 8`), usa bitflags próprios para modificadores e
//  prefixa `0x01000000` para teclas de consumer control (mídia).
//
//  Tabela derivada do keycode.h do Rangoli (GPL-3.0) e do keycode.ts do
//  Kludge Knight. Ver NOTICE.
//

import Foundation

/// Virtual-Key code do Windows, como aparece nos arquivos `KB.ini` da RK.
public typealias VKCode = Int

/// Código de firmware da RK, escrito nos buffers HID.
public typealias FirmwareCode = UInt32

public enum KeyCategory: String, CaseIterable, Sendable, Codable {
    case letters = "Letras"
    case numbers = "Números"
    case symbols = "Símbolos"
    case functionKeys = "Teclas F"
    case navigation = "Navegação"
    case modifiers = "Modificadores"
    case numpad = "Numérico"
    case media = "Mídia"
    case special = "Especiais"
}

public struct KeyInfo: Hashable, Sendable, Codable {
    public let vk: VKCode
    public let fw: FirmwareCode
    public let category: KeyCategory
    /// Rótulo como o teclado físico é impresso (padrão ANSI/Windows).
    public let label: String
    /// Rótulo equivalente no macOS, quando difere (ex.: Left Win -> ⌘ esquerdo).
    public let macLabel: String?

    public init(vk: VKCode, fw: FirmwareCode, category: KeyCategory, label: String, macLabel: String? = nil) {
        self.vk = vk
        self.fw = fw
        self.category = category
        self.label = label
        self.macLabel = macLabel
    }

    /// Nome a exibir na interface: prefere o rótulo de macOS quando existe.
    public var displayLabel: String { macLabel ?? label }
}

public enum Keycode {
    /// VK -> KeyInfo. Fonte da verdade para tradução de remap.
    public static let map: [VKCode: KeyInfo] = {
        var m: [VKCode: KeyInfo] = [:]
        func add(_ k: KeyInfo) { m[k.vk] = k }

        // Letras (fw = hid << 8)
        let letters: [(VKCode, UInt32, String)] = [
            (0x41, 0x0400, "A"), (0x42, 0x0500, "B"), (0x43, 0x0600, "C"), (0x44, 0x0700, "D"),
            (0x45, 0x0800, "E"), (0x46, 0x0900, "F"), (0x47, 0x0A00, "G"), (0x48, 0x0B00, "H"),
            (0x49, 0x0C00, "I"), (0x4A, 0x0D00, "J"), (0x4B, 0x0E00, "K"), (0x4C, 0x0F00, "L"),
            (0x4D, 0x1000, "M"), (0x4E, 0x1100, "N"), (0x4F, 0x1200, "O"), (0x50, 0x1300, "P"),
            (0x51, 0x1400, "Q"), (0x52, 0x1500, "R"), (0x53, 0x1600, "S"), (0x54, 0x1700, "T"),
            (0x55, 0x1800, "U"), (0x56, 0x1900, "V"), (0x57, 0x1A00, "W"), (0x58, 0x1B00, "X"),
            (0x59, 0x1C00, "Y"), (0x5A, 0x1D00, "Z"),
        ]
        for (vk, fw, label) in letters {
            add(KeyInfo(vk: vk, fw: fw, category: .letters, label: label))
        }

        // Números
        let numbers: [(VKCode, UInt32, String)] = [
            (0x30, 0x2700, "0"), (0x31, 0x1E00, "1"), (0x32, 0x1F00, "2"), (0x33, 0x2000, "3"),
            (0x34, 0x2100, "4"), (0x35, 0x2200, "5"), (0x36, 0x2300, "6"), (0x37, 0x2400, "7"),
            (0x38, 0x2500, "8"), (0x39, 0x2600, "9"),
        ]
        for (vk, fw, label) in numbers {
            add(KeyInfo(vk: vk, fw: fw, category: .numbers, label: label))
        }

        // Teclas F
        for i in 0..<12 {
            add(KeyInfo(vk: 0x70 + i, fw: UInt32(0x3A00 + (i << 8)), category: .functionKeys, label: "F\(i + 1)"))
        }

        // Especiais
        add(KeyInfo(vk: 0x08, fw: 0x2A00, category: .special, label: "Backspace", macLabel: "⌫ Delete"))
        add(KeyInfo(vk: 0x09, fw: 0x2B00, category: .special, label: "Tab", macLabel: "⇥ Tab"))
        add(KeyInfo(vk: 0x0D, fw: 0x2800, category: .special, label: "Enter", macLabel: "⏎ Return"))
        add(KeyInfo(vk: 0x13, fw: 0x4800, category: .special, label: "Pause"))
        add(KeyInfo(vk: 0x14, fw: 0x3900, category: .special, label: "Caps Lock", macLabel: "⇪ Caps Lock"))
        add(KeyInfo(vk: 0x1B, fw: 0x2900, category: .special, label: "Esc", macLabel: "⎋ Esc"))
        add(KeyInfo(vk: 0x20, fw: 0x2C00, category: .special, label: "Space", macLabel: "Espaço"))
        add(KeyInfo(vk: 0xE0, fw: 0x2C00, category: .special, label: "Space (direita)"))
        add(KeyInfo(vk: 0x91, fw: 0x4700, category: .special, label: "Scroll Lock"))
        add(KeyInfo(vk: 0x5D, fw: 0x6500, category: .special, label: "App / Menu"))

        // Navegação
        add(KeyInfo(vk: 0x21, fw: 0x4B00, category: .navigation, label: "Page Up", macLabel: "⇞ Page Up"))
        add(KeyInfo(vk: 0x22, fw: 0x4E00, category: .navigation, label: "Page Down", macLabel: "⇟ Page Down"))
        add(KeyInfo(vk: 0x23, fw: 0x4D00, category: .navigation, label: "End", macLabel: "↘ End"))
        add(KeyInfo(vk: 0x24, fw: 0x4A00, category: .navigation, label: "Home", macLabel: "↖ Home"))
        add(KeyInfo(vk: 0x25, fw: 0x5000, category: .navigation, label: "Esquerda", macLabel: "←"))
        add(KeyInfo(vk: 0x26, fw: 0x5200, category: .navigation, label: "Cima", macLabel: "↑"))
        add(KeyInfo(vk: 0x27, fw: 0x4F00, category: .navigation, label: "Direita", macLabel: "→"))
        add(KeyInfo(vk: 0x28, fw: 0x5100, category: .navigation, label: "Baixo", macLabel: "↓"))
        add(KeyInfo(vk: 0x2C, fw: 0x4600, category: .navigation, label: "Print Screen"))
        add(KeyInfo(vk: 0x2D, fw: 0x4900, category: .navigation, label: "Insert"))
        add(KeyInfo(vk: 0x2E, fw: 0x4C00, category: .navigation, label: "Delete", macLabel: "⌦ Forward Delete"))

        // Símbolos
        add(KeyInfo(vk: 0xBA, fw: 0x3300, category: .symbols, label: "; :"))
        add(KeyInfo(vk: 0xBB, fw: 0x2E00, category: .symbols, label: "= +"))
        add(KeyInfo(vk: 0xBC, fw: 0x3600, category: .symbols, label: ", <"))
        add(KeyInfo(vk: 0xBD, fw: 0x2D00, category: .symbols, label: "- _"))
        add(KeyInfo(vk: 0xBE, fw: 0x3700, category: .symbols, label: ". >"))
        add(KeyInfo(vk: 0xBF, fw: 0x3800, category: .symbols, label: "/ ?"))
        add(KeyInfo(vk: 0xC0, fw: 0x3500, category: .symbols, label: "` ~"))
        add(KeyInfo(vk: 0xDB, fw: 0x2F00, category: .symbols, label: "[ {"))
        add(KeyInfo(vk: 0xDC, fw: 0x3100, category: .symbols, label: "\\ |"))
        add(KeyInfo(vk: 0xDD, fw: 0x3000, category: .symbols, label: "] }"))
        add(KeyInfo(vk: 0xDE, fw: 0x3400, category: .symbols, label: "' \""))
        add(KeyInfo(vk: 0xE2, fw: 0x6400, category: .symbols, label: "\\ | (ISO)"))

        // Modificadores — bitflags próprios do firmware RK
        add(KeyInfo(vk: 0xA0, fw: 0x020000, category: .modifiers, label: "Shift esquerdo", macLabel: "⇧ esquerdo"))
        add(KeyInfo(vk: 0xA1, fw: 0x200000, category: .modifiers, label: "Shift direito", macLabel: "⇧ direito"))
        add(KeyInfo(vk: 0xA2, fw: 0x010000, category: .modifiers, label: "Ctrl esquerdo", macLabel: "⌃ esquerdo"))
        add(KeyInfo(vk: 0xA3, fw: 0x100000, category: .modifiers, label: "Ctrl direito", macLabel: "⌃ direito"))
        add(KeyInfo(vk: 0xA4, fw: 0x040000, category: .modifiers, label: "Alt esquerdo", macLabel: "⌥ Option esquerdo"))
        add(KeyInfo(vk: 0xA5, fw: 0x400000, category: .modifiers, label: "Alt direito", macLabel: "⌥ Option direito"))
        add(KeyInfo(vk: 0x5B, fw: 0x080000, category: .modifiers, label: "Win esquerdo", macLabel: "⌘ Command esquerdo"))
        add(KeyInfo(vk: 0x5C, fw: 0x800000, category: .modifiers, label: "Win direito", macLabel: "⌘ Command direito"))
        add(KeyInfo(vk: 0xFA, fw: 0xB000, category: .modifiers, label: "Fn"))

        // Teclado numérico
        let numpad: [(VKCode, UInt32, String)] = [
            (0x60, 0x6200, "Num 0"), (0x61, 0x5900, "Num 1"), (0x62, 0x5A00, "Num 2"),
            (0x63, 0x5B00, "Num 3"), (0x64, 0x5C00, "Num 4"), (0x65, 0x5D00, "Num 5"),
            (0x66, 0x5E00, "Num 6"), (0x67, 0x5F00, "Num 7"), (0x68, 0x6000, "Num 8"),
            (0x69, 0x6100, "Num 9"), (0x6A, 0x5500, "Num *"), (0x6B, 0x5700, "Num +"),
            (0x6D, 0x5600, "Num -"), (0x6E, 0x6300, "Num ."), (0x6F, 0x5400, "Num /"),
            (0x90, 0x5300, "Num Lock"), (0xFD, 0x5800, "Num Enter"),
        ]
        for (vk, fw, label) in numpad {
            add(KeyInfo(vk: vk, fw: fw, category: .numpad, label: label))
        }

        // Mídia (consumer control: 0x01000000 | usage)
        add(KeyInfo(vk: 0xAD, fw: 0x010000E2, category: .media, label: "Mudo", macLabel: "🔇 Mudo"))
        add(KeyInfo(vk: 0xAE, fw: 0x010000EA, category: .media, label: "Volume -"))
        add(KeyInfo(vk: 0xAF, fw: 0x010000E9, category: .media, label: "Volume +"))
        add(KeyInfo(vk: 0xB0, fw: 0x010000B5, category: .media, label: "Faixa seguinte"))
        add(KeyInfo(vk: 0xB1, fw: 0x010000B6, category: .media, label: "Faixa anterior"))
        add(KeyInfo(vk: 0xB2, fw: 0x010000B7, category: .media, label: "Parar"))
        add(KeyInfo(vk: 0xB3, fw: 0x010000CD, category: .media, label: "Play/Pause"))
        add(KeyInfo(vk: 0x99, fw: 0x01000192, category: .media, label: "Calculadora"))

        // Codificação alternativa de mídia usada por firmwares RK mais antigos
        add(KeyInfo(vk: 0x89, fw: 0x010000CD, category: .media, label: "Play/Pause (alt)"))
        add(KeyInfo(vk: 0x8A, fw: 0x010000B7, category: .media, label: "Parar (alt)"))
        add(KeyInfo(vk: 0x8B, fw: 0x010000B6, category: .media, label: "Faixa anterior (alt)"))
        add(KeyInfo(vk: 0x8C, fw: 0x010000B5, category: .media, label: "Faixa seguinte (alt)"))
        add(KeyInfo(vk: 0x8D, fw: 0x010000E9, category: .media, label: "Volume + (alt)"))
        add(KeyInfo(vk: 0x8E, fw: 0x010000EA, category: .media, label: "Volume - (alt)"))
        add(KeyInfo(vk: 0x8F, fw: 0x010000E2, category: .media, label: "Mudo (alt)"))

        // Brilho — VKs sintéticos (fora da faixa real do Windows) só para remap
        add(KeyInfo(vk: 0x1001, fw: 0x0100006F, category: .media, label: "Brilho +", macLabel: "🔆 Brilho +"))
        add(KeyInfo(vk: 0x1002, fw: 0x01000070, category: .media, label: "Brilho -", macLabel: "🔅 Brilho -"))

        // Atalhos de edição gravados no firmware (capturados do software oficial)
        add(KeyInfo(vk: 0xD9, fw: 0x010400, category: .special, label: "Selecionar tudo (Ctrl+A)"))
        add(KeyInfo(vk: 0xB9, fw: 0x010600, category: .special, label: "Copiar (Ctrl+C)"))
        add(KeyInfo(vk: 0xB8, fw: 0x011B00, category: .special, label: "Cortar (Ctrl+X)"))
        add(KeyInfo(vk: 0xC6, fw: 0x011900, category: .special, label: "Colar (Ctrl+V)"))
        add(KeyInfo(vk: 0xC1, fw: 0x011D00, category: .special, label: "Desfazer (Ctrl+Z)"))
        add(KeyInfo(vk: 0xC7, fw: 0x011600, category: .special, label: "Salvar (Ctrl+S)"))

        return m
    }()

    /// Busca pelo VK. Devolve `nil` para VKs que o catálogo não reconhece.
    public static func info(vk: VKCode) -> KeyInfo? { map[vk] }

    /// Converte o VK de um `KB.ini` em `KeyInfo`, usando o campo seguinte do
    /// arquivo como firmware code de reserva quando o VK não está no catálogo.
    ///
    /// VKs `<= 0x05` são índices sequenciais usados por teclados estilo A72,
    /// com outro esquema de codificação: não são remapeáveis aqui.
    public static func parse(vkHex: String, fallbackFirmwareHex: String? = nil) -> KeyInfo? {
        guard let vk = Int(vkHex.trimmingCharacters(in: .whitespaces), radix: 16) else { return nil }
        if let known = map[vk] { return known }

        if let hex = fallbackFirmwareHex,
           let fw = UInt32(hex.trimmingCharacters(in: .whitespaces), radix: 16), fw > 0 {
            return KeyInfo(vk: vk, fw: fw, category: .special, label: "VK 0x\(String(vk, radix: 16, uppercase: true))")
        }

        if vk <= 0x05 { return nil }

        return KeyInfo(vk: vk, fw: 0, category: .special, label: "VK 0x\(String(vk, radix: 16, uppercase: true))")
    }

    /// Teclas atribuíveis a um remap, agrupadas por categoria na ordem de exibição.
    public static func assignableKeys() -> [(KeyCategory, [KeyInfo])] {
        KeyCategory.allCases.compactMap { category in
            let keys = map.values
                .filter { $0.category == category && $0.fw != 0 }
                .sorted { $0.vk < $1.vk }
            return keys.isEmpty ? nil : (category, keys)
        }
    }
}
