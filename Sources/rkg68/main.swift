//
//  rkg68 — CLI de configuração do Royal Kludge G68 no macOS.
//
//  Fase 1 do projeto: valida o canal HID e já entrega remap, iluminação e
//  cor por tecla. A interface gráfica usa o mesmo RKCore.
//

import Foundation
import RKCore

let usage = """
rkg68 — configurador do Royal Kludge G68 para macOS

USO
  rkg68 scan                            Lista teclados RK e suas interfaces HID
  rkg68 info                            Mostra o modelo detectado, teclas e modos de luz
  rkg68 keys [filtro]                   Lista as teclas do layout (e seus índices)
  rkg68 targets [filtro]                Lista as funções atribuíveis a uma tecla
  rkg68 remap <tecla>=<função> ...      Grava remaps no teclado
  rkg68 reset-remap                     Devolve o layout de fábrica
  rkg68 resync [modo]                   Reescreve TUDO do zero (luz + cores + mapa de teclas)
  rkg68 factory-reset [--tail-c0]       Restauração de fábrica do firmware
  rkg68 read [id...]                    Lê feature reports do teclado (diagnóstico)
  rkg68 led <modo> [opções]             Define o modo de iluminação
  rkg68 perkey <tecla>=<#RRGGBB> ...    Cor por tecla (modo Customize)
  rkg68 perkey --fill <#RRGGBB>         Pinta todo o espaço de índices (diagnóstico)
  rkg68 profile list|show|apply|delete  Perfis salvos em disco
  rkg68 keyset [jogo|escritorio]        Acende só o conjunto de teclas da RK
  rkg68 palette list|add|remove|apply   Cores validadas a olho (presets)
  rkg68 palette test <cores…> [--rows]  Acende candidatos para você julgar
  rkg68 solid <#RRGGBB|@nome>           Cor sólida uniforme (corrige por posição)
  rkg68 calibrate [opções]              Ajusta o branco do teclado (ganho por canal)
  rkg68 dump-buffers <subcomando>       Mostra os bytes que seriam enviados (não escreve nada)
  rkg68 selftest                        Verifica os vetores do protocolo (sem tocar no teclado)

OPÇÕES
  --pid <hex>          Força um PID (quando há mais de um RK conectado)
  --profile <nome>     Perfil a usar/gravar (padrão: "Padrão")
  --no-save            Não grava o resultado no perfil
  --speed <1-5>        Velocidade da animação
  --brightness <1-5>   Brilho
  --color <#RRGGBB>    Cor fixa
  --random             Cores aleatórias
  --sleep <1-5>        1=5min 2=10min 3=20min 4=30min 5=nunca
  --raw                Envia a cor sem o ganho por canal da calibração

CALIBRAÇÃO (rkg68 calibrate)
  --r/--g/--b <0-1>    Ganho do canal (1 = intocado). Só abaixa, nunca sobe.
  --gamma <0.4-3>      Gama antes do ganho (1 = linear, como o firmware)
  --white              Acende branco sólido com a calibração atual, para olhar
  --load-r/-g/-b <0-1> Expoente de carga: ganho = base × (LEDs acesos)^expoente
  --keys <lista>       Teclas a corrigir por posição (rótulos ou #índice)
  --key-r/-g/-b <0-1>  Fator dessas teclas sobre o ganho do canal
  --keys-reset         Apaga todas as correções por posição
  --preset             Aplica a calibração medida no G68 (R .11 G 1 B .28, carga R^.19)
  --reset              Volta a enviar a cor crua

EXEMPLOS
  rkg68 remap caps=esc
  rkg68 remap lwin=lalt lalt=lwin        # troca ⌘ e ⌥ no layout Windows
  rkg68 led 17 --color '#FF6600' --brightness 5
  rkg68 led Customize && rkg68 perkey a=#FF0000 s=#00FF00
  rkg68 palette test '#FF8000' '#FF9000' '#FFA000' --rows
  rkg68 palette add laranja '#FF9000' --lit 68 --note 'laranja de verdade'
  rkg68 led 17 --color @laranja          # preset: byte cru, sem calibração
  rkg68 calibrate --white                # branco atual: está rosado?
  rkg68 calibrate --r 0.7 --b 0.8 --white  # puxa vermelho e azul e mostra
"""

// MARK: - Argumentos

struct Args {
    var command: String = ""
    var positionals: [String] = []
    var flags: [String: String] = [:]
    var booleans: Set<String> = []

    init(_ raw: [String]) {
        var items = raw
        if let first = items.first, !first.hasPrefix("-") {
            command = first
            items.removeFirst()
        }
        var i = 0
        while i < items.count {
            let item = items[i]
            if item.hasPrefix("--") {
                let name = String(item.dropFirst(2))
                if i + 1 < items.count, !items[i + 1].hasPrefix("--") {
                    flags[name] = items[i + 1]
                    i += 2
                } else {
                    booleans.insert(name)
                    i += 1
                }
            } else {
                positionals.append(item)
                i += 1
            }
        }
    }

    func int(_ name: String) -> Int? { flags[name].flatMap(Int.init) }
    func has(_ name: String) -> Bool { booleans.contains(name) }
}

let args = Args(Array(CommandLine.arguments.dropFirst()))

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("erro: " + message + "\n").utf8))
    exit(1)
}

func describe(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}

// MARK: - Helpers

let profileName = args.flags["profile"] ?? "Padrão"
let store = ProfileStore()


func loadResources() -> RKResources {
    do { return try RKResources.bundled() } catch { fail(describe(error)) }
}

func connect() -> RKKeyboard {
    do {
        let keyboard = try RKKeyboard.connect(pid: args.flags["pid"], resources: loadResources())
        // `--raw` manda a cor como ela foi escrita, sem o ganho por canal.
        // É o que permite catalogar o que o teclado realmente acende: uma cor
        // validada a olho tem de ser reproduzível byte a byte, independente de
        // a calibração mudar depois.
        if args.has("raw") { keyboard.calibration = .identity }
        return keyboard
    } catch {
        fail(describe(error))
    }
}

/// Modelo sem exigir hardware conectado — usado por `keys`, `dump-buffers`
/// e pelos comandos de perfil.
func offlineConfig() -> KeyboardConfig {
    let resources = loadResources()
    do {
        let loader = try KeyboardConfigLoader(resources: resources)
        if let pid = args.flags["pid"] {
            return try loader.load(pid: pid)
        }
        if let found = RKHIDTransport.discoverConfigurationInterfaces().first {
            return try loader.load(pid: found.info.pidString)
        }
        // 013A é o G68 RGB com fio: o padrão quando nada está conectado.
        return try loader.load(pid: "013a")
    } catch {
        fail(describe(error))
    }
}

func currentProfile() -> Profile {
    store.loadIfExists(name: profileName) ?? Profile(name: profileName)
}

func saveIfWanted(_ profile: Profile) {
    guard !args.has("no-save") else { return }
    do {
        try store.save(profile)
        print("perfil \"\(profile.name)\" salvo em \(store.directory.path)")
    } catch {
        FileHandle.standardError.write(Data("aviso: não foi possível salvar o perfil: \(describe(error))\n".utf8))
    }
}

func hexDump(_ buffers: [[UInt8]]) {
    for (i, buffer) in buffers.enumerated() {
        print("buffer \(i + 1)/\(buffers.count):")
        for chunk in stride(from: 0, to: buffer.count, by: 16) {
            let slice = buffer[chunk..<min(chunk + 16, buffer.count)]
            let hex = slice.map { String(format: "%02x", $0) }.joined(separator: " ")
            print(String(format: "  %04x  %@", chunk, hex))
        }
    }
}

// MARK: - Comandos

func cmdScan() {
    let all = RKHIDTransport.discoverAll()
    guard !all.isEmpty else {
        print("Nenhum teclado Royal Kludge (VID 0x258A) no barramento.")
        print("Conecte pelo cabo USB — 2.4G e Bluetooth não expõem o canal de configuração.")
        return
    }
    print("Teclados Royal Kludge encontrados (VID 0x258A):\n")
    for (_, info) in all {
        let mark = info.isConfigurationInterface ? "✦ CONFIGURAÇÃO" : "  (entrada)"
        print("\(mark)  PID 0x\(info.pidString.uppercased())  \(info.product ?? "sem nome")")
        print("           usage page 0x\(String(format: "%02X", info.primaryUsagePage)) / usage 0x\(String(format: "%02X", info.primaryUsage))"
              + "  ·  feature report máx: \(info.maxFeatureReportSize) bytes"
              + "  ·  transporte: \(info.transport ?? "?")")
        if let serial = info.serialNumber { print("           serial: \(serial)") }
    }
    let configurable = all.filter { $0.info.isConfigurationInterface }
    print("")
    if configurable.isEmpty {
        print("Nenhuma interface de configuração (usage page 0x01 / usage 0x80) exposta.")
    } else {
        print("\(configurable.count) interface(s) de configuração pronta(s) para receber comandos.")
    }

    // A descoberta acima funciona sem autorização nenhuma; abrir o dispositivo
    // não. Dizer isso aqui separa "teclado não apareceu" de "o macOS barrou".
    switch RKHIDTransport.access {
    case .granted:
        break
    case .notAsked:
        print("\nMonitoramento de Entrada: ainda não autorizado para este processo.")
        print("Na primeira escrita o macOS vai pedir a autorização do terminal.")
    case .denied:
        print("\nMonitoramento de Entrada: NEGADO — nenhuma escrita vai funcionar.")
        print("Autorize o terminal em Ajustes do Sistema › Privacidade e Segurança"
              + " › Monitoramento de Entrada.")
    }
}

func cmdInfo() {
    let keyboard = connect()
    let config = keyboard.config
    print("Modelo:      \(config.name)")
    print("PID:         0x\(config.pid.uppercased())")
    print("Produto HID: \(keyboard.info.product ?? "?")")
    print("Teclas:      \(config.keys.count) mapeadas (layout declara \(config.keyCount))")
    print("Iluminação:  \(config.lightingKind.rawValue)\(config.isRGB ? " (RGB)" : "")")
    if config.hasLighting {
        print("Modos:")
        for mode in config.lightingModes {
            var controls: [String] = []
            if mode.flags.speed { controls.append("velocidade") }
            if mode.flags.brightness { controls.append("brilho") }
            if mode.flags.colorPicker { controls.append("cor") }
            if mode.flags.random { controls.append("aleatório") }
            if mode.flags.direction > 0 { controls.append("direção(\(mode.flags.direction))") }
            let suffix = controls.isEmpty ? "sem controles" : controls.joined(separator: ", ")
            let custom = config.customColorMode?.index == mode.index ? "  ← cor por tecla" : ""
            print(String(format: "  %2d  %-24@ %@%@", mode.index, mode.name as NSString, suffix, custom))
        }
    }
    if let profile = store.loadIfExists(name: profileName) {
        print("\nPerfil \"\(profileName)\": \(profile.remaps.count) remap(s), "
              + "luz \(profile.lighting.map { "modo \($0.modeIndex)" } ?? "não definida"), "
              + "\(profile.perKeyColors.count) cor(es) por tecla")
    }
}

func cmdKeys() {
    let config = offlineConfig()
    let filter = args.positionals.first?.lowercased()
    print("Teclas do \(config.name) — use o rótulo ou #índice no remap:\n")
    for key in config.keys {
        let label = key.keyInfo.displayLabel
        if let filter, !label.lowercased().contains(filter), !key.iniKey.lowercased().contains(filter) { continue }
        print(String(format: "  #%-4d %-22@ VK 0x%02X  fw 0x%06X  (%@)",
                     key.bufferIndex, label as NSString, key.keyInfo.vk, key.keyInfo.fw, key.iniKey as NSString))
    }
}

func cmdTargets() {
    let filter = args.positionals.first?.lowercased()
    for (category, keys) in Keycode.assignableKeys() {
        let shown = keys.filter { key in
            guard let filter else { return true }
            return key.displayLabel.lowercased().contains(filter) || key.label.lowercased().contains(filter)
        }
        guard !shown.isEmpty else { continue }
        print("\n\(category.rawValue):")
        for key in shown {
            let alias = KeyNames.aliases.first { $0.value == key.vk }?.key
            print(String(format: "  %-26@ %@", key.displayLabel as NSString, alias.map { "alias: \($0)" } ?? ""))
        }
    }
}

/// Converte `tecla=função` em (bufferIndex, VK).
func parseRemapPairs(_ config: KeyboardConfig) -> [Int: VKCode] {
    var result: [Int: VKCode] = [:]
    for pair in args.positionals {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { fail("par inválido: \"\(pair)\" (use tecla=função)") }
        guard let key = KeyNames.physicalKey(parts[0], in: config) else {
            fail("tecla \"\(parts[0])\" não existe nesse layout. Veja `rkg68 keys`.")
        }
        guard let target = KeyNames.target(parts[1]), target.fw != 0 else {
            fail("função \"\(parts[1])\" desconhecida. Veja `rkg68 targets`.")
        }
        result[key.bufferIndex] = target.vk
    }
    return result
}

func cmdRemap() {
    guard !args.positionals.isEmpty else { fail("informe ao menos um par tecla=função") }
    let keyboard = connect()
    var profile = currentProfile()
    let pairs = parseRemapPairs(keyboard.config)

    for (bufferIndex, vk) in pairs {
        profile.remaps[bufferIndex] = vk
        let from = keyboard.config.key(bufferIndex: bufferIndex)?.keyInfo.displayLabel ?? "#\(bufferIndex)"
        let to = Keycode.info(vk: vk)?.displayLabel ?? "VK 0x\(String(vk, radix: 16))"
        print("\(from) → \(to)")
    }

    do {
        try keyboard.applyRemaps(profile.firmwareMappings())
    } catch {
        fail(describe(error))
    }
    print("✔ \(profile.remaps.count) remap(s) gravado(s) no firmware")
    saveIfWanted(profile)
}

func cmdResetRemap() {
    let keyboard = connect()
    do { try keyboard.resetRemaps() } catch { fail(describe(error)) }
    print("✔ layout de fábrica restaurado")
    var profile = currentProfile()
    profile.remaps = [:]
    saveIfWanted(profile)
}

func resolveMode(_ raw: String, in config: KeyboardConfig) -> LightingMode {
    if let index = Int(raw), let mode = config.lightingModes.first(where: { $0.index == index }) {
        return mode
    }
    let needle = raw.lowercased()
    if let mode = config.lightingModes.first(where: { $0.name.lowercased() == needle })
        ?? config.lightingModes.first(where: { $0.name.lowercased().contains(needle) }) {
        return mode
    }
    fail("modo \"\(raw)\" não existe nesse teclado. Veja `rkg68 info`.")
}

/// Devolve também se a cor veio da paleta: preset é byte já validado a olho, e
/// aplicar a calibração nele desfaria a validação.
func buildLighting(_ config: KeyboardConfig, base: LightingSettings?)
    -> (settings: LightingSettings, fromPalette: Bool) {
    var fromPalette = false
    guard let raw = args.positionals.first else { fail("informe o modo (índice ou nome). Veja `rkg68 info`.") }
    let mode = resolveMode(raw, in: config)

    var settings = base ?? LightingSettings(modeIndex: mode.index)
    settings.modeIndex = mode.index
    if let speed = args.int("speed") { settings.speed = speed }
    if let brightness = args.int("brightness") { settings.brightness = brightness }
    if let sleep = args.int("sleep") { settings.sleep = sleep }
    if args.has("random") { settings.randomColor = true }
    if let raw = args.flags["color"] {
        let resolved = resolveColor(raw, palette: PaletteStore().load())
        fromPalette = resolved.fromPalette
        settings.color = resolved.color
        settings.randomColor = false
    }

    if !mode.flags.colorPicker && args.flags["color"] != nil {
        print("aviso: o modo \"\(mode.name)\" ignora cor fixa")
    }
    if !mode.flags.speed && args.flags["speed"] != nil {
        print("aviso: o modo \"\(mode.name)\" ignora velocidade")
    }
    return (settings, fromPalette)
}

func cmdLED() {
    let keyboard = connect()
    var profile = currentProfile()
    let (settings, fromPalette) = buildLighting(keyboard.config, base: profile.lighting)
    let mode = keyboard.config.lightingModes.first { $0.index == settings.modeIndex }
    if fromPalette {
        keyboard.calibration = .identity
        print("cor de preset: enviada crua, sem calibração")
    }

    do { try keyboard.applyLighting(settings) } catch { fail(describe(error)) }
    print("✔ modo \(settings.modeIndex) (\(mode?.name ?? "?")) aplicado "
          + "— velocidade \(settings.speed), brilho \(settings.brightness), "
          + (settings.randomColor ? "cores aleatórias" : "cor \(settings.color.hex)"))
    profile.lighting = settings
    saveIfWanted(profile)
}

func cmdPerKey() {
    guard !args.positionals.isEmpty || args.flags["fill"] != nil else {
        fail("informe pares tecla=#RRGGBB (ou --fill #RRGGBB)")
    }
    let keyboard = connect()
    var profile = currentProfile()

    // --fill pinta TODO o espaço de índices do protocolo, não só as teclas que
    // o KB.ini lista. Serve para diagnosticar LEDs em posições de matriz que o
    // arquivo da RK não declara.
    let palette = PaletteStore().load()
    var fromPalette = false

    if let raw = args.flags["fill"] {
        let resolved = resolveColor(raw, palette: palette)
        fromPalette = fromPalette || resolved.fromPalette
        for index in 0...LightingCodec.maxPerKeyIndex {
            profile.perKeyColors[index] = resolved.color
        }
    }

    for pair in args.positionals {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { fail("par inválido: \"\(pair)\" (use tecla=#RRGGBB)") }
        let resolved = resolveColor(parts[1], palette: palette)
        fromPalette = fromPalette || resolved.fromPalette
        let color = resolved.color

        // `#N` cru endereça o índice direto, mesmo fora do layout — é assim
        // que se alcança um LED que o KB.ini não lista.
        if parts[0].hasPrefix("#"), let index = Int(parts[0].dropFirst()) {
            profile.perKeyColors[index] = color
            continue
        }
        guard let key = KeyNames.physicalKey(parts[0], in: keyboard.config) else {
            fail("tecla \"\(parts[0])\" não existe nesse layout")
        }
        profile.perKeyColors[key.bufferIndex] = color
    }

    if fromPalette {
        keyboard.calibration = .identity
        print("cor de preset: enviada crua, sem calibração")
    }
    do { try keyboard.applyPerKeyColors(profile.perKeyColors) } catch { fail(describe(error)) }
    print("✔ \(profile.perKeyColors.count) tecla(s) colorida(s)")
    if let custom = keyboard.config.customColorMode, profile.lighting?.modeIndex != custom.index {
        print("aviso: para ver as cores, ative o modo \(custom.index) (\(custom.name)): rkg68 led \(custom.index)")
    }
    saveIfWanted(profile)
}

/// Lê feature reports do teclado. O software oficial usa HidD_GetFeature,
/// então existe caminho de leitura que nenhum projeto open source explora.
func cmdRead() {
    let keyboard = connect()
    let ids: [UInt8] = args.positionals.isEmpty
        ? [0x0a]
        : args.positionals.compactMap { UInt8($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }

    // --scan varre todos os report IDs para descobrir quais o firmware atende.
    if args.has("scan-ids") {
        var answered: [(UInt8, [UInt8])] = []
        for id in UInt8(0)...UInt8(255) {
            if let data = try? keyboard.transport.read(reportID: id), data.contains(where: { $0 != 0 }) {
                answered.append((id, data))
            }
        }
        if answered.isEmpty {
            print("Nenhum report ID devolveu dados.")
        } else {
            print("\(answered.count) report ID(s) responderam:")
            for (id, data) in answered {
                let preview = data.prefix(24).map { String(format: "%02x", $0) }.joined(separator: " ")
                print(String(format: "  0x%02x  (%d bytes)  %@…", id, data.count, preview))
            }
        }
        return
    }

    for id in ids {
        do {
            let data = try keyboard.transport.read(reportID: id)
            print("report 0x\(String(format: "%02x", id)) — \(data.count) bytes:")
            for chunk in stride(from: 0, to: data.count, by: 16) {
                let slice = data[chunk..<min(chunk + 16, data.count)]
                print(String(format: "  %04x  %@", chunk, slice.map { String(format: "%02x", $0) }.joined(separator: " ")))
            }
        } catch {
            print("report 0x\(String(format: "%02x", id)): \(describe(error))")
        }
    }
}

/// Restauração de fábrica do firmware (byte[6] = 1), como o software oficial.
func cmdFactoryReset() {
    let keyboard = connect()
    let withC0 = args.has("tail-c0")
    print("Enviando a restauração de fábrica\(withC0 ? " (com 0xC0 no fim)" : "")…")
    do { try keyboard.factoryReset(trailingC0: withC0) } catch { fail(describe(error)) }
    print("✔ comando de fábrica enviado + mapa de teclas original regravado")
}

/// Reescreve tudo do zero, na ordem do Rangoli. Serve para tirar o firmware
/// de um estado inconsistente.
func cmdResync() {
    let keyboard = connect()
    var settings: LightingSettings?
    if let raw = args.positionals.first {
        settings = buildLighting(keyboard.config, base: nil).settings
        _ = raw
    }
    print("Reescrevendo o estado inteiro do teclado (luz → cor por tecla → mapa de teclas)…")
    do { try keyboard.resync(lighting: settings) } catch { fail(describe(error)) }
    print("✔ teclado ressincronizado: layout de fábrica, sem cor por tecla gravada")
}

func cmdProfile() {
    let sub = args.positionals.first ?? "list"
    switch sub {
    case "list":
        let names = store.list()
        if names.isEmpty {
            print("Nenhum perfil salvo em \(store.directory.path)")
        } else {
            for name in names {
                let profile = store.loadIfExists(name: name)
                print("  \(name)  — \(profile?.remaps.count ?? 0) remap(s), "
                      + (profile?.lighting.map { "luz modo \($0.modeIndex)" } ?? "sem luz"))
            }
        }
    case "show":
        let profile = currentProfile()
        let config = offlineConfig()
        print("Perfil \"\(profile.name)\"  (atualizado \(profile.updatedAt.formatted()))")
        if profile.remaps.isEmpty {
            print("  sem remaps")
        } else {
            for (bufferIndex, vk) in profile.remaps.sorted(by: { $0.key < $1.key }) {
                let from = config.key(bufferIndex: bufferIndex)?.keyInfo.displayLabel ?? "#\(bufferIndex)"
                let to = Keycode.info(vk: vk)?.displayLabel ?? "VK 0x\(String(vk, radix: 16))"
                print("  \(from) → \(to)")
            }
        }
        if let light = profile.lighting {
            print("  luz: modo \(light.modeIndex), velocidade \(light.speed), brilho \(light.brightness), "
                  + (light.randomColor ? "aleatória" : light.color.hex))
        }
        if !profile.perKeyColors.isEmpty {
            print("  \(profile.perKeyColors.count) cor(es) por tecla")
        }
    case "apply":
        let keyboard = connect()
        let profile = currentProfile()
        do { try keyboard.apply(profile) } catch { fail(describe(error)) }
        print("✔ perfil \"\(profile.name)\" aplicado")
    case "delete":
        do { try store.delete(name: profileName); print("perfil \"\(profileName)\" removido") }
        catch { fail(describe(error)) }
    default:
        fail("subcomando de perfil desconhecido: \(sub)")
    }
}

/// Mostra os bytes sem tocar no hardware — serve para comparar com capturas
/// do software oficial.
func cmdDumpBuffers() {
    let config = offlineConfig()
    let what = args.positionals.first ?? "remap"
    var rest = args.positionals
    if !rest.isEmpty { rest.removeFirst() }

    switch what {
    case "remap":
        var mappings: [Int: FirmwareCode] = [:]
        for pair in rest {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let key = KeyNames.physicalKey(parts[0], in: config),
                  let target = KeyNames.target(parts[1]) else { fail("par inválido: \(pair)") }
            mappings[key.bufferIndex] = target.fw
        }
        hexDump(RemapCodec.encode(mappings: mappings, config: config))
    case "led":
        let mode = rest.first.map { resolveMode($0, in: config).index } ?? config.lightingModes.first?.index ?? 1
        var settings = LightingSettings(modeIndex: mode)
        if let speed = args.int("speed") { settings.speed = speed }
        if let brightness = args.int("brightness") { settings.brightness = brightness }
        if let hex = args.flags["color"], let color = RKColor(hex: hex) { settings.color = color }
        if args.has("random") { settings.randomColor = true }
        hexDump([LightingCodec.encodeStandard(settings)])
    case "perkey":
        var colors: [Int: RKColor] = [:]
        for pair in rest {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let key = KeyNames.physicalKey(parts[0], in: config),
                  let color = RKColor(hex: parts[1]) else { fail("par inválido: \(pair)") }
            colors[key.bufferIndex] = color
        }
        hexDump(LightingCodec.encodePerKey(colors))
    default:
        fail("dump-buffers aceita: remap, led, perkey")
    }
}

/// Conjuntos "Gaming mode" / "Office mode" da RK.
///
/// No software oficial são dois botões na aba Avançado. Nos arquivos são
/// `GaoshouKey1`/`GaoshouKey2` + `clrGaoshou` — listas de VK, não de índice de
/// buffer. Na prática é um preenchimento da tabela de cor por tecla: acende o
/// conjunto, apaga o resto, e por isso depende do modo Customize.
func cmdKeySet() {
    let keyboard = connect()
    let sets = keyboard.config.keySets
    guard !sets.isEmpty else { fail("este modelo não declara conjuntos de teclas no KB.ini") }

    guard let pedido = args.positionals.first else {
        print("conjuntos disponíveis:")
        for set in sets {
            let n = keyboard.config.perKeyColors(for: set).count
            print("  \(set.name.lowercased())  — \(n) tecla(s) neste layout, cor \(set.color.hex)")
        }
        print("\nuso: rkg68 keyset <nome> [--color #RRGGBB]")
        return
    }

    let alvo = pedido.lowercased().folding(options: .diacriticInsensitive, locale: nil)
    guard let set = sets.first(where: {
        $0.name.lowercased().folding(options: .diacriticInsensitive, locale: nil).hasPrefix(alvo)
    }) else {
        fail("conjunto \"\(pedido)\" não existe. Tente: " + sets.map { $0.name.lowercased() }.joined(separator: ", "))
    }

    var colors = keyboard.config.perKeyColors(for: set)
    if let hex = args.flags["color"] {
        guard let color = RKColor(hex: hex) else { fail("cor inválida: \(hex)") }
        colors = colors.mapValues { _ in color }
    }
    guard !colors.isEmpty else { fail("nenhuma tecla do conjunto \"\(set.name)\" existe neste layout") }

    guard let custom = keyboard.config.customColorMode else {
        fail("este modelo não tem modo de cor por tecla")
    }

    var profile = currentProfile()
    profile.perKeyColors = colors
    var lighting = profile.lighting ?? LightingSettings(modeIndex: custom.index)
    lighting.modeIndex = custom.index
    profile.lighting = lighting

    do {
        try keyboard.applyLighting(lighting)
        try keyboard.applyPerKeyColors(colors)
    } catch { fail(describe(error)) }

    print("✔ conjunto \"\(set.name)\": \(colors.count) tecla(s) acesas, resto apagado")
    print("  modo \(custom.index) (\(custom.name)) ativado")
    saveIfWanted(profile)
}

func cmdCalibrate() {
    let store = CalibrationStore()
    var cal = store.load()
    var changed = false

    if args.has("reset") { cal = .identity; changed = true }
    if args.has("preset") { cal = .g68Measured; changed = true }
    for (flag, keyPath) in [("r", \ColorCalibration.r), ("g", \ColorCalibration.g), ("b", \ColorCalibration.b)] {
        guard let raw = args.flags[flag] else { continue }
        guard let value = Double(raw), value >= 0, value <= 1 else {
            fail("--\(flag) aceita 0 a 1 (recebi \"\(raw)\")")
        }
        cal[keyPath: keyPath] = value
        changed = true
    }
    if let raw = args.flags["gamma"] {
        guard let value = Double(raw), value >= 0.4, value <= 3 else {
            fail("--gamma aceita 0.4 a 3 (recebi \"\(raw)\")")
        }
        cal.gamma = value
        changed = true
    }
    for (flag, keyPath) in [("load-r", \ColorCalibration.loadExponentR),
                            ("load-g", \ColorCalibration.loadExponentG),
                            ("load-b", \ColorCalibration.loadExponentB)] {
        guard let raw = args.flags[flag] else { continue }
        guard let value = Double(raw), value >= 0, value <= 1 else {
            fail("--\(flag) aceita 0 a 1 (recebi \"\(raw)\")")
        }
        cal[keyPath: keyPath] = value
        changed = true
    }
    if args.has("keys-reset") {
        cal.keyScale = [:]
        changed = true
    }
    // Correção por posição: --keys lista as teclas e --key-r/-g/-b o fator.
    if let list = args.flags["keys"] {
        let config = offlineConfig()
        func factor(_ flag: String) -> Double {
            guard let raw = args.flags[flag] else { return 1 }
            guard let value = Double(raw), value >= 0, value <= 1 else {
                fail("--\(flag) aceita 0 a 1 (recebi \"\(raw)\")")
            }
            return value
        }
        let scale = ChannelScale(r: factor("key-r"), g: factor("key-g"), b: factor("key-b"))
        var indices: [Int] = []
        for name in list.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if name.hasPrefix("#"), let index = Int(name.dropFirst()) {
                indices.append(index)
                continue
            }
            guard let key = KeyNames.physicalKey(name, in: config) else {
                fail("tecla \"\(name)\" não existe nesse layout")
            }
            indices.append(key.bufferIndex)
        }
        guard !indices.isEmpty else { fail("--keys veio vazio") }
        for index in indices {
            if scale.isNeutral { cal.keyScale.removeValue(forKey: index) }
            else { cal.keyScale[index] = scale }
        }
        changed = true
        print("correção de posição em \(indices.count) tecla(s): \(scale.summary)")
    }
    // Passar pelo init normaliza os limites depois das atribuições diretas.
    cal = ColorCalibration(r: cal.r, g: cal.g, b: cal.b, gamma: cal.gamma,
                           loadExponentR: cal.loadExponentR,
                           loadExponentG: cal.loadExponentG,
                           loadExponentB: cal.loadExponentB,
                           keyScale: cal.keyScale)

    if changed {
        do { try store.save(cal) } catch { fail("não consegui salvar a calibração: \(error.localizedDescription)") }
    }

    print("calibração: \(cal.summary)\(cal.isIdentity ? "  (cor crua)" : "")")
    print("arquivo: \(store.url.path)")
    if cal.isLoadDependent {
        // O ganho muda com a carga, então um número só mentiria.
        print("branco pedido #FFFFFF → enviado:")
        for n in [1, 9, 15, 29, 68] {
            let gains = cal.gains(litCount: n)
            print(String(format: "   %3d LED(s) acesos  %@  (R %.2f · G %.2f · B %.2f)",
                         n, cal.apply(.white, litCount: n).hex, gains.r, gains.g, gains.b))
        }
    } else {
        print("branco pedido #FFFFFF → enviado \(cal.apply(.white).hex)")
    }

    guard args.has("white") else {
        if !changed {
            print("\nnada mudou. use --r/--g/--b, --load-r/--load-g/--load-b, --preset ou --reset;")
            print("--white acende para conferir.")
        }
        return
    }

    let keyboard = connect()
    keyboard.calibration = cal
    guard let steady = keyboard.config.lightingModes.first(where: { $0.name == "Steady" })
            ?? keyboard.config.lightingModes.first else {
        fail("o teclado não declara modos de iluminação")
    }
    let settings = LightingSettings(modeIndex: steady.index, speed: 3, brightness: 5,
                                    color: .white, randomColor: false, sleep: 5)
    do { try keyboard.applyLighting(settings) } catch { fail(describe(error)) }
    print("\n✔ branco sólido aplicado no modo \(steady.index) (\(steady.name)).")
    print("  Ainda rosado? baixe --r. Esverdeado? baixe --g. Azulado? baixe --b.")
}

/// Cor sólida uniforme: Customize com a tabela compensada por posição, em vez
/// do Steady, que manda uma cor só e deixa os cantos fugirem.
func cmdSolid() {
    guard let raw = args.positionals.first else {
        fail("informe a cor: rkg68 solid <#RRGGBB|@nome>")
    }
    let palette = PaletteStore().load()
    let resolved = resolveColor(raw, palette: palette)
    let keyboard = connect()
    if resolved.fromPalette {
        keyboard.calibration = .identity
        print("cor de preset: enviada crua, sem calibração")
    }
    let cal = keyboard.calibration
    var profile = currentProfile()

    let colors: [Int: RKColor]
    do {
        colors = try keyboard.applyUniform(resolved.color,
                                           brightness: args.int("brightness") ?? 5)
    } catch { fail(describe(error)) }

    guard let custom = keyboard.config.customColorMode else { return }
    print("✔ \(resolved.color.hex) sólido em \(colors.count) tecla(s) pelo modo \(custom.index) (\(custom.name))")
    if cal.hasKeyScale {
        print("  \(cal.keyScale.count) tecla(s) com correção de posição aplicada")
    } else if !cal.isIdentity {
        print("  sem correção por posição: os cantos podem fugir da cor do centro")
    }

    profile.lighting = LightingSettings(modeIndex: custom.index, speed: 3,
                                        brightness: args.int("brightness") ?? 5,
                                        color: resolved.color, randomColor: false, sleep: 5)
    profile.perKeyColors = colors
    saveIfWanted(profile)
}

// MARK: - Paleta de cores validadas

/// Resolve uma cor escrita como `#RRGGBB` ou como `@nome` de preset.
/// Devolve também se veio da paleta — preset é byte validado e não passa pela
/// calibração de novo.
func resolveColor(_ raw: String, palette: Palette) -> (color: RKColor, fromPalette: Bool) {
    if raw.hasPrefix("@") {
        let name = String(raw.dropFirst())
        guard let entry = palette.entry(named: name) else {
            fail("preset \"\(name)\" não existe na paleta. Veja `rkg68 palette list`.")
        }
        return (entry.color, true)
    }
    guard let color = RKColor(hex: raw) else {
        fail("cor inválida: \(raw) (use #RRGGBB ou @nome de preset)")
    }
    return (color, false)
}

func cmdPalette() {
    let store = PaletteStore()
    var palette = store.load()
    let sub = (args.positionals.first ?? "list").lowercased()
    let rest = Array(args.positionals.dropFirst())

    func savePalette() {
        do { try store.save(palette) }
        catch { fail("não consegui salvar a paleta: \(error.localizedDescription)") }
    }

    switch sub {
    case "list", "ls":
        guard !palette.entries.isEmpty else {
            print("A paleta está vazia.")
            print("Valide uma cor com `rkg68 palette test <cores…>` e registre com")
            print("`rkg68 palette add <nome> <#RRGGBB> --lit <n>`.")
            return
        }
        print("Cores validadas — \(store.url.path)\n")
        for entry in palette.entries {
            print("  \(entry.name.padding(toLength: max(16, entry.name.count), withPad: " ", startingAt: 0))  \(entry.summary)")
        }
        print("\nUse em qualquer comando de cor como @nome, por exemplo:")
        print("  rkg68 led 17 --color @\(palette.entries[0].name)")

    case "add", "set":
        guard rest.count >= 2 else {
            fail("uso: rkg68 palette add <nome> <#RRGGBB> [--lit <n>] [--note \"…\"]")
        }
        let name = rest[0]
        guard let color = RKColor(hex: rest[1]) else {
            fail("cor inválida: \(rest[1]) (use #RRGGBB — o preset guarda o byte cru)")
        }
        let entry = PaletteEntry(name: name, color: color,
                                 litCount: args.int("lit"),
                                 note: args.flags["note"])
        let replaced = palette.put(entry)
        savePalette()
        print("✔ \(replaced ? "atualizado" : "registrado"): \(entry.name) — \(entry.summary)")
        if entry.litCount == nil {
            print("  dica: --lit <n> anota com quantos LEDs acesos você validou. A mesma")
            print("  tripla muda de cor com a carga, então sem isso o preset fica ambíguo.")
        }

    case "remove", "rm", "delete":
        guard let name = rest.first else { fail("uso: rkg68 palette remove <nome>") }
        guard let gone = palette.remove(named: name) else {
            fail("preset \"\(name)\" não existe na paleta")
        }
        savePalette()
        print("✔ removido: \(gone.name) (\(gone.color.hex))")

    case "apply", "show":
        guard let name = rest.first else { fail("uso: rkg68 palette apply <nome>") }
        guard let entry = palette.entry(named: name) else {
            fail("preset \"\(name)\" não existe na paleta")
        }
        let keyboard = connect()
        // Preset é byte validado: enviar cru é o ponto dele.
        keyboard.calibration = .identity
        guard let steady = keyboard.config.lightingModes.first(where: { $0.name == "Steady" })
                ?? keyboard.config.lightingModes.first else {
            fail("o teclado não declara modos de iluminação")
        }
        let settings = LightingSettings(modeIndex: steady.index, speed: 3,
                                        brightness: args.int("brightness") ?? 5,
                                        color: entry.color, randomColor: false, sleep: 5)
        do { try keyboard.applyLighting(settings) } catch { fail(describe(error)) }
        print("✔ \(entry.name) (\(entry.color.hex)) aplicado no modo \(steady.index) (\(steady.name)), sem calibração")
        if let lit = entry.litCount, lit != keyboard.config.keyCount {
            print("  aviso: validado com \(lit) LED(s) e aplicado com \(keyboard.config.keyCount) —")
            print("  a cor pode sair diferente do que você aprovou.")
        }

    case "test":
        guard !rest.isEmpty else {
            fail("uso: rkg68 palette test <#RRGGBB|@nome>… [--rows]  (--rows = carga cheia)")
        }
        let candidates = rest.map { resolveColor($0, palette: palette) }
        let keyboard = connect()
        guard let custom = keyboard.config.customColorMode else {
            fail("o teclado não tem modo de cor por tecla")
        }
        let rows = keyboard.config.rows()
        var colors: [Int: RKColor] = [:]
        var plan: [(String, RKColor)] = []

        if args.has("rows") {
            // Carga cheia: cada candidato pinta uma fileira inteira. É assim que
            // se compara candidato com o teclado aceso, que é a condição real
            // dos modos comuns.
            guard candidates.count <= rows.count else {
                fail("--rows comporta até \(rows.count) candidatos (um por fileira); recebi \(candidates.count)")
            }
            for (i, candidate) in candidates.enumerated() {
                let row = rows[i]
                for key in row { colors[key.bufferIndex] = candidate.color }
                let first = row.first?.keyInfo.displayLabel ?? "?"
                let last = row.last?.keyInfo.displayLabel ?? "?"
                plan.append(("fileira \(i + 1) (\(first) → \(last), \(row.count) teclas)", candidate.color))
            }
        } else {
            // Carga esparsa: um candidato por tecla, na primeira fileira.
            let slots = rows.flatMap { $0 }
            guard candidates.count <= slots.count else {
                fail("cabem \(slots.count) candidatos no layout; recebi \(candidates.count)")
            }
            for (i, candidate) in candidates.enumerated() {
                colors[slots[i].bufferIndex] = candidate.color
                plan.append((slots[i].keyInfo.displayLabel, candidate.color))
            }
        }

        // Sem calibração: o teste existe para julgar o byte, não o modelo.
        keyboard.calibration = .identity
        let lighting = LightingSettings(modeIndex: custom.index, speed: 3,
                                        brightness: args.int("brightness") ?? 5,
                                        color: .white, randomColor: false, sleep: 5)
        do {
            try keyboard.applyLighting(lighting)
            try keyboard.applyPerKeyColors(colors)
        } catch { fail(describe(error)) }

        print("✔ \(candidates.count) candidato(s) no modo \(custom.index) (\(custom.name)), bytes crus")
        print("  carga: \(colors.count) LED(s) acesos\n")
        for (where_, color) in plan {
            print("  \(color.hex)  \(where_)")
        }
        print("\nAprovou algum? registre com a carga em que julgou:")
        print("  rkg68 palette add <nome> \(plan.first?.1.hex ?? "#RRGGBB") --lit \(colors.count)")

    default:
        fail("subcomando de palette desconhecido: \"\(sub)\" (use list, add, remove, apply, test)")
    }
}

// MARK: - Dispatch

switch args.command {
case "scan": cmdScan()
case "info": cmdInfo()
case "keys": cmdKeys()
case "targets": cmdTargets()
case "remap": cmdRemap()
case "reset-remap": cmdResetRemap()
case "led": cmdLED()
case "perkey": cmdPerKey()
case "read": cmdRead()
case "factory-reset": cmdFactoryReset()
case "resync": cmdResync()
case "profile": cmdProfile()
case "keyset": cmdKeySet()
case "palette": cmdPalette()
case "solid": cmdSolid()
case "calibrate": cmdCalibrate()
case "dump-buffers": cmdDumpBuffers()
case "selftest": exit(SelfTest.run() ? 0 : 1)
case "", "help", "-h", "--help": print(usage)
default: fail("comando desconhecido: \(args.command)\n\n\(usage)")
}
