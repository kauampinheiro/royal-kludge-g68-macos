//
//  INIFile.swift
//  Leitor de INI tolerante ao que a RK distribui: alguns arquivos são UTF-8,
//  outros UTF-16LE (com ou sem BOM), com comentários em `;` e chaves repetidas.
//

import Foundation

public struct INIFile: Sendable {
    /// Seções na ordem do arquivo; cada seção preserva a ordem das chaves.
    public private(set) var sections: [String: [(key: String, value: String)]] = [:]
    private var lookup: [String: [String: String]] = [:]

    public init(text: String) {
        var current = ""
        // `isNewline` é obrigatório aqui: em Swift "\r\n" é um único
        // Character, então comparar com "\n" não quebra arquivos CRLF.
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                current = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if sections[current] == nil { sections[current] = [] }
                continue
            }

            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            // Comentário no fim da linha só vale quando separado por espaço,
            // porque alguns valores legítimos contêm ';'.
            if let hit = value.range(of: " ;") {
                value = String(value[value.startIndex..<hit.lowerBound]).trimmingCharacters(in: .whitespaces)
            }

            sections[current, default: []].append((key: key, value: value))
            lookup[current, default: [:]][key.lowercased()] = value
        }
    }

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        self.init(text: INIFile.decode(data))
    }

    /// Decodifica UTF-8 ou UTF-16LE. A heurística de byte nulo cobre os
    /// arquivos UTF-16 sem BOM que o instalador da RK também traz.
    public static func decode(_ data: Data) -> String {
        if data.count >= 2 {
            if data[0] == 0xFF && data[1] == 0xFE {
                return String(decoding: data.dropFirst(2), as: UTF16.self)
            }
            if data[0] == 0xFE && data[1] == 0xFF {
                // UTF-16BE: raro, mas presente em alguns pacotes de idioma.
                let swapped = Data(stride(from: 2, to: data.count - 1, by: 2).flatMap { [data[$0 + 1], data[$0]] })
                return String(decoding: swapped, as: UTF16.self)
            }
            if data.count >= 4, data[1] == 0x00, data[3] == 0x00 {
                return String(decoding: data, as: UTF16.self)
            }
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    public func string(_ section: String, _ key: String) -> String? {
        lookup[section]?[key.lowercased()]
    }

    public func int(_ section: String, _ key: String) -> Int? {
        guard let raw = string(section, key) else { return nil }
        if raw.lowercased().hasPrefix("0x") { return Int(raw.dropFirst(2), radix: 16) }
        return Int(raw)
    }

    public func bool(_ section: String, _ key: String) -> Bool {
        string(section, key) == "1"
    }

    public func entries(_ section: String) -> [(key: String, value: String)] {
        sections[section] ?? []
    }
}

private extension String {
    init(decoding data: Data, as encoding: UTF16.Type) {
        var units: [UInt16] = []
        units.reserveCapacity(data.count / 2)
        let bytes = [UInt8](data)
        for i in stride(from: 0, to: bytes.count - 1, by: 2) {
            units.append(UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8))
        }
        self = String(decoding: units, as: UTF16.self)
    }

    init(decoding data: Data, as encoding: UTF8.Type) {
        self = String(decoding: [UInt8](data), as: UTF8.self)
    }
}
