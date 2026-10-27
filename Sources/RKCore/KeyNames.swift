//
//  KeyNames.swift
//  Tradução de nomes amigáveis ("caps", "lcmd", "volup") para teclas do
//  layout e para funções de destino. Usado pelo CLI e pela busca do app.
//

import Foundation

public enum KeyNames {
    /// Apelidos digitáveis -> VK. Inclui a nomenclatura do macOS (`cmd`,
    /// `option`) apontando para os VKs que o firmware RK usa (Win/Alt).
    public static let aliases: [String: VKCode] = [
        // modificadores, nomes de macOS e de Windows no mesmo lugar
        "caps": 0x14, "capslock": 0x14, "esc": 0x1B, "escape": 0x1B,
        "tab": 0x09, "enter": 0x0D, "return": 0x0D, "space": 0x20, "espaco": 0x20,
        "backspace": 0x08, "del": 0x2E, "delete": 0x2E, "fwddelete": 0x2E, "insert": 0x2D,
        "lshift": 0xA0, "rshift": 0xA1, "shift": 0xA0,
        "lctrl": 0xA2, "rctrl": 0xA3, "ctrl": 0xA2, "control": 0xA2,
        "lalt": 0xA4, "ralt": 0xA5, "alt": 0xA4,
        "loption": 0xA4, "roption": 0xA5, "option": 0xA4, "opt": 0xA4,
        "lwin": 0x5B, "rwin": 0x5C, "win": 0x5B,
        "lcmd": 0x5B, "rcmd": 0x5C, "cmd": 0x5B, "command": 0x5B,
        "fn": 0xFA, "menu": 0x5D, "app": 0x5D,
        // navegação
        "left": 0x25, "right": 0x27, "up": 0x26, "down": 0x28,
        "home": 0x24, "end": 0x23, "pgup": 0x21, "pageup": 0x21,
        "pgdn": 0x22, "pagedown": 0x22, "printscreen": 0x2C, "prtsc": 0x2C,
        "scrolllock": 0x91, "pause": 0x13,
        // símbolos
        "semicolon": 0xBA, "equal": 0xBB, "comma": 0xBC, "minus": 0xBD,
        "period": 0xBE, "slash": 0xBF, "grave": 0xC0, "backtick": 0xC0,
        "lbracket": 0xDB, "backslash": 0xDC, "rbracket": 0xDD, "quote": 0xDE,
        // mídia e brilho
        "mute": 0xAD, "voldown": 0xAE, "volumedown": 0xAE,
        "volup": 0xAF, "volumeup": 0xAF,
        "next": 0xB0, "nexttrack": 0xB0, "prev": 0xB1, "prevtrack": 0xB1,
        "stop": 0xB2, "play": 0xB3, "playpause": 0xB3, "calc": 0x99,
        "brightup": 0x1001, "brightnessup": 0x1001,
        "brightdown": 0x1002, "brightnessdown": 0x1002,
        // teclado numérico
        "numlock": 0x90, "numenter": 0xFD,
        // atalhos gravados no firmware
        "copy": 0xB9, "paste": 0xC6, "cut": 0xB8, "undo": 0xC1,
        "selectall": 0xD9, "save": 0xC7,
    ]

    /// Resolve a função de destino de um remap.
    /// Aceita apelido, letra/dígito, `f1`-`f12`, `vk:0x41` ou `0x41`.
    public static func target(_ raw: String) -> KeyInfo? {
        let name = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return nil }

        if let vk = aliases[name] { return Keycode.info(vk: vk) }

        // letra ou dígito solto
        if name.count == 1, let scalar = name.unicodeScalars.first {
            if scalar.properties.isAlphabetic, let upper = name.uppercased().unicodeScalars.first {
                return Keycode.info(vk: Int(upper.value))
            }
            if ("0"..."9").contains(name) {
                return Keycode.info(vk: Int(scalar.value))
            }
        }

        // f1..f12
        if name.hasPrefix("f"), let n = Int(name.dropFirst()), (1...12).contains(n) {
            return Keycode.info(vk: 0x70 + n - 1)
        }

        // num0..num9
        if name.hasPrefix("num"), let n = Int(name.dropFirst(3)), (0...9).contains(n) {
            return Keycode.info(vk: 0x60 + n)
        }

        // VK explícito
        let hexPart = name.hasPrefix("vk:") ? String(name.dropFirst(3)) : name
        let cleaned = hexPart.replacingOccurrences(of: "0x", with: "")
        if let vk = Int(cleaned, radix: 16), let info = Keycode.info(vk: vk) {
            return info
        }

        // último recurso: casar pelo rótulo
        return Keycode.map.values.first {
            $0.label.lowercased() == name || $0.macLabel?.lowercased() == name
        }
    }

    /// Resolve a tecla física do layout a ser remapeada.
    /// Aceita apelido/rótulo, `#<bufferIndex>` ou o nome da entrada do INI (`K1`).
    public static func physicalKey(_ raw: String, in config: KeyboardConfig) -> KeyboardKey? {
        let name = raw.trimmingCharacters(in: .whitespaces)
        let lower = name.lowercased()

        if lower.hasPrefix("#"), let index = Int(lower.dropFirst()) {
            return config.key(bufferIndex: index)
        }
        if let match = config.keys.first(where: { $0.iniKey.lowercased() == lower }) {
            return match
        }
        if let vk = target(lower)?.vk,
           let match = config.keys.first(where: { $0.keyInfo.vk == vk }) {
            return match
        }
        return config.keys.first {
            $0.keyInfo.label.lowercased() == lower || $0.keyInfo.macLabel?.lowercased() == lower
        }
    }
}
