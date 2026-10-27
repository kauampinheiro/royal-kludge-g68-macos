//
//  KeyboardController.swift
//  Estado único do app: conexão com o teclado, perfil em edição e escrita
//  no firmware.
//
//  Todas as escritas acontecem no main actor de propósito: um perfil inteiro
//  são 9 feature reports (~20 ms) e o firmware não tolera comandos
//  intercalados — serializar na UI é mais simples e mais seguro que
//  paralelizar.
//

import AppKit
import Foundation
import Observation
import RKCore

@MainActor
@Observable
final class KeyboardController {
    enum Connection {
        case searching
        case connected(RKKeyboard)
        case notFound
        case failed(String)

        var keyboard: RKKeyboard? {
            if case .connected(let keyboard) = self { return keyboard }
            return nil
        }
    }

    var connection: Connection = .searching
    var profile: Profile
    var profileNames: [String] = []
    /// Tecla selecionada no desenho do teclado.
    var selectedKeyIndex: Int?
    /// Última mensagem de resultado mostrada no rodapé.
    var status: String = ""
    var statusIsError = false
    /// Cor usada ao pintar teclas no modo de cor por tecla.
    var paintColor = RKColor(r: 255, g: 0, b: 0)
    /// Correção de cor da unidade física. Mora fora do perfil de propósito:
    /// é propriedade do teclado, vale para todos os perfis.
    var calibration: ColorCalibration = CalibrationStore().load() {
        didSet {
            guard calibration != oldValue else { return }
            connection.keyboard?.calibration = calibration
            try? calibrationStore.save(calibration)
            if let lighting = profile.lighting { applyLighting(lighting) }
        }
    }
    /// Autorização de Monitoramento de Entrada, relida a cada `refresh()`.
    /// Sem ela o IOKit recusa abrir o teclado, e é o motivo mais comum de o
    /// app achar o dispositivo e ainda assim não conseguir gravar nada.
    var access: RKHIDAccess = .granted

    /// Cores validadas a olho. Fora do perfil, como a calibração: é
    /// conhecimento sobre a unidade física, não sobre um conjunto de ajustes.
    var palette: Palette = PaletteStore().load()

    /// Macros por software. Não ficam no firmware — ver `Macro.swift`.
    var macros: [Macro] = MacroStore().load().macros
    /// O macOS autorizou o app a controlar o computador (Acessibilidade)?
    /// Sem isso o event tap nem é criado.
    var accessibilityGranted = MacroEngine.hasAccessibility
    /// Espelho observável do motor: um `computed` lendo o `MacroEngine` não
    /// notificaria a interface quando o tap liga ou desliga.
    var macrosActive = false

    // MARK: - Comportamento do app
    //
    // Estas três moram aqui, e não em `UserDefaults` lido direto pela view,
    // porque `UserDefaults` não é observável: o clique chamava o setter, o
    // valor mudava, e o menu não se redesenhava — a marca de seleção ficava
    // onde estava e o item parecia morto.

    var hideDockIcon: Bool = AppPreferences.hideDockIcon {
        didSet {
            guard hideDockIcon != oldValue else { return }
            AppPreferences.hideDockIcon = hideDockIcon
        }
    }

    var startInBackground: Bool = AppPreferences.startInBackground {
        didSet {
            guard startInBackground != oldValue else { return }
            AppPreferences.startInBackground = startInBackground
        }
    }

    var loginItemEnabled: Bool = LoginItem.isEnabled {
        didSet {
            guard loginItemEnabled != oldValue else { return }
            LoginItem.set(loginItemEnabled) { [weak self] message, isError in
                self?.report(message, isError: isError)
            }
            // O macOS pode recusar ou exigir aprovação: o valor exibido tem de
            // ser o que o sistema diz, não o que foi pedido.
            let actual = LoginItem.isEnabled
            if actual != loginItemEnabled { loginItemEnabled = actual }
            loginItemNeedsApproval = LoginItem.needsApproval
        }
    }

    var loginItemNeedsApproval: Bool = LoginItem.needsApproval

    private let store = ProfileStore()
    private let calibrationStore = CalibrationStore()
    private let paletteStore = PaletteStore()
    private let macroStore = MacroStore()
    private var resources: RKResources?
    private var pollTimer: Timer?

    /// Modelo a usar na interface mesmo sem teclado conectado: sem isso a
    /// janela ficaria vazia enquanto o cabo não está plugado.
    var config: KeyboardConfig? {
        connection.keyboard?.config ?? fallbackConfig
    }
    private var fallbackConfig: KeyboardConfig?

    /// O init fica deliberadamente vazio de I/O: ler o bundle aqui trava a
    /// criação da janela se o sistema resolver pedir autorização de disco —
    /// o app fica rodando sem interface nenhuma. O carregamento real
    /// acontece em `start()`, chamado pela view já montada.
    init() {
        profile = Profile(name: "Padrão")
    }

    private(set) var started = false

    /// Carrega definições e perfis fora da thread principal. Ler o bundle
    /// pode bloquear por segundos se o macOS decidir pedir autorização de
    /// disco, e a janela não pode congelar por causa disso.
    func start() async {
        guard !started else { return }
        started = true

        let store = self.store
        let loaded = await Task.detached(priority: .userInitiated) { () -> Loaded in
            let resources = try? RKResources.bundled()
            var fallback: KeyboardConfig?
            if let resources, let loader = try? KeyboardConfigLoader(resources: resources) {
                // 013A é o G68 RGB com fio — o layout mostrado enquanto nada responde.
                fallback = try? loader.load(pid: "013a")
            }
            return Loaded(resources: resources,
                          fallbackConfig: fallback,
                          profile: store.loadIfExists(name: "Padrão"),
                          profileNames: store.list())
        }.value

        resources = loaded.resources
        fallbackConfig = loaded.fallbackConfig
        if let saved = loaded.profile { profile = saved }
        profileNames = loaded.profileNames

        refresh()
        startPolling()
        syncMacroEngine()
    }

    /// Resultado do carregamento em segundo plano.
    private struct Loaded: Sendable {
        let resources: RKResources?
        let fallbackConfig: KeyboardConfig?
        let profile: Profile?
        let profileNames: [String]
    }

    // MARK: - Conexão

    func refresh() {
        guard let resources else {
            connection = .failed("Recursos da RK não encontrados no app.")
            return
        }

        // A descoberta não depende de autorização; abrir, sim. Reler aqui deixa
        // a interface em dia depois de o usuário marcar a caixa em Ajustes.
        access = RKHIDTransport.access

        let interfaces = RKHIDTransport.discoverConfigurationInterfaces()
        guard !interfaces.isEmpty else {
            if case .connected = connection { connection = .notFound } else if case .searching = connection {
                connection = .notFound
            } else {
                connection = .notFound
            }
            return
        }

        // Já conectado no mesmo dispositivo: nada a fazer.
        if let current = connection.keyboard,
           interfaces.contains(where: { $0.info.id == current.info.id }) {
            return
        }

        do {
            let keyboard = try RKKeyboard.connect(resources: resources, calibration: calibration)
            connection = .connected(keyboard)
            report("\(keyboard.config.name) conectado")
        } catch {
            connection = .failed(describe(error))
        }
        // `connect` pode ter acabado de disparar o diálogo do sistema.
        access = RKHIDTransport.access
    }

    /// Mostrar o caminho da autorização só quando ela realmente falta.
    var needsInputMonitoring: Bool { access != .granted }

    /// Pede a autorização; se o sistema já tem uma resposta gravada ele não
    /// pergunta mais nada, então nesse caso abrimos o painel de Ajustes.
    func requestInputMonitoring() {
        if RKHIDTransport.access == .notAsked, RKHIDTransport.requestAccess() {
            access = .granted
            refresh()
            return
        }
        NSWorkspace.shared.open(RKHIDTransport.inputMonitoringSettingsURL)
        report("Marque \"RK G68\" em Monitoramento de Entrada e clique em Procurar. "
               + "Se já estiver marcado, desmarque e marque de novo.", isError: true)
    }

    private func startPolling() {
        // O IOKit avisa por callback, mas o polling curto cobre também a troca
        // de cabo e a volta do sleep sem manter um run loop próprio.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var isConnected: Bool { connection.keyboard != nil }

    var connectionLabel: String {
        switch connection {
        case .searching: return "Procurando…"
        case .connected(let keyboard): return keyboard.config.name
        case .notFound: return "Nenhum teclado RK no cabo USB"
        case .failed(let message): return message
        }
    }

    // MARK: - Remap

    func remap(keyIndex: Int, to vk: VKCode?) {
        if let vk {
            profile.remaps[keyIndex] = vk
        } else {
            profile.remaps.removeValue(forKey: keyIndex)
        }
        writeRemaps()
    }

    func clearAllRemaps() {
        profile.remaps.removeAll()
        writeRemaps()
    }

    private func writeRemaps() {
        guard let keyboard = connection.keyboard else {
            report("Conecte o teclado pelo cabo USB para gravar.", isError: true)
            return
        }
        do {
            try keyboard.applyRemaps(profile.firmwareMappings())
            persist()
            report(profile.remaps.isEmpty
                   ? "Layout de fábrica restaurado"
                   : "\(profile.remaps.count) remap(s) gravado(s) no teclado")
        } catch {
            report(describe(error), isError: true)
        }
    }

    // MARK: - Iluminação

    func applyLighting(_ settings: LightingSettings) {
        profile.lighting = settings
        guard let keyboard = connection.keyboard else {
            report("Conecte o teclado pelo cabo USB para gravar.", isError: true)
            return
        }
        do {
            try keyboard.applyLighting(settings)
            persist()
            let name = keyboard.config.lightingModes.first { $0.index == settings.modeIndex }?.name
            report("Iluminação: \(name ?? "modo \(settings.modeIndex)")")
        } catch {
            report(describe(error), isError: true)
        }
    }

    func paintKey(_ keyIndex: Int) {
        profile.perKeyColors[keyIndex] = paintColor
        writePerKeyColors()
    }

    func clearKeyColor(_ keyIndex: Int) {
        profile.perKeyColors.removeValue(forKey: keyIndex)
        writePerKeyColors()
    }

    func clearAllKeyColors() {
        profile.perKeyColors.removeAll()
        writePerKeyColors()
    }

    private func writePerKeyColors() {
        guard let keyboard = connection.keyboard else {
            report("Conecte o teclado pelo cabo USB para gravar.", isError: true)
            return
        }
        do {
            try keyboard.applyPerKeyColors(profile.perKeyColors)
            persist()
            report("\(profile.perKeyColors.count) tecla(s) com cor própria")
        } catch {
            report(describe(error), isError: true)
        }
    }

    /// O modo de cor por tecla precisa estar ativo para as cores aparecerem.
    var perKeyColorsVisible: Bool {
        guard let custom = config?.customColorMode else { return false }
        return profile.lighting?.modeIndex == custom.index
    }

    /// Aplica um conjunto da RK ("Jogo" / "Escritório"): acende só aquelas
    /// teclas e apaga o resto. Como é preenchimento da tabela de cor por
    /// tecla, só faz sentido no modo Customize — então o modo entra junto.
    func applyKeySet(_ set: KeySet) {
        guard let keyboard = connection.keyboard else {
            report("Conecte o teclado pelo cabo USB para gravar.", isError: true)
            return
        }
        let colors = keyboard.config.perKeyColors(for: set)
        guard !colors.isEmpty else {
            report("Nenhuma tecla do conjunto \"\(set.name)\" existe neste layout.", isError: true)
            return
        }
        guard let custom = keyboard.config.customColorMode else {
            report("Este modelo não tem modo de cor por tecla.", isError: true)
            return
        }

        var lighting = profile.lighting ?? LightingSettings(modeIndex: custom.index)
        lighting.modeIndex = custom.index
        profile.lighting = lighting
        profile.perKeyColors = colors

        do {
            try keyboard.applyLighting(lighting)
            try keyboard.applyPerKeyColors(colors)
            persist()
            report("Conjunto \"\(set.name)\": \(colors.count) tecla(s) acesas")
        } catch {
            report(describe(error), isError: true)
        }
    }

    /// Cor sólida uniforme pelo Customize, em vez do Steady.
    ///
    /// O Steady manda uma cor só e o firmware a repete em todos os LEDs — e aí
    /// o desvio por posição aparece, porque não há onde aplicar a correção de
    /// cada tecla. Pintando tecla por tecla, cada uma recebe o seu fator.
    func applySolidUniform(_ color: RKColor, raw: Bool = false) {
        guard let keyboard = connection.keyboard else {
            report("Conecte o teclado pelo cabo USB para gravar.", isError: true)
            return
        }
        let brightness = profile.lighting?.brightness ?? 5
        if raw { keyboard.calibration = .identity }
        defer { keyboard.calibration = calibration }
        do {
            let colors = try keyboard.applyUniform(color, brightness: brightness)
            if let custom = keyboard.config.customColorMode {
                var lighting = profile.lighting ?? LightingSettings(modeIndex: custom.index)
                lighting.modeIndex = custom.index
                lighting.color = color
                lighting.randomColor = false
                profile.lighting = lighting
            }
            profile.perKeyColors = colors
            persist()
            let corrigidas = calibration.keyScale.count
            report("\(color.hex) sólido em \(colors.count) tecla(s)"
                   + (raw ? ", sem calibração" : corrigidas > 0 ? " · \(corrigidas) com correção de posição" : ""))
        } catch {
            report(describe(error), isError: true)
        }
    }

    // MARK: - Paleta de cores validadas

    /// Registra a cor como preset. Guarda o **byte cru** que o teclado recebeu
    /// e a carga em que foi julgada — sem os dois, o preset não é reproduzível
    /// (ver `Palette.swift`).
    func addPaletteEntry(name: String, color: RKColor, litCount: Int?, note: String?) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            report("Dê um nome ao preset.", isError: true)
            return
        }
        let entry = PaletteEntry(name: name.trimmingCharacters(in: .whitespaces),
                                 color: color, litCount: litCount,
                                 note: note?.isEmpty == true ? nil : note)
        let replaced = palette.put(entry)
        savePalette()
        report("\(replaced ? "Preset atualizado" : "Preset registrado"): \(entry.name) (\(entry.color.hex))")
    }

    func removePaletteEntry(_ entry: PaletteEntry) {
        palette.remove(named: entry.name)
        savePalette()
        report("Preset \"\(entry.name)\" removido")
    }

    /// Aplica o preset como cor fixa do efeito corrente, **sem calibração**:
    /// o byte guardado já é o resultado que você aprovou olhando o teclado.
    func applyPaletteEntry(_ entry: PaletteEntry) {
        guard let keyboard = connection.keyboard else {
            report("Conecte o teclado pelo cabo USB para gravar.", isError: true)
            return
        }
        guard let config = config else { return }
        var lighting = profile.lighting ?? LightingSettings(modeIndex: config.lightingModes.first?.index ?? 1)
        // Num modo que ignora cor fixa o preset não teria efeito nenhum.
        let mode = config.lightingModes.first { $0.index == lighting.modeIndex }
        if mode?.flags.colorPicker != true,
           let steady = config.lightingModes.first(where: { $0.name == "Steady" }) {
            lighting.modeIndex = steady.index
        }
        lighting.color = entry.color
        lighting.randomColor = false

        keyboard.calibration = .identity
        defer { keyboard.calibration = calibration }
        do {
            try keyboard.applyLighting(lighting)
            profile.lighting = lighting
            persist()
            var message = "\(entry.name) (\(entry.color.hex)) aplicado sem calibração"
            if let lit = entry.litCount, lit != config.keyCount {
                message += " · validado com \(lit) LED(s), aplicado com \(config.keyCount)"
            }
            report(message)
        } catch {
            report(describe(error), isError: true)
        }
    }

    private func savePalette() {
        try? paletteStore.save(palette)
    }

    // MARK: - Correção de cor por tecla

    /// Fator do vermelho dessa tecla. 1 = sem correção.
    func keyScale(_ keyIndex: Int) -> ChannelScale {
        calibration.keyScale[keyIndex] ?? .neutral
    }

    /// Grava o fator de uma tecla e reescreve a tabela para você ver o efeito.
    ///
    /// Só tem efeito onde existe cor por tecla: nos modos de cor única o
    /// firmware recebe uma cor e a repete, sem endereço por tecla.
    func setKeyScale(_ keyIndex: Int, _ scale: ChannelScale) {
        var next = calibration
        if scale.isNeutral {
            next.keyScale.removeValue(forKey: keyIndex)
        } else {
            next.keyScale[keyIndex] = scale
        }
        // O `didSet` de `calibration` já salva e reaplica a iluminação.
        calibration = next
        if !profile.perKeyColors.isEmpty, let keyboard = connection.keyboard {
            try? keyboard.applyPerKeyColors(profile.perKeyColors)
        }
    }

    func clearKeyScales() {
        var next = calibration
        next.keyScale.removeAll()
        calibration = next
        report("Correções por tecla apagadas")
    }

    // MARK: - Macros

    /// Liga o interceptador se houver macro habilitada e autorização.
    /// Chamado a cada mudança: é mais simples garantir o estado certo aqui do
    /// que espalhar start/stop por todas as ações.
    func syncMacroEngine() {
        accessibilityGranted = MacroEngine.hasAccessibility
        MacroEngine.shared.update(macros)
        let wanted = accessibilityGranted && macros.contains { $0.enabled && !$0.steps.isEmpty }
        if wanted {
            if !MacroEngine.shared.start() {
                report("O macOS não liberou a Acessibilidade — as macros não vão disparar.", isError: true)
            }
        } else {
            MacroEngine.shared.stop()
        }
        macrosActive = MacroEngine.shared.isRunning
    }

    func requestAccessibility() {
        MacroEngine.requestAccessibility()
        // O diálogo é assíncrono e o app não é notificado; reconsultar depois
        // de um instante cobre o caso de o usuário autorizar na hora.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            syncMacroEngine()
        }
    }

    func saveMacro(_ macro: Macro) {
        if let index = macros.firstIndex(where: { $0.id == macro.id }) {
            macros[index] = macro
        } else {
            macros.append(macro)
        }
        persistMacros()
        if let other = macros.first(where: { $0.conflicts(with: macro) }) {
            report("Atenção: \"\(other.name)\" usa o mesmo gatilho \(macro.triggerSummary) — só uma vai disparar.",
                   isError: true)
        } else {
            report("Macro \"\(macro.name)\" salva")
        }
    }

    func deleteMacro(_ macro: Macro) {
        macros.removeAll { $0.id == macro.id }
        persistMacros()
        report("Macro \"\(macro.name)\" removida")
    }

    func setMacroEnabled(_ macro: Macro, _ enabled: Bool) {
        guard let index = macros.firstIndex(where: { $0.id == macro.id }) else { return }
        macros[index].enabled = enabled
        persistMacros()
    }

    private func persistMacros() {
        try? macroStore.save(MacroSet(macros: macros))
        syncMacroEngine()
    }

    // MARK: - Perfis

    func persist() {
        try? store.save(profile)
        profileNames = store.list()
    }

    func saveProfile(as name: String) {
        var copy = profile
        copy.name = name
        profile = copy
        persist()
        report("Perfil \"\(name)\" salvo")
    }

    func loadProfile(_ name: String) {
        guard let loaded = store.loadIfExists(name: name) else {
            report("Perfil \"\(name)\" não pôde ser lido", isError: true)
            return
        }
        profile = loaded
        applyCurrentProfile()
    }

    func applyCurrentProfile() {
        guard let keyboard = connection.keyboard else {
            report("Conecte o teclado pelo cabo USB para aplicar.", isError: true)
            return
        }
        do {
            try keyboard.apply(profile)
            report("Perfil \"\(profile.name)\" aplicado ao teclado")
        } catch {
            report(describe(error), isError: true)
        }
    }

    func deleteProfile(_ name: String) {
        try? store.delete(name: name)
        profileNames = store.list()
        report("Perfil \"\(name)\" removido")
    }

    // MARK: - Mensagens

    func report(_ message: String, isError: Bool = false) {
        status = message
        statusIsError = isError
    }

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
