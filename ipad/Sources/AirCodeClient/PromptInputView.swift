import SwiftUI

struct PromptInputView: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    let theme: AirCodeTheme
    let onSubmit: () -> Void

    var body: some View {
        #if os(iOS)
        PromptTextView(text: $text, isFocused: $isFocused, theme: theme, onSubmit: onSubmit)
        #else
        TextEditor(text: $text)
        #endif
    }
}

#if os(iOS)
import UIKit

private struct PromptTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let theme: AirCodeTheme
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> SubmitTextView {
        let textView = SubmitTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = UIColor(hex: theme.isLight ? 0x546E7A : 0xEEFFFF)
        textView.tintColor = UIColor(hex: theme.isLight ? 0x39ADB5 : 0x80CBC4)
        textView.returnKeyType = .send
        textView.textContainerInset = UIEdgeInsets(top: 7, left: 5, bottom: 7, right: 5)
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        return textView
    }

    func updateUIView(_ textView: SubmitTextView, context: Context) {
        context.coordinator.parent = self
        textView.onSubmit = onSubmit
        textView.textColor = UIColor(hex: theme.isLight ? 0x546E7A : 0xEEFFFF)
        textView.tintColor = UIColor(hex: theme.isLight ? 0x39ADB5 : 0x80CBC4)
        if textView.text != text {
            textView.text = text
        }
        if isFocused && !textView.isFirstResponder {
            textView.becomeFirstResponder()
        } else if !isFocused && textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PromptTextView

        init(parent: PromptTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard replacement == "\n" else { return true }
            if let submitTextView = textView as? SubmitTextView, submitTextView.consumeShiftNewlineAllowance() {
                return true
            }
            parent.onSubmit()
            return false
        }
    }
}

private final class SubmitTextView: UITextView {
    var onSubmit: (() -> Void)?
    private var allowsNextNewline = false

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key,
              key.keyCode == .keyboardReturnOrEnter else {
            super.pressesBegan(presses, with: event)
            return
        }

        if key.modifierFlags.contains(.shift) {
            allowsNextNewline = true
            insertText("\n")
        } else {
            onSubmit?()
        }
    }

    func consumeShiftNewlineAllowance() -> Bool {
        if allowsNextNewline {
            allowsNextNewline = false
            return true
        }
        return false
    }
}

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
#endif
