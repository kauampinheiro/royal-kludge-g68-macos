//
//  KeyboardConfig.swift
//  Modelo do teclado montado a partir dos arquivos da RK: catálogo de PIDs
//  (Cfg.ini), layout e capacidades (Dev/<PID>/KB.ini) e nomes dos modos de
//  iluminação (led.xml).
//

import Foundation

/// Vendor ID da SinoWealth, usado por todos os teclados RK suportados.
public let rkVendorID: Int = 0x258A

public enum LightingKind: String, Sendable, Codable {
    case none       // sem iluminação
    case backlit    // LED de cor única (tc_led1-20)
    case rgb        // RGB de teclado inteiro (tc_led_mode1-21)
    case eft        // RGB reativo por tecla (tc_eft1-19)
}

/// Quais controles o modo aceita — vem dos 6 campos de `LedOpt<n>`.
public struct LightingModeFlags: Hashable, Sendable, Codable {
    public let animation: Bool   // campo 1: reservado, sempre 0 nos arquivos observados
    public let speed: Bool       // campo 2: slider de velocidade (1-5)
    public let brightness: Bool  // campo 3: slider de brilho (1-5)
    public let direction: Int    // campo 4: 0=nenhuma, 1=esquerda/direita, 2=cima/baixo
    public let random: Bool      // campo 5: cores aleatórias
    public let colorPicker: Bool // campo 6: cor fixa escolhida

    public init?(raw: String) {
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 6 else { return nil }
        animation = parts[0] == "1"
        speed = parts[1] == "1"
        brightness = parts[2] == "1"
        direction = Int(parts[3]) ?? 0
        random = parts[4] == "1"
        colorPicker = parts[5] == "1"
    }
}

public struct LightingMode: Hashable, Sendable, Codable, Identifiable {
    /// Índice 1-based: `LedOpt1` é o modo 1 e é o valor enviado ao firmware.
    public let index: Int
    public let name: String
    public let flags: LightingModeFlags

    public var id: Int { index }
}

/// Uma tecla física do teclado.
public struct KeyboardKey: Hashable, Sendable, Identifiable {
    /// Índice da tecla no buffer de remap — a posição que o firmware entende.
    public let bufferIndex: Int
    public let keyInfo: KeyInfo
    /// Retângulo na imagem do teclado: (left, top, right, bottom) em pixels.
    public let rect: (left: Int, top: Int, right: Int, bottom: Int)
    /// Nome da entrada no KB.ini (`K1`, `K2`, ...), útil para diagnóstico.
    public let iniKey: String

    public var id: Int { bufferIndex }

    public static func == (lhs: KeyboardKey, rhs: KeyboardKey) -> Bool {
        lhs.bufferIndex == rhs.bufferIndex && lhs.keyInfo == rhs.keyInfo && lhs.iniKey == rhs.iniKey
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bufferIndex)
        hasher.combine(keyInfo)
        hasher.combine(iniKey)
    }
}

/// Um conjunto de teclas pré-definido pela RK: acende só essas, apagando o
/// resto. No `KB.ini` são `GaoshouKey1`/`GaoshouKey2` com a cor `clrGaoshou`
/// ("gaoshou" = 高手, "mestre"; na interface oficial em inglês viram
/// **Gaming mode** e **Office mode**, na aba Avançado).
///
/// As listas vêm em **VK do Windows**, não em índice de buffer — por isso
/// precisam ser traduzidas contra o layout antes de virar cor por tecla.
public struct KeySet: Sendable, Identifiable {
    public let name: String
    public let vks: [VKCode]
    public let color: RKColor

    public var id: String { name }

    public init(name: String, vks: [VKCode], color: RKColor) {
        self.name = name
        self.vks = vks
        self.color = color
    }
}

public struct KeyboardConfig: Sendable {
    public let pid: String            // minúsculo, 4 dígitos hex
    public let name: String           // nome comercial vindo do Cfg.ini
    public let keys: [KeyboardKey]
    public let keyCount: Int          // LayoutKeyNum declarado no KB.ini
    public let lightingKind: LightingKind
    public let lightingModes: [LightingMode]
    /// PID cuja arte deve ser usada (`KbImgUse` aponta para outro modelo).
    public let imagePID: String
    public let usesLEDImage: Bool
    /// Conjuntos de teclas que o software oficial chama de "Gaming mode" e
    /// "Office mode", com a cor que ele usa para acendê-los.
    public let keySets: [KeySet]

    public var hasLighting: Bool { !lightingModes.isEmpty }
    public var isRGB: Bool { lightingKind == .rgb || lightingKind == .eft }

    /// Caixa que envolve todas as teclas, em pixels da arte do teclado.
    /// A interface escala os retângulos por esta medida.
    public var layoutBounds: (width: Int, height: Int) {
        let right = keys.map(\.rect.right).max() ?? 1
        let bottom = keys.map(\.rect.bottom).max() ?? 1
        return (right, bottom)
    }

    /// Traduz um conjunto em cor por tecla, pronto para `applyPerKeyColors`.
    /// Teclas do conjunto que este layout não tem são ignoradas em silêncio —
    /// as listas da RK são as mesmas para a família inteira, então trazem
    /// teclas que um modelo de 68 não possui.
    public func perKeyColors(for set: KeySet) -> [Int: RKColor] {
        // A RK lista os modificadores na forma genérica do Windows
        // (VK_SHIFT, VK_CONTROL, VK_MENU), mas o layout só tem as teclas
        // físicas esquerda e direita. Sem expandir, o conjunto Escritório
        // perdia os dois Shift, os dois Ctrl e os dois Alt.
        let genericos: [VKCode: [VKCode]] = [
            0x10: [0xA0, 0xA1],   // Shift  → LShift, RShift
            0x11: [0xA2, 0xA3],   // Ctrl   → LCtrl,  RCtrl
            0x12: [0xA4, 0xA5],   // Alt    → LAlt,   RAlt
        ]
        var wanted = Set(set.vks)
        for vk in set.vks {
            if let fisicas = genericos[vk] { wanted.formUnion(fisicas) }
        }

        var out: [Int: RKColor] = [:]
        for key in keys where wanted.contains(key.keyInfo.vk) {
            out[key.bufferIndex] = set.color
        }
        return out
    }

    public func key(bufferIndex: Int) -> KeyboardKey? {
        keys.first { $0.bufferIndex == bufferIndex }
    }

    /// Teclas em fileiras físicas, de cima para baixo e da esquerda para a
    /// direita.
    ///
    /// O `KB.ini` dá retângulos, não fileiras, e teclas da mesma fileira nem
    /// sempre têm o mesmo topo — no G68 variam 1 ou 2 pixels, o que separaria
    /// a barra de espaço da própria fileira. A tolerância fecha o grupo.
    ///
    /// Serve para validar cor com carga controlada: uma fileira acesa é uma
    /// carga conhecida, e cinco candidatos em cinco fileiras se comparam numa
    /// olhada só.
    public func rows(tolerance: Int = 10) -> [[KeyboardKey]] {
        let sorted = keys.sorted { $0.rect.top < $1.rect.top }
        var out: [[KeyboardKey]] = []
        for key in sorted {
            if let last = out.last, let first = last.first,
               key.rect.top - first.rect.top <= tolerance {
                out[out.count - 1].append(key)
            } else {
                out.append([key])
            }
        }
        return out.map { $0.sorted { $0.rect.left < $1.rect.left } }
    }

    /// Modo cujo nome indica cor por tecla (`Customize` / `Self-define`).
    public var customColorMode: LightingMode? {
        lightingModes.first {
            let n = $0.name.lowercased()
            return n.contains("customize") || n.contains("self-define") || n.contains("custom")
        }
    }
}

public enum KeyboardConfigError: Error, LocalizedError {
    case unknownPID(String)
    case missingKeySection(String)

    public var errorDescription: String? {
        switch self {
        case .unknownPID(let pid):
            return "Nenhuma definição de teclado para o PID 0x\(pid.uppercased()). Esse modelo não está no catálogo da RK incluído no app."
        case .missingKeySection(let pid):
            return "KB.ini do PID 0x\(pid.uppercased()) não tem seção [KEY]."
        }
    }
}

/// Catálogo PID -> nome comercial, lido do `Cfg.ini` do software oficial.
public struct KeyboardCatalog: Sendable {
    public let devices: [String: String]

    public init(cfgIni url: URL) throws {
        let text = INIFile.decode(try Data(contentsOf: url))
        var map: [String: String] = [:]
        // Linhas no formato: DevName17=005c,RK-G68RGB-UK Keyboard
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("devname"),
                  let eq = trimmed.firstIndex(of: "=") else { continue }
            let value = trimmed[trimmed.index(after: eq)...]
            let parts = value.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty else { continue }
            map[parts[0].lowercased()] = parts[1]
        }
        devices = map
    }

    public func name(pid: String) -> String? { devices[pid.lowercased()] }
}

public struct KeyboardConfigLoader: Sendable {
    let resources: RKResources
    let catalog: KeyboardCatalog

    public init(resources: RKResources) throws {
        self.resources = resources
        self.catalog = try KeyboardCatalog(cfgIni: resources.cfgIni)
    }

    public func load(pid rawPID: String) throws -> KeyboardConfig {
        let pid = rawPID.lowercased()
        guard let kbIniURL = resources.kbIni(pid: pid) else {
            throw KeyboardConfigError.unknownPID(pid)
        }
        let ini = try INIFile(contentsOf: kbIniURL)

        guard !ini.entries("KEY").isEmpty else {
            throw KeyboardConfigError.missingKeySection(pid)
        }

        // --- Teclas ---
        // Formato: K<n>=left,top,right,bottom,flags,vk,extra,bufferIndex
        var keys: [KeyboardKey] = []
        for (name, value) in ini.entries("KEY") {
            guard name.uppercased().hasPrefix("K") else { continue }
            let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 8 else { continue }

            let vkHex = parts[5].replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            let fallbackHex = parts[6].replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            guard let info = Keycode.parse(vkHex: vkHex, fallbackFirmwareHex: fallbackHex),
                  let l = Int(parts[0]), let t = Int(parts[1]),
                  let r = Int(parts[2]), let b = Int(parts[3]),
                  let bIndex = Int(parts[7]) else { continue }

            keys.append(KeyboardKey(bufferIndex: bIndex, keyInfo: info,
                                    rect: (l, t, r, b), iniKey: name))
        }
        keys.sort { $0.bufferIndex < $1.bufferIndex }

        // --- Iluminação ---
        let isRGB = ini.bool("OPT", "RGBKb")
        let hasEFT = ini.string("OPT", "MaxEftKeyIndex") != nil

        var flagsByIndex: [(Int, LightingModeFlags)] = []
        for i in 1...21 {
            guard let raw = ini.string("OPT", "LedOpt\(i)"),
                  let flags = LightingModeFlags(raw: raw) else { continue }
            flagsByIndex.append((i, flags))
        }

        let kind: LightingKind = hasEFT ? .eft : (isRGB ? .rgb : (flagsByIndex.isEmpty ? .none : .backlit))
        var modes: [LightingMode] = []
        if !flagsByIndex.isEmpty, kind != .none {
            let names = LedXMLParser.modeNames(resources: resources, pid: pid, kind: kind)
            modes = flagsByIndex.map { index, flags in
                LightingMode(index: index, name: names[index] ?? "Modo \(index)", flags: flags)
            }
        }

        // --- Arte ---
        // KbImgUse aponta para a pasta de outro PID que traz a imagem.
        var imagePID = pid
        if let ref = ini.string("OPT", "KbImgUse") {
            imagePID = ref.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive).lowercased()
        }

        // --- Conjuntos de teclas (Gaming / Office) ---
        // `clrGaoshou` é "R,G,B" em decimal; o software oficial usa branco em
        // todos os modelos, mas o arquivo manda.
        let setColor: RKColor = {
            let parts = (ini.string("OPT", "clrGaoshou") ?? "").split(separator: ",")
                .compactMap { UInt8($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 3 else { return .white }
            return RKColor(r: parts[0], g: parts[1], b: parts[2])
        }()

        func vks(_ key: String) -> [VKCode] {
            (ini.string("OPT", key) ?? "").split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces), radix: 16) }
        }

        var keySets: [KeySet] = []
        // A ordem da RK: Key1 é o conjunto de jogo (Esc+WASD+setas), Key2 o de
        // escritório (atalhos, F-keys, navegação).
        for (iniKey, nome) in [("GaoshouKey1", "Jogo"), ("GaoshouKey2", "Escritório")] {
            let list = vks(iniKey)
            guard !list.isEmpty else { continue }
            keySets.append(KeySet(name: nome, vks: list, color: setColor))
        }

        return KeyboardConfig(
            pid: pid,
            name: catalog.name(pid: pid) ?? "RK \(pid.uppercased())",
            keys: keys,
            keyCount: ini.int("OPT", "LayoutKeyNum") ?? keys.count,
            lightingKind: kind,
            lightingModes: modes,
            imagePID: imagePID,
            usesLEDImage: ini.bool("OPT", "KeyUseLEDImg"),
            keySets: keySets
        )
    }

    /// PIDs que o catálogo conhece e para os quais existe KB.ini embutido.
    public func availablePIDs() -> [String] {
        catalog.devices.keys.filter { resources.kbIni(pid: $0) != nil }.sorted()
    }
}

/// Lê os nomes dos modos de iluminação do `led.xml` (UTF-16, tags por tipo).
enum LedXMLParser {
    static func modeNames(resources: RKResources, pid: String, kind: LightingKind) -> [Int: String] {
        let prefix: String
        let maxModes: Int
        switch kind {
        case .eft: prefix = "tc_eft"; maxModes = 19
        case .rgb: prefix = "tc_led_mode"; maxModes = 21
        case .backlit: prefix = "tc_led"; maxModes = 20
        case .none: return [:]
        }

        guard let url = resources.ledXML(pid: pid),
              let data = try? Data(contentsOf: url) else { return [:] }
        let xml = INIFile.decode(data)

        var result: [Int: String] = [:]
        for i in 1...maxModes {
            guard let value = element("\(prefix)\(i)", in: xml) else { continue }
            // Os arquivos usam '_' onde a interface original mostra espaço.
            result[i] = value.replacingOccurrences(of: "_", with: " ")
        }
        return result
    }

    /// Extração direta por tag. O led.xml é plano o bastante para não
    /// justificar um parser completo, e `tc_led1` x `tc_led_mode1` exigem
    /// casamento exato do nome da tag.
    private static func element(_ tag: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<\(tag)>"),
              let close = xml.range(of: "</\(tag)>", range: open.upperBound..<xml.endIndex) else { return nil }
        let value = xml[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
