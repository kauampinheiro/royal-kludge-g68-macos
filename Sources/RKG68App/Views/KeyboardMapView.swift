//
//  KeyboardMapView.swift
//  Desenha o teclado usando a própria arte do software oficial e os
//  retângulos que o KB.ini dá para cada tecla — por isso o mapa confere com
//  o teclado físico, inclusive nas teclas de tamanho irregular.
//

import SwiftUI
import RKCore

struct KeyboardMapView: View {
    let config: KeyboardConfig
    let imageURL: URL?
    /// Remaps ativos, para marcar as teclas alteradas.
    let remaps: [Int: VKCode]
    /// Cores por tecla, exibidas quando o modo de cor própria está ativo.
    let keyColors: [Int: RKColor]
    let showKeyColors: Bool
    @Binding var selection: Int?
    /// Chamado depois da seleção — a aba de cores usa isso para pintar.
    var onTap: ((Int) -> Void)?

    /// A arte, carregada uma vez por URL — ler o PNG do disco dentro do `body`
    /// significava relê-lo a cada redesenho.
    @State private var art: NSImage?

    private var bounds: (width: Int, height: Int) { config.layoutBounds }

    /// Espaço de coordenadas em que os retângulos do KB.ini foram escritos:
    /// o da imagem, em pixels.
    ///
    /// Não dá para usar `layoutBounds` aqui. Ele é a extensão das teclas, e as
    /// teclas param antes da borda da arte — no G68 são 710×232 contra 716×246
    /// de imagem. Escalar por ele esticava o mapa ~5% na vertical, e as teclas
    /// de baixo acabavam desencontradas do desenho.
    private var canvas: CGSize {
        if let rep = art?.representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return CGSize(width: bounds.width, height: bounds.height)
    }

    var body: some View {
        let canvas = self.canvas

        return GeometryReader { geometry in
            // A arte tem proporção fixa; o layout acompanha a largura
            // disponível para o mapa casar com a imagem em qualquer janela.
            let scale = geometry.size.width / canvas.width
            let height = canvas.height * scale

            ZStack(alignment: .topLeading) {
                if let art {
                    Image(nsImage: art)
                        .resizable()
                        .frame(width: geometry.size.width, height: height)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary)
                        .frame(width: geometry.size.width, height: height)
                }

                ForEach(config.keys) { key in
                    keyOverlay(key, scale: scale)
                }
            }
        }
        .aspectRatio(canvas.width / canvas.height, contentMode: .fit)
        .task(id: imageURL) {
            art = imageURL.flatMap { NSImage(contentsOf: $0) }
        }
    }

    @ViewBuilder
    private func keyOverlay(_ key: KeyboardKey, scale: CGFloat) -> some View {
        let width = CGFloat(key.rect.right - key.rect.left) * scale
        let height = CGFloat(key.rect.bottom - key.rect.top) * scale
        let isSelected = selection == key.bufferIndex
        let remappedVK = remaps[key.bufferIndex]
        let color = showKeyColors ? keyColors[key.bufferIndex] : nil

        ZStack {
            if let color {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: Double(color.r) / 255,
                                green: Double(color.g) / 255,
                                blue: Double(color.b) / 255))
                    .opacity(0.85)
            }
            if remappedVK != nil {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor.opacity(color == nil ? 0.8 : 0.35))
            }
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)

            // Só a tecla remapeada recebe rótulo: a arte já traz a legenda
            // original de todas as outras.
            if let remappedVK, let info = Keycode.info(vk: remappedVK) {
                Text(info.displayLabel)
                    .font(.system(size: max(6, min(height * 0.34, 11)), weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 1)
            }
        }
        .frame(width: width, height: height)
        // A ordem aqui importa: `offset` só desloca o desenho, não o quadro de
        // layout. Com `contentShape` depois dele, a área clicável de toda tecla
        // ficava ancorada no canto do ZStack, empilhada sobre as outras — quem
        // respondia ao clique era a última tecla grande desenhada por cima
        // (Enter no canto, Espaço na fileira de números). O `offset` precisa
        // ser o modificador mais externo, para levar junto a área de toque.
        .contentShape(Rectangle())
        .onTapGesture {
            selection = key.bufferIndex
            onTap?(key.bufferIndex)
        }
        .help(tooltip(for: key, remappedVK: remappedVK))
        .offset(x: CGFloat(key.rect.left) * scale, y: CGFloat(key.rect.top) * scale)
    }

    private func tooltip(for key: KeyboardKey, remappedVK: VKCode?) -> String {
        let base = "\(key.keyInfo.displayLabel)  ·  índice #\(key.bufferIndex)"
        guard let remappedVK, let info = Keycode.info(vk: remappedVK) else { return base }
        return base + "  →  \(info.displayLabel)"
    }
}
