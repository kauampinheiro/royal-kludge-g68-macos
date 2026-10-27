//
//  KeyCaptureField.swift
//  Captura uma combinação de teclas pressionando-a.
//
//  O layout da RK identifica teclas por VK do Windows e o event tap do macOS
//  fala em keycode próprio. Manter a tradução entre as duas tabelas seria
//  fonte garantida de erro — tecla morta, ABNT, modificador lateral. Gravar o
//  que o sistema realmente envia elimina a tradução inteira.
//

import AppKit
import SwiftUI
import RKCore

/// Nomes das teclas que não produzem caractere. O resto sai de
/// `charactersIgnoringModifiers`.
enum KeyCodeNames {
    static let table: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Espaço", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
        71: "Clear", 76: "↩ (num)",
    ]

    static func label(for event: NSEvent) -> String {
        if let known = table[event.keyCode] { return known }
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty,
           let first = chars.unicodeScalars.first, first.value >= 32, first.value != 127 {
            return chars.uppercased()
        }
        return "tecla \(event.keyCode)"
    }

    static func modifiers(for event: NSEvent) -> MacroModifiers {
        var out: MacroModifiers = []
        if event.modifierFlags.contains(.shift) { out.insert(.shift) }
        if event.modifierFlags.contains(.control) { out.insert(.control) }
        if event.modifierFlags.contains(.option) { out.insert(.option) }
        if event.modifierFlags.contains(.command) { out.insert(.command) }
        return out
    }
}

final class KeyCaptureNSView: NSView {
    var onCapture: ((UInt16, MacroModifiers, String) -> Void)?
    var isCapturing = false {
        didSet {
            guard isCapturing != oldValue else { return }
            if isCapturing {
                window?.makeFirstResponder(self)
            } else if window?.firstResponder === self {
                window?.makeFirstResponder(nil)
            }
        }
    }

    override var acceptsFirstResponder: Bool { isCapturing }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else { return super.keyDown(with: event) }
        capture(event)
    }

    /// Sem isto, combinações com ⌘ nunca chegam ao `keyDown` — o sistema as
    /// trata como atalho de menu antes.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isCapturing else { return false }
        capture(event)
        return true
    }

    private func capture(_ event: NSEvent) {
        onCapture?(event.keyCode, KeyCodeNames.modifiers(for: event), KeyCodeNames.label(for: event))
        isCapturing = false
    }
}

struct KeyCaptureField: NSViewRepresentable {
    @Binding var isCapturing: Bool
    var onCapture: (UInt16, MacroModifiers, String) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = { code, modifiers, label in
            onCapture(code, modifiers, label)
            isCapturing = false
        }
        return view
    }

    func updateNSView(_ view: KeyCaptureNSView, context: Context) {
        view.isCapturing = isCapturing
    }
}
