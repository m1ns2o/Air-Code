import SwiftUI

struct PromptInputView: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    let theme: AirCodeTheme
    let onHistoryPrevious: () -> Bool
    let onHistoryNext: () -> Bool
    let onSubmit: () -> Void

    init(
        text: Binding<String>,
        isFocused: Binding<Bool>,
        theme: AirCodeTheme,
        onHistoryPrevious: @escaping () -> Bool = { false },
        onHistoryNext: @escaping () -> Bool = { false },
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self._isFocused = isFocused
        self.theme = theme
        self.onHistoryPrevious = onHistoryPrevious
        self.onHistoryNext = onHistoryNext
        self.onSubmit = onSubmit
    }

    var body: some View {
        #if os(iOS)
        PromptTextView(
            text: $text,
            isFocused: $isFocused,
            theme: theme,
            onHistoryPrevious: onHistoryPrevious,
            onHistoryNext: onHistoryNext,
            onSubmit: onSubmit
        )
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
    let onHistoryPrevious: () -> Bool
    let onHistoryNext: () -> Bool
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> SubmitTextView {
        let textView = SubmitTextView()
        textView.delegate = context.coordinator
        textView.onHistoryPrevious = onHistoryPrevious
        textView.onHistoryNext = onHistoryNext
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
        textView.onHistoryPrevious = onHistoryPrevious
        textView.onHistoryNext = onHistoryNext
        textView.onSubmit = onSubmit
        textView.textColor = UIColor(hex: theme.isLight ? 0x546E7A : 0xEEFFFF)
        textView.tintColor = UIColor(hex: theme.isLight ? 0x39ADB5 : 0x80CBC4)
        if textView.text != text {
            context.coordinator.isApplyingExternalText = true
            textView.text = text
            context.coordinator.isApplyingExternalText = false
        }
        if isFocused && !textView.isFirstResponder {
            DispatchQueue.main.async { [weak textView] in
                guard let textView, !textView.isFirstResponder else { return }
                textView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PromptTextView
        var isApplyingExternalText = false

        init(parent: PromptTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            setFocused(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            setFocused(false)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingExternalText else { return }
            let value = textView.text ?? ""
            guard parent.text != value else { return }
            parent.text = value
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard replacement == "\n" else { return true }
            if let submitTextView = textView as? SubmitTextView, submitTextView.consumeShiftNewlineAllowance() {
                return true
            }
            DispatchQueue.main.async { [parent] in
                parent.onSubmit()
            }
            return false
        }

        private func setFocused(_ focused: Bool) {
            guard parent.isFocused != focused else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent.isFocused != focused else { return }
                self.parent.isFocused = focused
            }
        }
    }
}

private final class SubmitTextView: UITextView {
    var onSubmit: (() -> Void)?
    var onHistoryPrevious: (() -> Bool)?
    var onHistoryNext: (() -> Bool)?
    private var allowsNextNewline = false

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key else {
            super.pressesBegan(presses, with: event)
            return
        }

        switch key.keyCode {
        case .keyboardReturnOrEnter:
            if key.modifierFlags.contains(.shift) {
                allowsNextNewline = true
                insertText("\n")
            } else {
                let submit = onSubmit
                DispatchQueue.main.async {
                    submit?()
                }
            }
        case .keyboardUpArrow:
            if shouldNavigateHistoryUp, onHistoryPrevious?() == true {
                return
            }
            super.pressesBegan(presses, with: event)
        case .keyboardDownArrow:
            if shouldNavigateHistoryDown, onHistoryNext?() == true {
                return
            }
            super.pressesBegan(presses, with: event)
        default:
            super.pressesBegan(presses, with: event)
        }
    }

    func consumeShiftNewlineAllowance() -> Bool {
        if allowsNextNewline {
            allowsNextNewline = false
            return true
        }
        return false
    }

    private var shouldNavigateHistoryUp: Bool {
        text.isEmpty || !text.contains("\n") || selectedRange.location == 0
    }

    private var shouldNavigateHistoryDown: Bool {
        text.isEmpty || !text.contains("\n") || selectedRange.location >= (text as NSString).length
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
