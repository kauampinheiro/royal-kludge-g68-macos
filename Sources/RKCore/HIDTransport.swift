//
//  HIDTransport.swift
//  Camada IOKit: descoberta da interface de configuração do teclado e envio
//  dos feature reports.
//
//  Um teclado RK publica várias collections HID. A configuração só trafega
//  pela collection de usage page 0x01 / usage 0x80 (System Control) — a de
//  usage 0x06 (Keyboard) é reservada pelo sistema e nem deve ser aberta.
//

import Foundation
import IOKit
import IOKit.hid

public struct RKHIDDeviceInfo: Sendable, Identifiable {
    public let vendorID: Int
    public let productID: Int
    public let product: String?
    public let manufacturer: String?
    public let serialNumber: String?
    public let primaryUsagePage: Int
    public let primaryUsage: Int
    public let maxFeatureReportSize: Int
    public let locationID: Int
    public let transport: String?

    /// PID em 4 dígitos hex minúsculos, como nas pastas `Dev/<PID>`.
    public var pidString: String { String(format: "%04x", productID) }

    public var id: String { "\(vendorID)-\(productID)-\(locationID)-\(primaryUsage)" }

    /// A collection pela qual o software oficial conversa com o teclado.
    public var isConfigurationInterface: Bool {
        primaryUsagePage == 0x01 && primaryUsage == 0x80
    }
}

/// Estado da autorização de *Monitoramento de Entrada* (TCC
/// `kTCCServiceListenEvent`), exigida pelo macOS para abrir qualquer
/// collection HID de um dispositivo que se declara teclado — inclusive a de
/// configuração (usage page 0x01 / usage 0x80).
public enum RKHIDAccess: Sendable, Equatable {
    /// Autorizado: `IOHIDDeviceOpen` vai funcionar.
    case granted
    /// O sistema nunca perguntou. Sem chamar `IOHIDRequestAccess` o diálogo
    /// nunca aparece e o `open` só devolve `kIOReturnNotPermitted`.
    case notAsked
    /// O usuário recusou, ou a autorização ficou obsoleta (ver `requestAccess`).
    case denied
}

public enum RKHIDError: Error, LocalizedError {
    case noDeviceFound
    case noConfigurationInterface(found: [RKHIDDeviceInfo])
    case openFailed(IOReturn)
    case setReportFailed(IOReturn, buffer: Int)
    case readFailed(IOReturn)
    /// `wasAsked == false`: o diálogo acabou de ser pedido e a resposta ainda
    /// não chegou. `true`: está recusado de fato em Ajustes do Sistema.
    case accessDenied(wasAsked: Bool)

    public var errorDescription: String? {
        switch self {
        case .noDeviceFound:
            return """
            Nenhum teclado Royal Kludge (VID 0x258A) encontrado no barramento USB.
            Conecte o teclado pelo cabo USB — nos modos 2.4G e Bluetooth o canal \
            de configuração não fica acessível.
            """
        case .noConfigurationInterface(let found):
            let list = found.map { "  · \($0.product ?? "?") — usage page 0x\(String($0.primaryUsagePage, radix: 16)) / usage 0x\(String($0.primaryUsage, radix: 16))" }
                .joined(separator: "\n")
            return """
            O teclado foi encontrado, mas sem a interface de configuração \
            (usage page 0x01 / usage 0x80). Collections vistas:
            \(list)
            """
        case .openFailed(let code):
            if code == kIOReturnNotPermitted || code == kIOReturnNotPrivileged {
                return RKHIDError.accessDenied(wasAsked: true).errorDescription
            }
            return "Falha ao abrir o dispositivo HID (IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .setReportFailed(let code, let buffer):
            return "Falha ao enviar o buffer \(buffer) (IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .readFailed(let code):
            return "Falha ao ler do dispositivo (IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .accessDenied(let wasAsked):
            guard wasAsked else {
                return """
                O macOS pediu sua autorização para este app em Monitoramento de \
                Entrada. Autorize no diálogo que apareceu e clique em Procurar.
                """
            }
            return """
            O macOS negou o acesso ao dispositivo HID. Abra Ajustes do Sistema › \
            Privacidade e Segurança › Monitoramento de Entrada e marque \
            "RK G68". Se já estiver marcado, desmarque e marque de novo; se nem \
            assim, rode `tccutil reset ListenEvent com.kauampinheiro.rkg68` no \
            terminal e abra o app outra vez.
            """
        }
    }
}

public final class RKHIDTransport {
    private let device: IOHIDDevice
    public let info: RKHIDDeviceInfo
    private var isOpen = false

    private init(device: IOHIDDevice, info: RKHIDDeviceInfo) {
        self.device = device
        self.info = info
    }

    deinit {
        if isOpen { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
    }

    // MARK: - Autorização

    /// URL que abre direto o painel de Monitoramento de Entrada.
    public static let inputMonitoringSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    )!

    /// Lê o estado da autorização sem provocar diálogo nenhum.
    public static var access: RKHIDAccess {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied:  return .denied
        default:                      return .notAsked
        }
    }

    /// Pede a autorização ao sistema, mostrando o diálogo na primeira vez.
    ///
    /// Sem esta chamada o diálogo **nunca** aparece: `IOHIDDeviceOpen` apenas
    /// devolve `kIOReturnNotPermitted` e o app fica preso num erro que o
    /// usuário não tem como resolver, porque nem chega a constar na lista de
    /// Monitoramento de Entrada.
    ///
    /// Depois de recusado, o macOS não pergunta de novo — daí só sai marcando
    /// na mão em Ajustes do Sistema, ou zerando o registro com
    /// `tccutil reset ListenEvent com.kauampinheiro.rkg68`.
    ///
    /// Com assinatura ad-hoc a autorização fica presa ao cdhash do bundle, e
    /// esse hash muda a cada alteração de código: a permissão do build
    /// anterior para de valer mesmo continuando marcada em Ajustes. Por isso
    /// `build-app.sh` zera o registro a cada build.
    @discardableResult
    public static func requestAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    // MARK: - Descoberta

    /// Todas as collections HID de teclados RK presentes na máquina.
    public static func discoverAll() -> [(device: IOHIDDevice, info: RKHIDDeviceInfo)] {
        guard let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone)) as IOHIDManager? else {
            return []
        }

        let matching: [String: Any] = [kIOHIDVendorIDKey: rkVendorID]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        defer {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }

        return set.map { device in (device, describe(device)) }
            .sorted { $0.info.id < $1.info.id }
    }

    /// Só as interfaces de configuração — as que aceitam os feature reports.
    public static func discoverConfigurationInterfaces() -> [(device: IOHIDDevice, info: RKHIDDeviceInfo)] {
        discoverAll().filter { $0.info.isConfigurationInterface }
    }

    /// Abre o primeiro teclado RK configurável encontrado.
    /// - Parameter pid: restringe a um PID específico (hex, com ou sem `0x`).
    public static func open(pid: String? = nil) throws -> RKHIDTransport {
        let all = discoverAll()
        guard !all.isEmpty else { throw RKHIDError.noDeviceFound }

        var candidates = all.filter { $0.info.isConfigurationInterface }
        if let pid {
            let wanted = pid.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive).lowercased()
            candidates = candidates.filter { $0.info.pidString == wanted }
        }

        guard let chosen = candidates.first else {
            throw RKHIDError.noConfigurationInterface(found: all.map(\.info))
        }

        // O macOS exige Monitoramento de Entrada para abrir qualquer collection
        // de um dispositivo que se declara teclado, inclusive a de
        // configuração. Pedir antes de abrir é o que faz o diálogo aparecer.
        if access == .notAsked, !requestAccess() {
            throw RKHIDError.accessDenied(wasAsked: access != .notAsked)
        }

        let result = IOHIDDeviceOpen(chosen.device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw RKHIDError.openFailed(result) }

        let transport = RKHIDTransport(device: chosen.device, info: chosen.info)
        transport.isOpen = true
        return transport
    }

    static func describe(_ device: IOHIDDevice) -> RKHIDDeviceInfo {
        func int(_ key: String) -> Int {
            (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
        }
        func string(_ key: String) -> String? {
            IOHIDDeviceGetProperty(device, key as CFString) as? String
        }

        return RKHIDDeviceInfo(
            vendorID: int(kIOHIDVendorIDKey),
            productID: int(kIOHIDProductIDKey),
            product: string(kIOHIDProductKey),
            manufacturer: string(kIOHIDManufacturerKey),
            serialNumber: string(kIOHIDSerialNumberKey),
            primaryUsagePage: int(kIOHIDPrimaryUsagePageKey),
            primaryUsage: int(kIOHIDPrimaryUsageKey),
            maxFeatureReportSize: int(kIOHIDMaxFeatureReportSizeKey),
            locationID: int(kIOHIDLocationIDKey),
            transport: string(kIOHIDTransportKey)
        )
    }

    // MARK: - Escrita

    /// Envia um buffer de 65 bytes como feature report. O byte 0 é o report ID
    /// e vai junto do payload, como o hidapi faz no macOS.
    public func send(buffer: [UInt8]) throws {
        try send(buffers: [buffer])
    }

    /// Envia buffers em sequência. O firmware espera a sequência inteira de um
    /// comando sem intercalar outros; a pausa curta entre buffers reproduz o
    /// ritmo do software oficial e evita reports descartados.
    public func send(buffers: [[UInt8]], interBufferDelay: TimeInterval = 0.002) throws {
        for (index, buffer) in buffers.enumerated() {
            let reportID = CFIndex(buffer.first ?? RKProtocol.reportID)
            let result = buffer.withUnsafeBufferPointer { pointer -> IOReturn in
                guard let base = pointer.baseAddress else { return kIOReturnBadArgument }
                return IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, reportID, base, buffer.count)
            }
            guard result == kIOReturnSuccess else {
                throw RKHIDError.setReportFailed(result, buffer: index + 1)
            }
            if index < buffers.count - 1, interBufferDelay > 0 {
                Thread.sleep(forTimeInterval: interBufferDelay)
            }
        }
    }

    /// Lê um feature report do teclado.
    ///
    /// Rangoli e Kludge Knight tratam o teclado como write-only, mas o
    /// software oficial chama `HidD_GetFeature` — então existe caminho de
    /// leitura. Serve para inspecionar o estado real gravado no firmware.
    public func read(reportID: UInt8 = RKProtocol.reportID,
                     length: Int = RKProtocol.bufferSize) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: length)
        buffer[0] = reportID
        var size = length
        let result = buffer.withUnsafeMutableBufferPointer { pointer -> IOReturn in
            guard let base = pointer.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), base, &size)
        }
        guard result == kIOReturnSuccess else { throw RKHIDError.readFailed(result) }
        return Array(buffer.prefix(size))
    }

    public func close() {
        guard isOpen else { return }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = false
    }
}
