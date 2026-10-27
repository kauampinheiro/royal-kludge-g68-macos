//
//  RKKeyboard.swift
//  Junta transporte HID, definição do modelo e perfil: é por aqui que a
//  interface (CLI ou app) fala com o teclado.
//

import Foundation

public final class RKKeyboard {
    public let transport: RKHIDTransport
    public let config: KeyboardConfig

    /// Correção de cor por canal da unidade física. Fica aqui, e não no
    /// `Codecs`, para o encoder continuar puro — é o que deixa o `selftest`
    /// comparar buffers byte a byte com a captura oficial.
    public var calibration: ColorCalibration

    public var info: RKHIDDeviceInfo { transport.info }

    public init(transport: RKHIDTransport, config: KeyboardConfig,
                calibration: ColorCalibration = .identity) {
        self.transport = transport
        self.config = config
        self.calibration = calibration
    }

    /// Abre o teclado conectado e carrega a definição correspondente ao PID.
    public static func connect(pid: String? = nil, resources: RKResources? = nil,
                               calibration: ColorCalibration? = nil) throws -> RKKeyboard {
        let resources = try resources ?? RKResources.bundled()
        let transport = try RKHIDTransport.open(pid: pid)
        let loader = try KeyboardConfigLoader(resources: resources)
        let config = try loader.load(pid: transport.info.pidString)
        return RKKeyboard(transport: transport, config: config,
                          calibration: calibration ?? CalibrationStore().load())
    }

    // MARK: - Remap

    /// Grava o conjunto de remaps. Sempre envia o perfil completo: o firmware
    /// substitui a tabela inteira a cada escrita.
    public func applyRemaps(_ mappings: [Int: FirmwareCode]) throws {
        let buffers = RemapCodec.encode(mappings: mappings, config: config)
        try transport.send(buffers: buffers)
    }

    /// Devolve o teclado ao layout de fábrica (nenhum remap).
    public func resetRemaps() throws {
        try applyRemaps([:])
    }

    // MARK: - Iluminação

    public func applyLighting(_ settings: LightingSettings) throws {
        guard config.hasLighting else { throw RKKeyboardError.lightingUnsupported(config.name) }
        var corrected = settings
        // Nos modos comuns a cor vai para o teclado inteiro, e é essa carga
        // que decide o ganho — medir o branco com uma tecla acesa e aplicar
        // com 68 foi o que fazia o branco virar ciano.
        corrected.color = calibration.apply(settings.color, litCount: config.keyCount)
        try transport.send(buffer: LightingCodec.encodeStandard(corrected))
    }

    public func applyPerKeyColors(_ colors: [Int: RKColor]) throws {
        guard config.isRGB else { throw RKKeyboardError.rgbUnsupported(config.name) }
        try transport.send(buffers: LightingCodec.encodePerKey(calibration.apply(colors)))
    }

    /// Cor sólida uniforme, desenhada pelo Customize em vez do Steady.
    ///
    /// O Steady manda **uma** cor para o firmware, que a repete em todos os
    /// LEDs — e aí o desvio por posição aparece: no G68 a região das setas sai
    /// rosada enquanto o resto está branco. Pintando tecla por tecla, cada uma
    /// recebe a sua correção e a cor sai igual no teclado inteiro.
    ///
    /// Custo: ocupa a tabela de cor por tecla, que passa a ser a cor sólida.
    @discardableResult
    public func applyUniform(_ color: RKColor, brightness: Int = 5,
                             speed: Int = 3, sleep: Int = 5) throws -> [Int: RKColor] {
        guard config.isRGB, let custom = config.customColorMode else {
            throw RKKeyboardError.rgbUnsupported(config.name)
        }
        var colors: [Int: RKColor] = [:]
        for key in config.keys { colors[key.bufferIndex] = color }

        try applyLighting(LightingSettings(modeIndex: custom.index, speed: speed,
                                           brightness: brightness, color: color,
                                           randomColor: false, sleep: sleep))
        try applyPerKeyColors(colors)
        return colors
    }

    // MARK: - Perfil

    /// Aplica o perfil inteiro numa transação só, na ordem exata do Rangoli:
    /// iluminação → cor por tecla (se o modo for o de cor própria) → mapa de
    /// teclas, este último **sempre**, mesmo sem remap nenhum.
    ///
    /// Mandar comando solto deixa o firmware com a parte de LED dessincronizada
    /// da parte de teclas — foi o que aconteceu num G68 real: quatro teclas
    /// pararam de acender em qualquer efeito, embora os LEDs respondessem ao
    /// toque.
    public func apply(_ profile: Profile) throws {
        if let lighting = profile.lighting, config.hasLighting {
            try applyLighting(lighting)

            if !profile.perKeyColors.isEmpty,
               config.isRGB,
               let custom = config.customColorMode,
               custom.index == lighting.modeIndex {
                try applyPerKeyColors(profile.perKeyColors)
            }
        }

        try applyRemaps(profile.firmwareMappings())
    }

    /// Restauração de fábrica: o comando de reset do firmware seguido do mapa
    /// de teclas original, exatamente como o software oficial envia.
    public func factoryReset(trailingC0: Bool = false) throws {
        try transport.send(buffer: LightingCodec.encodeFactoryReset(trailingC0: trailingC0))
        try applyRemaps([:])
    }

    /// Reescreve o estado inteiro do teclado a partir do zero: layout de
    /// fábrica, modo de iluminação pedido e nenhuma cor por tecla. É a saída
    /// quando o firmware fica num estado estranho.
    public func resync(lighting: LightingSettings? = nil) throws {
        let settings = lighting ?? LightingSettings(
            modeIndex: config.lightingModes.first?.index ?? 1,
            speed: 3, brightness: 5, color: .white, randomColor: false, sleep: 5)

        if config.hasLighting {
            try applyLighting(settings)
        }
        if config.isRGB, let custom = config.customColorMode {
            // Reescreve o buffer de cor por tecla inteiro em branco, para não
            // deixar preto gravado de alguma tentativa anterior.
            try applyLighting(LightingSettings(modeIndex: custom.index, speed: settings.speed,
                                               brightness: settings.brightness, color: .white,
                                               randomColor: false, sleep: settings.sleep))
            var all: [Int: RKColor] = [:]
            for index in 0...LightingCodec.maxPerKeyIndex { all[index] = .white }
            try applyPerKeyColors(all)
            try applyLighting(settings)
        }

        try applyRemaps([:])
    }
}

public enum RKKeyboardError: Error, LocalizedError {
    case lightingUnsupported(String)
    case rgbUnsupported(String)
    case unknownKey(String)
    case unknownTarget(String)

    public var errorDescription: String? {
        switch self {
        case .lightingUnsupported(let name):
            return "O \(name) não declara modos de iluminação configuráveis."
        case .rgbUnsupported(let name):
            return "O \(name) não é RGB: não aceita cor por tecla."
        case .unknownKey(let name):
            return "Tecla não encontrada no layout: \(name)"
        case .unknownTarget(let name):
            return "Função de destino desconhecida: \(name)"
        }
    }
}
