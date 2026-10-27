//
//  RKResources.swift
//  Acesso aos arquivos de definição que vêm do software oficial da RK
//  (Cfg.ini, Dev/<PID>/KB.ini, led.xml).
//

import Foundation

public enum RKResourcesError: Error, LocalizedError {
    case bundleNotFound
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .bundleNotFound:
            return "Pasta de recursos da RK não encontrada no bundle."
        case .fileNotFound(let path):
            return "Arquivo de definição não encontrado: \(path)"
        }
    }
}

public struct RKResources: Sendable {
    /// Raiz da árvore `rk/` (contém `Cfg.ini` e `Dev/`).
    public let root: URL

    /// Resolve a pasta `rk/` com os arquivos da RK.
    ///
    /// A busca é feita à mão de propósito: o acessador que o SwiftPM gera
    /// procura o bundle ao lado do `.app` e, se não encontra, cai num caminho
    /// absoluto da pasta de build — o que faz o app pedir acesso a Documentos
    /// do usuário e falhar quando o build sai do lugar.
    public static func bundled() throws -> RKResources {
        let fm = FileManager.default
        var candidates: [URL] = []

        // Permite apontar para outra cópia durante o desenvolvimento.
        if let override = ProcessInfo.processInfo.environment["RKG68_RESOURCES"] {
            candidates.append(URL(fileURLWithPath: override))
        }

        // Dentro de um .app: Contents/Resources/rk
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("rk"))
            candidates.append(resourceURL.appendingPathComponent("RKG68Mac_RKCore.bundle/rk"))
            candidates.append(resourceURL.appendingPathComponent("RKG68Mac_RKCore.bundle/Contents/Resources/rk"))
        }

        // Binário solto: o bundle de recursos do SwiftPM fica ao lado dele.
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() {
            candidates.append(executable.appendingPathComponent("RKG68Mac_RKCore.bundle/rk"))
            candidates.append(executable.appendingPathComponent("rk"))
            // Instalado em <prefixo>/bin: os recursos ficam em <prefixo>/share.
            let prefix = executable.deletingLastPathComponent()
            candidates.append(prefix.appendingPathComponent("share/rkg68/rk"))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("RKG68Mac_RKCore.bundle/rk"))

        // Prefixos de instalação usuais, para o CLI copiado sem os recursos.
        for prefix in ["/usr/local", "/opt/homebrew", "/opt/local"] {
            candidates.append(URL(fileURLWithPath: "\(prefix)/share/rkg68/rk"))
        }

        // Último recuo: o app instalado já carrega a árvore completa em
        // Contents/Resources/rk, então o CLI aproveita a cópia dele.
        var appRoots = ["/Applications"]
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            appRoots.insert("\(home)/Applications", at: 0)
        }
        for root in appRoots {
            candidates.append(URL(fileURLWithPath: "\(root)/RK G68.app/Contents/Resources/rk"))
        }

        guard let root = candidates.first(where: {
            var isDirectory: ObjCBool = false
            return fm.fileExists(atPath: $0.appendingPathComponent("Cfg.ini").path, isDirectory: &isDirectory)
        }) else {
            throw RKResourcesError.bundleNotFound
        }
        return RKResources(root: root)
    }

    public init(root: URL) {
        self.root = root
    }

    public var cfgIni: URL { root.appendingPathComponent("Cfg.ini") }

    /// Pasta do dispositivo. Os diretórios vêm do instalador Windows com caixa
    /// inconsistente (`013A` x `013a`), então as duas formas são testadas.
    public func deviceDirectory(pid: String) -> URL? {
        let fm = FileManager.default
        for variant in [pid.uppercased(), pid.lowercased()] {
            let url = root.appendingPathComponent("Dev/\(variant)", isDirectory: true)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    public func kbIni(pid: String) -> URL? {
        guard let dir = deviceDirectory(pid: pid) else { return nil }
        let url = dir.appendingPathComponent("KB.ini")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// `led.xml` do dispositivo, com recuo para o global em `Dev/<locale>/led.xml`.
    public func ledXML(pid: String, locale: String = "en") -> URL? {
        let fm = FileManager.default
        if let dir = deviceDirectory(pid: pid) {
            let perDevice = dir.appendingPathComponent("\(locale)/led.xml")
            if fm.fileExists(atPath: perDevice.path) { return perDevice }
        }
        let global = root.appendingPathComponent("Dev/\(locale)/led.xml")
        return fm.fileExists(atPath: global.path) ? global : nil
    }

    /// Imagem do modelo, resolvendo `KbImgUse` e a preferência por arte de LED.
    public func image(for config: KeyboardConfig) -> URL? {
        keyboardImage(pid: config.imagePID, useLEDImage: config.usesLEDImage)
            ?? keyboardImage(pid: config.imagePID, useLEDImage: !config.usesLEDImage)
            ?? keyboardImage(pid: config.pid, useLEDImage: false)
    }

    /// Imagem do teclado: `kbled.png` quando o `KB.ini` pede a arte de LED,
    /// senão `keyimg.png`. `pid` já deve ser o PID da arte (ver `KbImgUse`).
    public func keyboardImage(pid: String, useLEDImage: Bool) -> URL? {
        guard let dir = deviceDirectory(pid: pid) else { return nil }
        let url = dir.appendingPathComponent(useLEDImage ? "kbled.png" : "keyimg.png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
