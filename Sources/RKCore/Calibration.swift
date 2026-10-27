//
//  Calibration.swift
//  Correção de cor por canal, aplicada antes de a cor virar bytes.
//
//  O teclado recebe RGB cru e aciona cada canal com o mesmo PWM, mas os três
//  LEDs não rendem igual: no G68 o verde é o mais fraco, então `#FFFFFF`
//  (255,255,255) sai rosado. Nenhum ajuste de brilho conserta isso — brilho
//  mexe nos três ao mesmo tempo e mantém a proporção errada.
//
//  A correção é um ganho por canal, sempre ≤ 1: só dá para *abaixar* os canais
//  fortes até o mais fraco alcançar, nunca empurrar além de 255. Branco
//  calibrado, portanto, acende um pouco menos que branco cru — é o preço de
//  ser branco de verdade.
//
//  **O ganho não é constante: depende de quantos LEDs estão acesos.** Medido no
//  G68 em 09/10/2026, com o verde fixo em 255 e o branco julgado a olho:
//
//      LEDs acesos    vermelho neutro    ganho
//                1                 28    0.110
//               15                ~46    0.180
//               68                 64    0.251
//
//  Ou seja: com uma tecla acesa o vermelho domina e tem de cair a um décimo;
//  com o teclado cheio o mesmo byte vira ciano, porque o vermelho perde força
//  quando a corrente é dividida entre todos os LEDs. Um ganho único não serve
//  para os dois casos — foi por isso que nenhum ajuste fechou o branco antes.
//
//  Os três pontos caem numa lei de potência `ganho = base × n^k` com k ≈ 0.19
//  (0.183 do 1º ao 2º ponto, 0.196 do 1º ao 3º), que prevê 46.8 para 15 LEDs —
//  o ponto intermediário medido. Verde e azul não mostraram dependência de
//  carga: o azul fechou em 72/255 nas duas pontas.
//
//  Nem Rangoli nem Kludge Knight modelam isso; os dois mandam a cor crua.
//
//  Isto é propriedade da unidade física, não do perfil: fica num arquivo
//  próprio e vale para todos os perfis.
//

import Foundation

/// Multiplicador por canal, aplicado sobre o ganho. Serve para corrigir uma
/// tecla ou uma região que foge do resto.
public struct ChannelScale: Codable, Sendable, Equatable {
    public var r: Double
    public var g: Double
    public var b: Double

    public static let neutral = ChannelScale(r: 1, g: 1, b: 1)

    public init(r: Double = 1, g: Double = 1, b: Double = 1) {
        self.r = min(max(r, 0), 1)
        self.g = min(max(g, 0), 1)
        self.b = min(max(b, 0), 1)
    }

    public var isNeutral: Bool { self == .neutral }

    public var summary: String {
        var parts: [String] = []
        if r != 1 { parts.append(String(format: "R %.2f×", r)) }
        if g != 1 { parts.append(String(format: "G %.2f×", g)) }
        if b != 1 { parts.append(String(format: "B %.2f×", b)) }
        return parts.isEmpty ? "neutro" : parts.joined(separator: " ")
    }
}

public struct ColorCalibration: Codable, Sendable, Equatable {
    /// Ganho por canal, 0…1. 1 = canal intocado.
    public var r: Double
    public var g: Double
    public var b: Double

    /// Gama aplicada antes do ganho. 1 = linear (o que o firmware faz).
    /// Valores > 1 escurecem os tons médios; serve para gradientes e para a
    /// cor por tecla parecerem mais próximos do que a tela mostra.
    public var gamma: Double

    /// Expoente da resposta à carga, por canal. O ganho efetivo com `n` LEDs
    /// acesos é `base × n^expoente`, limitado a 1. Zero = ganho fixo, que é o
    /// comportamento de antes desta medição.
    public var loadExponentR: Double
    public var loadExponentG: Double
    public var loadExponentB: Double

    /// Correção por posição: fator por índice de buffer, sobre o ganho do canal.
    ///
    /// O desvio de cor não é só função da carga, é também da **posição**. Medido
    /// no G68 em 09/10/2026: com o teclado inteiro no branco calibrado, a região
    /// das setas puxava para o rosa, e casou com o resto levando o vermelho a
    /// `0.76×`.
    ///
    /// Mesma causa do efeito de carga, outro eixo: o LED vermelho tem tensão
    /// direta de ~2.0 V contra ~3.0 V do verde e do azul. Onde o trilho perde
    /// tensão — e perde mais longe do ponto de injeção — o vermelho é o que
    /// continua acendendo com folga. Por isso os cantos ficam rosados.
    ///
    /// Só vale onde existe tabela de cor por tecla: nos modos comuns o firmware
    /// recebe **uma** cor para todos os LEDs e não há onde aplicar a correção.
    /// A saída é desenhar cor sólida pelo Customize — ver `RKKeyboard.applyUniform`.
    public var keyScale: [Int: ChannelScale]

    public static let identity = ColorCalibration(r: 1, g: 1, b: 1, gamma: 1)

    /// Medido no G68 do usuário em 09/10/2026 — ponto de branco a olho em três
    /// níveis de carga (ver o cabeçalho). Substitui o palpite que vigorava
    /// antes (`R 0.70 · B 0.80`), que errava o vermelho por seis vezes.
    public static let g68Measured = ColorCalibration(
        r: 0.110, g: 1.0, b: 0.282, gamma: 1, loadExponentR: 0.19)

    /// Nome antigo, mantido para não quebrar quem chamava.
    @available(*, deprecated, renamed: "g68Measured")
    public static let g68Starting = g68Measured

    public init(r: Double = 1, g: Double = 1, b: Double = 1, gamma: Double = 1,
                loadExponentR: Double = 0, loadExponentG: Double = 0,
                loadExponentB: Double = 0, keyScale: [Int: ChannelScale] = [:]) {
        self.r = Self.clampGain(r)
        self.g = Self.clampGain(g)
        self.b = Self.clampGain(b)
        self.gamma = min(max(gamma, 0.4), 3.0)
        self.loadExponentR = Self.clampExponent(loadExponentR)
        self.loadExponentG = Self.clampExponent(loadExponentG)
        self.loadExponentB = Self.clampExponent(loadExponentB)
        self.keyScale = keyScale.filter { !$0.value.isNeutral }
    }

    /// Arquivos gravados antes da medição de carga não têm os expoentes, e o
    /// decodificador sintetizado falharia na chave ausente.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(r: try c.decodeIfPresent(Double.self, forKey: .r) ?? 1,
                  g: try c.decodeIfPresent(Double.self, forKey: .g) ?? 1,
                  b: try c.decodeIfPresent(Double.self, forKey: .b) ?? 1,
                  gamma: try c.decodeIfPresent(Double.self, forKey: .gamma) ?? 1,
                  loadExponentR: try c.decodeIfPresent(Double.self, forKey: .loadExponentR) ?? 0,
                  loadExponentG: try c.decodeIfPresent(Double.self, forKey: .loadExponentG) ?? 0,
                  loadExponentB: try c.decodeIfPresent(Double.self, forKey: .loadExponentB) ?? 0,
                  keyScale: try c.decodeIfPresent([Int: ChannelScale].self, forKey: .keyScale) ?? [:])
    }

    private static func clampGain(_ v: Double) -> Double { min(max(v, 0), 1) }
    private static func clampExponent(_ v: Double) -> Double { min(max(v, 0), 1) }

    public var isIdentity: Bool { self == .identity }

    /// Tem correção por posição?
    public var hasKeyScale: Bool { !keyScale.isEmpty }

    /// Depende da carga? Se não, o `litCount` é irrelevante e dá para pular o
    /// cálculo.
    public var isLoadDependent: Bool {
        loadExponentR != 0 || loadExponentG != 0 || loadExponentB != 0
    }

    /// Ganho efetivo dos três canais com `litCount` LEDs acesos.
    public func gains(litCount: Int) -> (r: Double, g: Double, b: Double) {
        let n = Double(max(litCount, 1))
        func scaled(_ base: Double, _ exponent: Double) -> Double {
            exponent == 0 ? base : min(base * pow(n, exponent), 1)
        }
        return (scaled(r, loadExponentR), scaled(g, loadExponentG), scaled(b, loadExponentB))
    }

    /// Aplica gama e ganho a um canal.
    private func channel(_ value: UInt8, gain: Double) -> UInt8 {
        guard value > 0 else { return 0 }
        let normalized = Double(value) / 255
        let corrected = (gamma == 1 ? normalized : pow(normalized, gamma)) * gain
        // Arredondar para cima o que não for zero: um canal pedido acima de
        // zero não pode sumir por arredondamento, senão matizes escuros viram
        // preto.
        let scaled = corrected * 255
        return UInt8(min(255, max(1, scaled.rounded())))
    }

    /// `litCount` é quantos LEDs o teclado vai acender com essa cor. Nos modos
    /// comuns é o teclado todo; na cor por tecla, só as teclas pintadas.
    /// `scale` é a correção da posição, quando a cor vai para uma tecla sabida.
    public func apply(_ color: RKColor, litCount: Int = 1,
                      scale: ChannelScale = .neutral) -> RKColor {
        guard !isIdentity || !scale.isNeutral else { return color }
        let gain = gains(litCount: litCount)
        return RKColor(r: channel(color.r, gain: gain.r * scale.r),
                       g: channel(color.g, gain: gain.g * scale.g),
                       b: channel(color.b, gain: gain.b * scale.b))
    }

    /// A carga sai da própria tabela: só as teclas com cor acendem. Aqui cada
    /// tecla tem endereço, então é o único caminho em que a correção por
    /// posição pode ser aplicada.
    public func apply(_ colors: [Int: RKColor]) -> [Int: RKColor] {
        guard !isIdentity || hasKeyScale else { return colors }
        let lit = colors.values.filter { $0 != .black }.count
        return colors.reduce(into: [:]) { out, pair in
            out[pair.key] = apply(pair.value, litCount: lit,
                                  scale: keyScale[pair.key] ?? .neutral)
        }
    }

    /// Como aparece no CLI e no app.
    public var summary: String {
        let gains = String(format: "R %.2f · G %.2f · B %.2f", r, g, b)
        var parts = [gains]
        if gamma != 1 { parts.append(String(format: "gama %.2f", gamma)) }
        if isLoadDependent {
            var exps: [String] = []
            if loadExponentR != 0 { exps.append(String(format: "R^%.2f", loadExponentR)) }
            if loadExponentG != 0 { exps.append(String(format: "G^%.2f", loadExponentG)) }
            if loadExponentB != 0 { exps.append(String(format: "B^%.2f", loadExponentB)) }
            parts.append("carga " + exps.joined(separator: " "))
        }
        if hasKeyScale { parts.append("\(keyScale.count) tecla(s) corrigida(s)") }
        return parts.joined(separator: " · ")
    }
}

public struct CalibrationStore: Sendable {
    public let url: URL

    public init(directory: URL? = nil) {
        let base = directory ?? {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            return support.appendingPathComponent("RKG68Mac", isDirectory: true)
        }()
        self.url = base.appendingPathComponent("calibration.json")
    }

    public func load() -> ColorCalibration {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(ColorCalibration.self, from: data) else {
            return .identity
        }
        return value
    }

    public func save(_ calibration: ColorCalibration) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(calibration).write(to: url, options: .atomic)
    }
}
