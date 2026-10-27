//
//  LightingTab.swift
//  Modos de iluminação. Quais controles aparecem vem do KB.ini — cada modo
//  declara se aceita velocidade, brilho, cor fixa ou cor aleatória, então a
//  interface não oferece o que o firmware ignoraria.
//

import SwiftUI
import RKCore

struct LightingTab: View {
    @Bindable var controller: KeyboardController
    let config: KeyboardConfig
    let imageURL: URL?

    @State private var settings: LightingSettings
    @State private var draftCalibration: ColorCalibration?
    @State private var showingAddPreset = false
    @State private var presetName = ""
    @State private var presetNote = ""
    /// Fator em edição no slider de correção por tecla, para a escrita só
    /// acontecer quando o dedo solta.
    @State private var draftKeyFactor: Double?

    init(controller: KeyboardController, config: KeyboardConfig, imageURL: URL?) {
        self.controller = controller
        self.config = config
        self.imageURL = imageURL
        _settings = State(initialValue: controller.profile.lighting
            ?? LightingSettings(modeIndex: config.lightingModes.first?.index ?? 1))
    }

    private var mode: LightingMode? {
        config.lightingModes.first { $0.index == settings.modeIndex }
    }

    private var isCustomMode: Bool {
        config.customColorMode?.index == settings.modeIndex
    }

    var body: some View {
        if !config.hasLighting {
            ContentUnavailableView("Sem iluminação configurável",
                                   systemImage: "lightbulb.slash",
                                   description: Text("Este modelo não declara modos de luz no catálogo da RK."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    modePicker
                    if let mode {
                        controls(for: mode)
                    }
                    if isCustomMode && config.isRGB {
                        perKeySection
                    }
                    if config.isRGB {
                        paletteSection
                        calibrationSection
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Efeito")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Efeito", selection: $settings.modeIndex) {
                ForEach(config.lightingModes) { mode in
                    Text("\(mode.index). \(mode.name)").tag(mode.index)
                }
            }
            .labelsHidden()
            .onChange(of: settings.modeIndex) { _, _ in apply() }
        }
    }

    @ViewBuilder
    private func controls(for mode: LightingMode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if mode.flags.brightness {
                slider("Brilho", value: $settings.brightness, range: 1...5,
                       labels: ["mínimo", "baixo", "médio", "alto", "máximo"])
            }
            if mode.flags.speed {
                slider("Velocidade", value: $settings.speed, range: 1...5,
                       labels: ["muito lenta", "lenta", "normal", "rápida", "muito rápida"])
            }
            if mode.flags.colorPicker {
                HStack(spacing: 12) {
                    ColorPicker("Cor", selection: Binding(
                        get: { Color(rgb: settings.color) },
                        set: { settings.color = $0.rgbColor; settings.randomColor = false; apply() }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    Text(settings.randomColor ? "cores aleatórias" : settings.color.hex)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if mode.flags.random {
                        Toggle("Aleatória", isOn: Binding(
                            get: { settings.randomColor },
                            set: { settings.randomColor = $0; apply() }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    Spacer()
                }
            }

            Picker("Dormir depois de", selection: Binding(
                get: { settings.sleep },
                set: { settings.sleep = $0; apply() }
            )) {
                Text("5 min").tag(1)
                Text("10 min").tag(2)
                Text("20 min").tag(3)
                Text("30 min").tag(4)
                Text("nunca").tag(5)
            }
            .pickerStyle(.segmented)
            .fixedSize()

            if mode.flags.direction > 0 {
                Text(mode.flags.direction == 1
                     ? "Este efeito anima na horizontal."
                     : "Este efeito anima na vertical.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func slider(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(labels[min(max(value.wrappedValue - range.lowerBound, 0), labels.count - 1)])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0.rounded()) }
            ), in: Double(range.lowerBound)...Double(range.upperBound),
               step: 1, onEditingChanged: { editing in if !editing { apply() } })
        }
    }

    /// Ajuste de branco. O teclado aciona os três canais com o mesmo PWM, mas
    /// os LEDs não rendem igual — no G68 o verde é o mais fraco, então
    /// `#FFFFFF` sai rosado. O ganho só abaixa canal, nunca levanta: branco
    /// calibrado acende um pouco menos, e é o preço de ser branco.
    private var calibrationSection: some View {
        let cal = activeCalibration
        return VStack(alignment: .leading, spacing: 10) {
            Divider()
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("O teclado não rende os três canais igual. Abaixe o canal que estiver sobrando até o branco ficar branco.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    gainSlider("Vermelho", \ColorCalibration.r)
                    gainSlider("Verde", \ColorCalibration.g)
                    gainSlider("Azul", \ColorCalibration.b)

                    if cal.isLoadDependent {
                        Text("O ganho sobe com a carga: foi medido que o branco neutro pede vermelho 28 com uma tecla acesa e 64 com as 68. Os controles acima são o valor com **uma** tecla; o resto segue a curva \(String(format: "n^%.2f", cal.loadExponentR)).")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        // Com dependência de carga, um número só mentiria: o
                        // mesmo branco sai diferente com 1 LED e com o teclado
                        // cheio. Mostra as duas pontas.
                        if cal.isLoadDependent {
                            Text("#FFFFFF sai como \(cal.apply(.white, litCount: 1).hex) com 1 LED e \(cal.apply(.white, litCount: config.keyCount).hex) com o teclado cheio")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("#FFFFFF sai como \(cal.apply(.white, litCount: litCount).hex)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Medido neste G68") {
                            controller.calibration = .g68Measured
                        }
                        Button("Cor crua") {
                            controller.calibration = .identity
                        }
                        .disabled(cal.isIdentity)
                    }
                    Text("Vale para a cor fixa dos efeitos e para a cor por tecla. Efeitos que geram as próprias cores (arco-íris e afins) são calculados no firmware e não passam por aqui.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Divider()
                    Text("Correção por tecla")
                        .font(.callout.weight(.semibold))
                    keyCorrectionSection
                }
                .padding(.top, 6)
            } label: {
                HStack {
                    Text("Ajuste de branco")
                        .font(.callout.weight(.semibold))
                    Text(cal.isIdentity ? "cor crua" : cal.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Valor em edição enquanto o slider está sendo arrastado.
    ///
    /// Sem isto, cada quadro do arrasto viraria uma escrita no firmware —
    /// dezenas de feature reports por segundo num canal que não gosta de
    /// comandos intercalados. O teclado só recebe quando o dedo solta.
    private var activeCalibration: ColorCalibration {
        draftCalibration ?? controller.calibration
    }

    private func gainSlider(_ title: String, _ keyPath: WritableKeyPath<ColorCalibration, Double>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            Slider(value: Binding(
                get: { activeCalibration[keyPath: keyPath] },
                set: { value in
                    var next = activeCalibration
                    next[keyPath: keyPath] = value
                    draftCalibration = next
                }
            // A faixa começa em 0.05: o vermelho medido neste G68 é 0.11, e um
            // mínimo de 0.2 deixaria o slider mostrando um valor que não é o
            // gravado.
            ), in: 0.05...1, onEditingChanged: { editing in
                guard !editing, let draft = draftCalibration else { return }
                draftCalibration = nil
                controller.calibration = draft
            })
            Text(String(format: "%.2f", activeCalibration[keyPath: keyPath]))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var perKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Text("Cor por tecla")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                ColorPicker("Pincel", selection: Binding(
                    get: { Color(rgb: controller.paintColor) },
                    set: { controller.paintColor = $0.rgbColor }
                ), supportsOpacity: false)
                .labelsHidden()
                Button("Limpar todas") { controller.clearAllKeyColors() }
                    .disabled(controller.profile.perKeyColors.isEmpty)
            }
            if !config.keySets.isEmpty {
                HStack(spacing: 8) {
                    Text("Conjuntos da RK")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(config.keySets) { set in
                        Button(set.name) { controller.applyKeySet(set) }
                            .disabled(!controller.isConnected)
                    }
                    Text("acendem só essas teclas e apagam o resto")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text("Clique nas teclas para pintar com a cor do pincel. Clique de novo numa tecla já pintada para apagá-la.")
                .font(.caption)
                .foregroundStyle(.secondary)

            KeyboardMapView(
                config: config,
                imageURL: imageURL,
                remaps: [:],
                keyColors: controller.profile.perKeyColors,
                showKeyColors: true,
                selection: $controller.selectedKeyIndex,
                onTap: { index in
                    if controller.profile.perKeyColors[index] != nil {
                        controller.clearKeyColor(index)
                    } else {
                        controller.paintKey(index)
                    }
                }
            )
        }
    }

    // MARK: - Cores validadas

    /// Quantos LEDs a cor corrente vai acender. É o parâmetro que decide o
    /// ganho (medido: o mesmo byte muda de cor com a carga), e por isso entra
    /// no preset junto com os bytes.
    private var litCount: Int {
        isCustomMode
            ? max(controller.profile.perKeyColors.count, 1)
            : config.keyCount
    }

    /// Os bytes que o teclado está recebendo agora — o que o preset guarda.
    private var sentColor: RKColor {
        activeCalibration.apply(settings.color, litCount: litCount)
    }

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Text("Cores validadas")
                    .font(.callout.weight(.semibold))
                Text("\(controller.palette.entries.count) preset(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Registrar a cor atual…") {
                    presetName = ""
                    presetNote = ""
                    showingAddPreset = true
                }
                .disabled(mode?.flags.colorPicker != true)
            }

            Text("O preset guarda o byte que o teclado recebeu, não a cor pedida — recalibrar não joga fora a validação. Ao aplicar, vai ao teclado sem passar pela calibração.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if controller.palette.entries.isEmpty {
                Text("Nada registrado ainda. Ajuste a cor até ficar certa no teclado e clique em “Registrar a cor atual”.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)],
                          alignment: .leading, spacing: 10) {
                    ForEach(controller.palette.entries) { entry in
                        swatch(entry)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddPreset) { addPresetSheet }
    }

    private func swatch(_ entry: PaletteEntry) -> some View {
        Button {
            controller.applyPaletteEntry(entry)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(rgb: entry.color))
                    .frame(height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    )
                Text(entry.name)
                    .font(.caption)
                    .lineLimit(1)
                Text(entry.color.hex)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(entry.summary)
        .contextMenu {
            Button("Usar como pincel") { controller.paintColor = entry.color }
            Button("Remover", role: .destructive) { controller.removePaletteEntry(entry) }
        }
        .disabled(!controller.isConnected)
    }

    private var addPresetSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Registrar cor validada")
                .font(.headline)
            Text("Guarda o byte que está no teclado agora, com a carga em que você julgou. Não guarda a cor pedida: assim o preset sobrevive a uma recalibração.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Nome").font(.caption).foregroundStyle(.secondary)
                    TextField("laranja de verdade", text: $presetName)
                        .frame(width: 220)
                }
                GridRow {
                    Text("Nota").font(.caption).foregroundStyle(.secondary)
                    TextField("opcional — o que o olho viu", text: $presetNote)
                        .frame(width: 220)
                }
                GridRow {
                    Text("Byte").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(rgb: sentColor))
                            .frame(width: 22, height: 16)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator, lineWidth: 0.5))
                        Text(sentColor.hex)
                            .font(.caption.monospaced())
                        if sentColor != settings.color {
                            Text("(pedido \(settings.color.hex))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                GridRow {
                    Text("Carga").font(.caption).foregroundStyle(.secondary)
                    Text("\(litCount) LED(s) acesos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancelar") { showingAddPreset = false }
                Button("Registrar") {
                    controller.addPaletteEntry(name: presetName, color: sentColor,
                                               litCount: litCount, note: presetNote)
                    showingAddPreset = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    // MARK: - Correção por tecla

    /// Teclas com correção, em nome legível — mostrar quais é mais útil que
    /// pintar o desenho, que já carrega a cor por tecla.
    private var correctedKeyNames: String {
        let names = activeCalibration.keyScale.keys
            .sorted()
            .compactMap { config.key(bufferIndex: $0)?.keyInfo.displayLabel }
        return names.joined(separator: ", ")
    }

    private var keyCorrectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("O desvio de cor também varia com a posição: no G68 a região das setas puxa para o rosa com o teclado cheio. A causa é a mesma do efeito de carga — o LED vermelho tem tensão direta menor, e onde falta tensão é ele que sobra.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Acender branco sólido") {
                    controller.applySolidUniform(.white)
                }
                .disabled(!controller.isConnected)
                Text("desenha pelo Customize, tecla por tecla — é o único jeito de a correção por posição valer")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text("Clique na tecla que está fora do tom e abaixe o vermelho dela.")
                .font(.caption)
                .foregroundStyle(.secondary)

            KeyboardMapView(
                config: config,
                imageURL: imageURL,
                remaps: [:],
                keyColors: controller.profile.perKeyColors,
                showKeyColors: true,
                selection: $controller.selectedKeyIndex,
                onTap: { index in controller.selectedKeyIndex = index }
            )

            if let index = controller.selectedKeyIndex,
               let key = config.key(bufferIndex: index) {
                keyFactorSlider(index: index, label: key.keyInfo.displayLabel)
            } else {
                Text("Nenhuma tecla selecionada.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !activeCalibration.keyScale.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Corrigidas:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(correctedKeyNames)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Apagar todas") { controller.clearKeyScales() }
                }
            }
        }
    }

    private func keyFactorSlider(index: Int, label: String) -> some View {
        let current = draftKeyFactor ?? controller.keyScale(index).r
        return HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(width: 90, alignment: .leading)
            Text("vermelho")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { current },
                set: { draftKeyFactor = $0 }
            ), in: 0.3...1, onEditingChanged: { editing in
                guard !editing, let draft = draftKeyFactor else { return }
                draftKeyFactor = nil
                var scale = controller.keyScale(index)
                scale.r = draft
                controller.setKeyScale(index, scale)
            })
            Text(String(format: "%.2f×", current))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
            Button("1.00×") {
                draftKeyFactor = nil
                controller.setKeyScale(index, .neutral)
            }
            .controlSize(.small)
            .disabled(controller.keyScale(index).isNeutral)
        }
    }

    private func apply() {
        controller.applyLighting(settings)
    }
}

extension Color {
    init(rgb: RKColor) {
        self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }

    /// Converte para sRGB antes de extrair os componentes: o ColorPicker pode
    /// devolver cor em outro espaço, e o firmware só entende 0-255 sRGB.
    var rgbColor: RKColor {
        let converted = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return RKColor(r: UInt8((converted.redComponent * 255).rounded()),
                        g: UInt8((converted.greenComponent * 255).rounded()),
                        b: UInt8((converted.blueComponent * 255).rounded()))
    }
}
