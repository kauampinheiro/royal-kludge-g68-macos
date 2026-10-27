//
//  SelfTest.swift
//  Vetores fixos do protocolo, verificados pelo próprio binário.
//
//  Vive aqui — e não em Tests/ — porque XCTest e swift-testing só existem
//  com o Xcode completo instalado; o self-test roda em qualquer máquina com
//  as Command Line Tools.
//

import Foundation
import RKCore

struct SelfTest {
    private var failures: [String] = []
    private var passed = 0

    private mutating func check(_ label: String, _ condition: @autoclosure () throws -> Bool) {
        do {
            if try condition() {
                passed += 1
            } else {
                failures.append(label)
            }
        } catch {
            failures.append("\(label) — lançou: \(error)")
        }
    }

    private mutating func equal<T: Equatable>(_ label: String, _ lhs: @autoclosure () throws -> T, _ rhs: T) {
        do {
            let value = try lhs()
            if value == rhs {
                passed += 1
            } else {
                failures.append("\(label) — esperado \(rhs), obtido \(value)")
            }
        } catch {
            failures.append("\(label) — lançou: \(error)")
        }
    }

    /// Retorna true se tudo passou.
    static func run() -> Bool {
        var t = SelfTest()
        do {
            let loader = try KeyboardConfigLoader(resources: try RKResources.bundled())
            let config = try loader.load(pid: "013a")

            // --- Definição do modelo ---
            t.equal("catálogo: nome do PID 013A", config.name, "RKG68 RGB N Wired Keyboard")
            t.equal("layout: teclas declaradas", config.keyCount, 68)
            t.equal("iluminação: tipo", config.lightingKind, .rgb)
            t.equal("iluminação: modos", config.lightingModes.count, 21)
            t.equal("iluminação: modo de cor por tecla", config.customColorMode?.index, 14)
            t.equal("iluminação: nome do modo 17", config.lightingModes.first { $0.index == 17 }?.name, "Steady")

            // --- Conjuntos de teclas (Gaming / Office da RK) ---
            // Vêm do KB.ini em VK do Windows e precisam cair nos índices
            // certos do layout, senão o preset acende a tecla errada.
            t.equal("conjuntos: quantidade", config.keySets.count, 2)
            let jogo = config.keySets.first
            t.equal("conjuntos: nome do primeiro", jogo?.name, "Jogo")
            t.equal("conjuntos: cor (clrGaoshou)", jogo?.color, .white)
            if let jogo {
                let colors = config.perKeyColors(for: jogo)
                // Esc + WASD + 4 setas = 9 teclas, todas presentes num G68.
                t.equal("conjunto Jogo: teclas resolvidas", colors.count, 9)
                t.equal("conjunto Jogo: Esc é o índice 1", colors[1], .white)
                t.equal("conjunto Jogo: W é o índice 14", colors[14], .white)
                t.equal("conjunto Jogo: ← é o índice 83", colors[83], .white)
                t.equal("conjunto Jogo: não pinta o Espaço", colors[35], nil)
            }
            if let escritorio = config.keySets.last, escritorio.name == "Escritório" {
                let colors = config.perKeyColors(for: escritorio)
                // A lista da RK vale para a família toda e cita teclas que um
                // layout de 68 não tem (PrtSc, Home, End) — devem ser
                // descartadas em silêncio, não viram índice inventado.
                t.equal("conjunto Escritório: VKs declarados", escritorio.vks.count, 27)
                t.equal("conjunto Escritório: teclas deste layout", colors.count, 24)
                t.equal("conjunto Escritório: Espaço é o índice 35", colors[35], .white)
                // Modificador genérico da RK tem de virar as duas teclas físicas.
                t.equal("conjunto Escritório: Shift esquerdo (4)", colors[4], .white)
                t.equal("conjunto Escritório: Shift direito (70)", colors[70], .white)
                t.equal("conjunto Escritório: F1 não existe no G68", colors[0], nil)
            }

            // --- Remap ---
            let caps = KeyNames.physicalKey("caps", in: config)
            t.equal("layout: Caps Lock no índice 3", caps?.bufferIndex, 3)
            let esc = KeyNames.target("esc")
            t.equal("keycode: Esc = 0x2900", esc?.fw, 0x2900)

            let buffers = RemapCodec.encode(mappings: [caps!.bufferIndex: esc!.fw], config: config)
            t.equal("remap: 9 buffers", buffers.count, 9)
            t.check("remap: todos com 65 bytes", buffers.allSatisfy { $0.count == 65 })
            t.equal("remap: cabeçalho do buffer 1", Array(buffers[0][0..<5]), [0x0A, 0x09, 0x01, 0x01, 0xF8])
            t.equal("remap: cabeçalho do buffer 5", Array(buffers[4][0..<3]), [0x0A, 0x09, 0x05])
            // Caps (índice 3) ocupa flat[12..15]; dados do buffer 1 começam no byte 5.
            t.equal("remap: Caps virou Esc em 5+12", Array(buffers[0][17..<21]), [0x00, 0x00, 0x29, 0x00])
            t.equal("remap: Esc original intocado em 5+4", Array(buffers[0][9..<13]), [0x00, 0x00, 0x29, 0x00])
            t.equal("remap: Shift esquerdo mantém bitflag", Array(buffers[0][21..<25]), [0x00, 0x02, 0x00, 0x00])

            let defaults = RemapCodec.encode(mappings: [:], config: config)
            if let q = config.keys.first(where: { $0.keyInfo.label == "Q" }) {
                let offset = 5 + q.bufferIndex * 4
                t.equal("remap: sem mapeamento, Q = 0x1400",
                        Array(defaults[0][offset..<(offset + 4)]), [0x00, 0x00, 0x14, 0x00])
            } else {
                t.check("remap: tecla Q existe no layout", false)
            }

            // --- Iluminação ---
            let lighting = LightingSettings(modeIndex: 17, speed: 3, brightness: 5,
                                            color: RKColor(hex: "#FF6600")!, randomColor: false, sleep: 5)
            let lightBuffer = LightingCodec.encodeStandard(lighting)
            t.equal("luz: buffer de 65 bytes", lightBuffer.count, 65)
            t.equal("luz: cabeçalho e parâmetros", Array(lightBuffer[0..<14]),
                    [0x0A, 0x01, 0x01, 0x02, 0x29, 17, 0x00, 3, 5, 0xFF, 0x66, 0x00, 0x00, 5])

            let random = LightingCodec.encodeStandard(
                LightingSettings(modeIndex: 2, color: .white, randomColor: true))
            t.equal("luz: aleatória zera a cor e liga a flag", Array(random[9..<13]), [0x00, 0x00, 0x00, 0x01])

            // --- Cor por tecla ---
            let a = KeyNames.physicalKey("a", in: config)
            t.equal("layout: tecla A no índice 9", a?.bufferIndex, 9)
            let perKey = LightingCodec.encodePerKey([a!.bufferIndex: RKColor(r: 255, g: 0, b: 0)])
            t.equal("cor por tecla: 7 buffers", perKey.count, 7)
            t.equal("cor por tecla: cabeçalho do buffer 1", Array(perKey[0][0..<6]), [0x0A, 0x07, 0x01, 0x03, 0x7E, 0x01])
            t.equal("cor por tecla: A vermelha em 6+27", Array(perKey[0][33..<36]), [0xFF, 0x00, 0x00])

            // --- Nomes de tecla ---
            t.equal("alias: cmd -> VK de Win", KeyNames.target("cmd")?.vk, 0x5B)
            t.equal("alias: option -> VK de Alt", KeyNames.target("option")?.vk, 0xA4)
            t.equal("alias: volup -> consumer control", KeyNames.target("volup")?.fw, 0x010000E9)
            t.equal("alias: f5", KeyNames.target("f5")?.fw, 0x3E00)
            t.check("alias: nome inexistente não resolve", KeyNames.target("inexistente") == nil)

            // --- Leitura de INI ---
            // CRLF + UTF-16LE é o formato real dos arquivos da RK; em Swift
            // "\r\n" é um Character único, o que já quebrou o parser uma vez.
            let utf16 = Data([0xFF, 0xFE] + "[OPT]\r\nRGBKb=1\r\nLayoutKeyNum=68\r\n"
                .utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
            let ini = INIFile(text: INIFile.decode(utf16))
            t.check("ini: UTF-16 + CRLF lê RGBKb", ini.bool("OPT", "RGBKb"))
            t.equal("ini: UTF-16 + CRLF lê LayoutKeyNum", ini.int("OPT", "LayoutKeyNum"), 68)

            // --- Perfil ---
            var profile = Profile(name: "selftest", remaps: [3: 0x1B])
            profile.lighting = LightingSettings(modeIndex: 14, color: RKColor(hex: "#00FF00")!)
            profile.perKeyColors = [9: RKColor(r: 1, g: 2, b: 3)]
            t.equal("perfil: VK traduzido em firmware code", profile.firmwareMappings(), [3: 0x2900])

            let data = try JSONEncoder().encode(profile)
            let decoded = try JSONDecoder().decode(Profile.self, from: data)
            t.equal("perfil: remaps sobrevivem ao JSON", decoded.remaps, profile.remaps)
            t.equal("perfil: luz sobrevive ao JSON", decoded.lighting, profile.lighting)
            t.equal("perfil: cores sobrevivem ao JSON", decoded.perKeyColors, profile.perKeyColors)

            // --- Cor ---
            t.equal("cor: #RRGGBB para componentes", RKColor(hex: "#1A2B3C"),
                    RKColor(r: 0x1A, g: 0x2B, b: 0x3C))
            t.equal("cor: ida e volta em hex", RKColor(r: 0, g: 128, b: 255).hex, "#0080FF")
            t.check("cor: hex inválido é rejeitado", RKColor(hex: "#12345") == nil)
        } catch {
            t.failures.append("falha ao carregar as definições: \(error)")
        }

        if t.failures.isEmpty {
            print("✔ \(t.passed) verificações passaram")
            return true
        }
        print("✖ \(t.failures.count) falha(s) de \(t.passed + t.failures.count):")
        for failure in t.failures { print("   · \(failure)") }
        return false
    }
}
