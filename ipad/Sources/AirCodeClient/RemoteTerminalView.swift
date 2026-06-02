import Foundation
import SwiftTerm
import SwiftUI

#if os(iOS) || os(visionOS)
import UIKit

public struct RemoteTerminalView: UIViewRepresentable {
    public let output: String
    public let theme: AirCodeTheme
    public let onInput: (Data) -> Void
    public let onResize: (UInt16, UInt16) -> Void

    public init(output: String, theme: AirCodeTheme, onInput: @escaping (Data) -> Void, onResize: @escaping (UInt16, UInt16) -> Void) {
        self.output = output
        self.theme = theme
        self.onInput = onInput
        self.onResize = onResize
    }

    public func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        configure(view)
        return view
    }

    public func updateUIView(_ uiView: TerminalView, context: Context) {
        context.coordinator.parent = self
        configure(uiView)
        context.coordinator.feed(output, into: uiView)
    }

    public func makeCoordinator() -> RemoteTerminalCoordinator {
        RemoteTerminalCoordinator(parent: self)
    }

    private func configure(_ view: TerminalView) {
        let backgroundColor = UIColor(theme.terminalBackground)
        view.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.backgroundColor = backgroundColor
        view.layer.backgroundColor = backgroundColor.cgColor
        view.nativeBackgroundColor = backgroundColor
        view.nativeForegroundColor = UIColor(theme.foreground)
        view.caretColor = UIColor(hex: theme.cursorHex)
        view.optionAsMetaKey = false
        if view.inputAccessoryView != nil {
            view.inputAccessoryView = nil
            view.reloadInputViews()
        }
        view.alwaysBounceVertical = true
    }
}
#elseif os(macOS)
import AppKit

public struct RemoteTerminalView: NSViewRepresentable {
    public let output: String
    public let theme: AirCodeTheme
    public let onInput: (Data) -> Void
    public let onResize: (UInt16, UInt16) -> Void

    public init(output: String, theme: AirCodeTheme, onInput: @escaping (Data) -> Void, onResize: @escaping (UInt16, UInt16) -> Void) {
        self.output = output
        self.theme = theme
        self.onInput = onInput
        self.onResize = onResize
    }

    public func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        configure(view)
        return view
    }

    public func updateNSView(_ nsView: TerminalView, context: Context) {
        context.coordinator.parent = self
        configure(nsView)
        context.coordinator.feed(output, into: nsView)
    }

    public func makeCoordinator() -> RemoteTerminalCoordinator {
        RemoteTerminalCoordinator(parent: self)
    }

    private func configure(_ view: TerminalView) {
        let backgroundColor = NSColor(theme.terminalBackground)
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.layer?.backgroundColor = backgroundColor.cgColor
        view.nativeBackgroundColor = backgroundColor
        view.nativeForegroundColor = NSColor(theme.foreground)
        view.caretColor = NSColor(hex: theme.cursorHex)
    }
}
#endif

public final class RemoteTerminalCoordinator: NSObject, @MainActor TerminalViewDelegate {
    fileprivate var parent: RemoteTerminalView
    private var lastOutput = ""

    fileprivate init(parent: RemoteTerminalView) {
        self.parent = parent
    }

    @MainActor
    fileprivate func feed(_ output: String, into view: TerminalView) {
        if output.count < lastOutput.count || !output.hasPrefix(lastOutput) {
            view.feed(text: "\u{001B}c")
            lastOutput = ""
        }
        let delta = output.dropFirst(lastOutput.count)
        if !delta.isEmpty {
            view.feed(text: String(delta))
        }
        lastOutput = output
    }

    @MainActor
    public func send(source: TerminalView, data: ArraySlice<UInt8>) {
        parent.onInput(Data(data))
    }

    @MainActor
    public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        parent.onResize(UInt16(clamping: newCols), UInt16(clamping: newRows))
    }

    @MainActor public func setTerminalTitle(source: TerminalView, title: String) {}
    @MainActor public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    @MainActor public func scrolled(source: TerminalView, position: Double) {}
    @MainActor public func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    @MainActor public func bell(source: TerminalView) {}
    @MainActor public func clipboardCopy(source: TerminalView, content: Data) {}
    @MainActor public func clipboardRead(source: TerminalView) -> Data? { nil }
    @MainActor public func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    @MainActor public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

}

#if os(iOS) || os(visionOS)
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex & 0xFF0000) >> 16) / 255,
            green: CGFloat((hex & 0x00FF00) >> 8) / 255,
            blue: CGFloat(hex & 0x0000FF) / 255,
            alpha: 1
        )
    }
}
#elseif os(macOS)
private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex & 0xFF0000) >> 16) / 255,
            green: CGFloat((hex & 0x00FF00) >> 8) / 255,
            blue: CGFloat(hex & 0x0000FF) / 255,
            alpha: 1
        )
    }
}
#endif
