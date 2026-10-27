//
//  Profile.swift
//  Perfil de configuração em disco. O teclado é write-only — não há como ler
//  o mapeamento atual do firmware —, então o perfil salvo é a única fonte da
//  verdade sobre o que está gravado.
//

import Foundation

public struct Profile: Codable, Sendable, Equatable {
    public var name: String
    /// bufferIndex da tecla -> VK de destino.
    public var remaps: [Int: VKCode]
    public var lighting: LightingSettings?
    /// bufferIndex -> cor, usado no modo Customize.
    public var perKeyColors: [Int: RKColor]
    public var updatedAt: Date

    public init(name: String = "Padrão",
                remaps: [Int: VKCode] = [:],
                lighting: LightingSettings? = nil,
                perKeyColors: [Int: RKColor] = [:],
                updatedAt: Date = Date()) {
        self.name = name
        self.remaps = remaps
        self.lighting = lighting
        self.perKeyColors = perKeyColors
        self.updatedAt = updatedAt
    }

    /// Converte os VKs do perfil nos firmware codes que o buffer exige,
    /// descartando destinos que o catálogo não sabe codificar.
    public func firmwareMappings() -> [Int: FirmwareCode] {
        var result: [Int: FirmwareCode] = [:]
        for (bufferIndex, vk) in remaps {
            guard let info = Keycode.info(vk: vk), info.fw != 0 else { continue }
            result[bufferIndex] = info.fw
        }
        return result
    }
}

public struct ProfileStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.directory = base.appendingPathComponent("RKG68Mac/profiles", isDirectory: true)
        }
    }

    private func url(for name: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        return directory.appendingPathComponent("\(safe).json")
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func save(_ profile: Profile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var copy = profile
        copy.updatedAt = Date()
        try encoder.encode(copy).write(to: url(for: profile.name), options: .atomic)
    }

    public func load(name: String) throws -> Profile {
        let data = try Data(contentsOf: url(for: name))
        return try decoder.decode(Profile.self, from: data)
    }

    public func loadIfExists(name: String) -> Profile? {
        try? load(name: name)
    }

    public func list() -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    public func delete(name: String) throws {
        try FileManager.default.removeItem(at: url(for: name))
    }
}
