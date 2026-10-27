//
//  Codecs.swift
//  Montagem dos buffers HID da Royal Kludge.
//
//  Copyright (C) 2026 RKG68Mac
//  Protocolo derivado do Rangoli (keyboardconfiguratorcontroller.cpp)
//  Copyright (C) 2023 Debayan Sutradhar (rnayabed)
//  e do Kludge Knight (BufferCodec.ts / LightingCodec.ts).
//
//  Este programa é software livre: você pode redistribuí-lo e/ou modificá-lo
//  sob os termos da GNU General Public License versão 3 ou posterior.
//  Ver o arquivo LICENSE na raiz do projeto.
//

import Foundation

/// Todo tráfego de configuração é um feature report de 65 bytes cujo primeiro
/// byte é o report ID 0x0A.
public enum RKProtocol {
    public static let reportID: UInt8 = 0x0A
    public static let bufferSize = 65
}

/// Cor de 8 bits por canal, como o firmware espera.
public struct RKColor: Hashable, Sendable, Codable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public static let white = RKColor(r: 255, g: 255, b: 255)
    public static let black = RKColor(r: 0, g: 0, b: 0)

    /// Aceita `#RRGGBB` ou `RRGGBB`.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(r: UInt8((value >> 16) & 0xFF),
                  g: UInt8((value >> 8) & 0xFF),
                  b: UInt8(value & 0xFF))
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Codifica o mapa de teclas nos 9 buffers de remap.
///
/// Layout: 9 buffers de 65 bytes. Cada tecla ocupa 4 bytes em
/// `bufferIndex * 4` dentro do espaço contínuo de 585 bytes; o buffer 1
/// carrega 5 bytes de cabeçalho e os demais 3.
public enum RemapCodec {
    static let numBuffers = 9
    static let bytesPerKey = 4

    public static func encode(mappings: [Int: FirmwareCode], config: KeyboardConfig) -> [[UInt8]] {
        var flat = [UInt8](repeating: 0, count: numBuffers * RKProtocol.bufferSize)

        // Toda tecla é escrita, mesmo sem remap: o firmware recebe o perfil
        // inteiro, então omitir uma tecla a zeraria.
        for key in config.keys {
            let code = mappings[key.bufferIndex] ?? key.keyInfo.fw
            write(code, into: &flat, at: key.bufferIndex * bytesPerKey)
        }

        var buffers: [[UInt8]] = []
        var cursor = 0
        for i in 0..<numBuffers {
            var buffer = [UInt8](repeating: 0, count: RKProtocol.bufferSize)
            buffer[0] = RKProtocol.reportID
            buffer[1] = UInt8(numBuffers)
            buffer[2] = UInt8(i + 1)
            if i == 0 {
                buffer[3] = 0x01
                buffer[4] = 0xF8
            }
            let dataStart = (i == 0) ? 5 : 3
            for position in dataStart..<RKProtocol.bufferSize where cursor < flat.count {
                buffer[position] = flat[cursor]
                cursor += 1
            }
            buffers.append(buffer)
        }
        return buffers
    }

    /// Grava o firmware code em 4 bytes big-endian, com o mesmo truncamento
    /// por faixa que o software oficial usa.
    static func write(_ code: FirmwareCode, into buffer: inout [UInt8], at offset: Int) {
        guard offset + 3 < buffer.count else { return }
        buffer[offset] = UInt8((code >> 24) & 0xFF)
        buffer[offset + 1] = UInt8((code >> 16) & 0xFF)
        buffer[offset + 2] = UInt8((code >> 8) & 0xFF)
        buffer[offset + 3] = UInt8(code & 0xFF)
    }
}

/// Ajustes globais de iluminação: um único buffer.
public struct LightingSettings: Hashable, Sendable, Codable {
    /// Índice do modo (1-21), igual ao `LedOpt<n>` do KB.ini.
    public var modeIndex: Int
    /// 1 = muito lenta ... 5 = muito rápida.
    public var speed: Int
    /// 1 a 5.
    public var brightness: Int
    public var color: RKColor
    public var randomColor: Bool
    /// 1=5min, 2=10min, 3=20min, 4=30min, 5=nunca dormir.
    public var sleep: Int

    public init(modeIndex: Int, speed: Int = 3, brightness: Int = 5,
                color: RKColor = .white, randomColor: Bool = false, sleep: Int = 5) {
        self.modeIndex = modeIndex
        self.speed = speed
        self.brightness = brightness
        self.color = color
        self.randomColor = randomColor
        self.sleep = sleep
    }
}

public enum LightingCodec {
    /// Maior índice de LED que cabe nos 7 buffers (3 bytes por índice).
    public static let maxPerKeyIndex = (7 * RKProtocol.bufferSize) / 3 - 1

    public static func encodeStandard(_ settings: LightingSettings) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: RKProtocol.bufferSize)
        buffer[0] = RKProtocol.reportID
        buffer[1] = 0x01 // total de buffers
        buffer[2] = 0x01 // índice do buffer
        buffer[3] = 0x02 // subcomando
        buffer[4] = 0x29 // parâmetro do subcomando

        buffer[5] = UInt8(clamping: settings.modeIndex)
        buffer[6] = 0x00
        buffer[7] = UInt8(clamping: max(1, min(5, settings.speed)))
        buffer[8] = UInt8(clamping: max(0, min(5, settings.brightness)))

        if !settings.randomColor {
            buffer[9] = settings.color.r
            buffer[10] = settings.color.g
            buffer[11] = settings.color.b
        }
        buffer[12] = settings.randomColor ? 0x01 : 0x00
        buffer[13] = UInt8(clamping: max(1, min(5, settings.sleep)))
        return buffer
    }

    /// Restauração de fábrica, como o software oficial da RK faz.
    ///
    /// É o mesmo buffer da iluminação, mas com `[6] = 0x01` — o byte que a
    /// documentação da comunidade dava como reservado. Capturas do software
    /// oficial em dois modelos (F68 e S70) mostram esse byte em 1 nos comandos
    /// "reset keyboard data" e "restore factory settings", e em 0 em todo o
    /// resto. Os demais valores são os da captura: modo 1, velocidade 4,
    /// brilho 5, sleep 2.
    ///
    /// - Parameter trailingC0: uma das capturas traz `0xC0` no último byte e a
    ///   outra não; provável resíduo, exposto aqui para tentar se o reset
    ///   simples não pegar.
    public static func encodeFactoryReset(trailingC0: Bool = false) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: RKProtocol.bufferSize)
        buffer[0] = RKProtocol.reportID
        buffer[1] = 0x01
        buffer[2] = 0x01
        buffer[3] = 0x02
        buffer[4] = 0x29
        buffer[5] = 0x01 // modo 1
        buffer[6] = 0x01 // flag de restauração
        buffer[7] = 0x04 // velocidade
        buffer[8] = 0x05 // brilho
        buffer[13] = 0x02 // sleep
        if trailingC0 { buffer[RKProtocol.bufferSize - 1] = 0xC0 }
        return buffer
    }

    /// Cor por tecla (modo Customize): 7 buffers, 3 bytes por tecla em
    /// `bufferIndex * 3`.
    public static func encodePerKey(_ colors: [Int: RKColor]) -> [[UInt8]] {
        let numBuffers = 7
        var flat = [UInt8](repeating: 0, count: numBuffers * RKProtocol.bufferSize)

        for (bufferIndex, color) in colors {
            let offset = bufferIndex * 3
            guard offset >= 0, offset + 2 < flat.count else { continue }
            flat[offset] = color.r
            flat[offset + 1] = color.g
            flat[offset + 2] = color.b
        }

        var buffers: [[UInt8]] = []
        var cursor = 0
        for i in 0..<numBuffers {
            var buffer = [UInt8](repeating: 0, count: RKProtocol.bufferSize)
            buffer[0] = RKProtocol.reportID
            buffer[1] = UInt8(numBuffers)
            buffer[2] = UInt8(i + 1)
            if i == 0 {
                buffer[3] = 0x03
                buffer[4] = 0x7E
                buffer[5] = 0x01
            }
            let dataStart = (i == 0) ? 6 : 3
            for position in dataStart..<RKProtocol.bufferSize where cursor < flat.count {
                buffer[position] = flat[cursor]
                cursor += 1
            }
            buffers.append(buffer)
        }
        return buffers
    }
}
