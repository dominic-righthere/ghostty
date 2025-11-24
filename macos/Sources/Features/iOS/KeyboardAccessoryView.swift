import UIKit

/// Custom keyboard accessory view that provides essential terminal keys
/// that are missing from the standard iOS keyboard.
///
/// This toolbar sits above the keyboard and provides quick access to:
/// - Control key modifier
/// - Escape key
/// - Tab key
/// - Arrow keys
/// - Function keys (F1-F12)
class TerminalKeyboardAccessoryView: UIView {
    weak var delegate: KeyboardAccessoryDelegate?

    private var controlButton: UIButton!
    private var altButton: UIButton!
    private var isControlActive = false
    private var isAltActive = false

    private let keyHeight: CGFloat = 38
    private let keySpacing: CGFloat = 4
    private let sideMargin: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = UIColor.systemGray6
        autoresizingMask = [.flexibleWidth]

        // Create a scroll view to hold all keys
        let scrollView = UIScrollView(frame: bounds)
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        addSubview(scrollView)

        // Create a stack view for the keys
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = keySpacing
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 3),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -3),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: sideMargin),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -sideMargin),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor, constant: -6)
        ])

        // Essential keys configuration
        let keys: [(String, TerminalKey, KeyStyle)] = [
            ("Ctrl", .control, .modifier),
            ("Alt", .alt, .modifier),
            ("Esc", .escape, .standard),
            ("Tab", .tab, .standard),
            ("↑", .arrowUp, .arrow),
            ("↓", .arrowDown, .arrow),
            ("←", .arrowLeft, .arrow),
            ("→", .arrowRight, .arrow),
            ("-", .minus, .standard),
            ("=", .equal, .standard),
            ("/", .slash, .standard),
            ("~", .tilde, .standard),
            ("|", .pipe, .standard),
            ("$", .dollar, .standard),
        ]

        // Add function keys row button
        let fkeysButton = createKeyButton(title: "F-keys", style: .standard)
        fkeysButton.addTarget(self, action: #selector(showFunctionKeys), for: .touchUpInside)
        stackView.addArrangedSubview(fkeysButton)

        // Add all primary keys
        for (title, key, style) in keys {
            let button: UIButton
            if style == .modifier {
                button = createModifierButton(title: title, key: key)
            } else {
                button = createKeyButton(title: title, style: style)
                button.tag = key.rawValue
                button.addTarget(self, action: #selector(keyTapped), for: .touchUpInside)
            }

            stackView.addArrangedSubview(button)

            // Store modifier buttons for state updates
            if key == .control {
                controlButton = button
            } else if key == .alt {
                altButton = button
            }
        }

        // Add dismiss keyboard button
        let dismissButton = createKeyButton(title: "⌨︎", style: .special)
        dismissButton.addTarget(self, action: #selector(dismissKeyboard), for: .touchUpInside)
        stackView.addArrangedSubview(dismissButton)
    }

    private func createKeyButton(title: String, style: KeyStyle) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)

        button.translatesAutoresizingMaskIntoConstraints = false
        let width: CGFloat = style == .arrow ? 44 : 56
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: width),
            button.heightAnchor.constraint(equalToConstant: keyHeight)
        ])

        switch style {
        case .standard:
            button.backgroundColor = .white
            button.setTitleColor(.black, for: .normal)
        case .modifier:
            button.backgroundColor = .systemBlue.withAlphaComponent(0.2)
            button.setTitleColor(.systemBlue, for: .normal)
        case .arrow:
            button.backgroundColor = .white
            button.setTitleColor(.black, for: .normal)
        case .special:
            button.backgroundColor = .systemGray4
            button.setTitleColor(.label, for: .normal)
        }

        button.layer.cornerRadius = 6
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowOpacity = 0.1
        button.layer.shadowRadius = 0

        return button
    }

    private func createModifierButton(title: String, key: TerminalKey) -> UIButton {
        let button = createKeyButton(title: title, style: .modifier)
        button.tag = key.rawValue
        button.addTarget(self, action: #selector(modifierTapped), for: .touchUpInside)
        return button
    }

    @objc private func keyTapped(_ sender: UIButton) {
        guard let key = TerminalKey(rawValue: sender.tag) else { return }

        var modifiers: Set<TerminalModifier> = []
        if isControlActive {
            modifiers.insert(.control)
            // Auto-deactivate control after use (typical terminal behavior)
            setModifierActive(.control, false)
        }
        if isAltActive {
            modifiers.insert(.alt)
            // Keep alt active for multiple keystrokes (can be manually disabled)
        }

        delegate?.keyboardAccessory(self, didTapKey: key, modifiers: modifiers)
    }

    @objc private func modifierTapped(_ sender: UIButton) {
        guard let modifier = TerminalKey(rawValue: sender.tag) else { return }

        switch modifier {
        case .control:
            setModifierActive(.control, !isControlActive)
        case .alt:
            setModifierActive(.alt, !isAltActive)
        default:
            break
        }
    }

    private func setModifierActive(_ modifier: TerminalModifier, _ active: Bool) {
        switch modifier {
        case .control:
            isControlActive = active
            if active {
                controlButton.backgroundColor = .systemBlue
                controlButton.setTitleColor(.white, for: .normal)
            } else {
                controlButton.backgroundColor = .systemBlue.withAlphaComponent(0.2)
                controlButton.setTitleColor(.systemBlue, for: .normal)
            }
        case .alt:
            isAltActive = active
            if active {
                altButton.backgroundColor = .systemOrange
                altButton.setTitleColor(.white, for: .normal)
            } else {
                altButton.backgroundColor = .systemBlue.withAlphaComponent(0.2)
                altButton.setTitleColor(.systemBlue, for: .normal)
            }
        default:
            break
        }
    }

    @objc private func showFunctionKeys() {
        // Show an action sheet with function keys
        let alert = UIAlertController(title: "Function Keys", message: nil, preferredStyle: .actionSheet)

        for i in 1...12 {
            alert.addAction(UIAlertAction(title: "F\(i)", style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.delegate?.keyboardAccessory(self, didTapFunctionKey: i)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        // Find the view controller to present from
        var responder: UIResponder? = self
        while responder != nil {
            responder = responder?.next
            if let viewController = responder as? UIViewController {
                alert.popoverPresentationController?.sourceView = self
                alert.popoverPresentationController?.sourceRect = bounds
                viewController.present(alert, animated: true)
                break
            }
        }
    }

    @objc private func dismissKeyboard() {
        delegate?.keyboardAccessoryDidRequestDismiss(self)
    }
}

// MARK: - Supporting Types

enum TerminalKey: Int {
    case control = 1
    case alt = 2
    case escape = 3
    case tab = 4
    case arrowUp = 5
    case arrowDown = 6
    case arrowLeft = 7
    case arrowRight = 8
    case minus = 9
    case equal = 10
    case slash = 11
    case tilde = 12
    case pipe = 13
    case dollar = 14

    var stringValue: String {
        switch self {
        case .control, .alt:
            return "" // Modifiers don't send text
        case .escape:
            return "\u{1B}" // ESC
        case .tab:
            return "\t"
        case .arrowUp:
            return "\u{1B}[A"
        case .arrowDown:
            return "\u{1B}[B"
        case .arrowRight:
            return "\u{1B}[C"
        case .arrowLeft:
            return "\u{1B}[D"
        case .minus:
            return "-"
        case .equal:
            return "="
        case .slash:
            return "/"
        case .tilde:
            return "~"
        case .pipe:
            return "|"
        case .dollar:
            return "$"
        }
    }
}

enum TerminalModifier {
    case control
    case alt
    case shift
}

enum KeyStyle {
    case standard
    case modifier
    case arrow
    case special
}

protocol KeyboardAccessoryDelegate: AnyObject {
    func keyboardAccessory(_ accessory: TerminalKeyboardAccessoryView, didTapKey key: TerminalKey, modifiers: Set<TerminalModifier>)
    func keyboardAccessory(_ accessory: TerminalKeyboardAccessoryView, didTapFunctionKey number: Int)
    func keyboardAccessoryDidRequestDismiss(_ accessory: TerminalKeyboardAccessoryView)
}

// MARK: - Extension for SurfaceView Integration

extension Ghostty.SurfaceView: KeyboardAccessoryDelegate {
    override var inputAccessoryView: UIView? {
        let accessory = TerminalKeyboardAccessoryView()
        accessory.delegate = self
        return accessory
    }

    func keyboardAccessory(_ accessory: TerminalKeyboardAccessoryView, didTapKey key: TerminalKey, modifiers: Set<TerminalModifier>) {
        guard let surface = self.surface else { return }

        var text = key.stringValue

        // Apply control modifier
        if modifiers.contains(.control) && !text.isEmpty {
            // For control characters, we need to send the appropriate control code
            if key == .tab {
                text = "\u{09}" // Already tab
            } else {
                // For regular characters with Ctrl, mask with 0x1F
                // This is handled per-character, but for special keys we have specific codes
                switch key {
                case .arrowUp:
                    text = "\u{1B}[1;5A" // Ctrl+Up
                case .arrowDown:
                    text = "\u{1B}[1;5B" // Ctrl+Down
                case .arrowRight:
                    text = "\u{1B}[1;5C" // Ctrl+Right
                case .arrowLeft:
                    text = "\u{1B}[1;5D" // Ctrl+Left
                default:
                    break
                }
            }
        }

        // Send to terminal
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.count))
        }
    }

    func keyboardAccessory(_ accessory: TerminalKeyboardAccessoryView, didTapFunctionKey number: Int) {
        guard let surface = self.surface else { return }

        // Function key escape sequences
        let sequences: [String] = [
            "\u{1B}OP",    // F1
            "\u{1B}OQ",    // F2
            "\u{1B}OR",    // F3
            "\u{1B}OS",    // F4
            "\u{1B}[15~",  // F5
            "\u{1B}[17~",  // F6
            "\u{1B}[18~",  // F7
            "\u{1B}[19~",  // F8
            "\u{1B}[20~",  // F9
            "\u{1B}[21~",  // F10
            "\u{1B}[23~",  // F11
            "\u{1B}[24~",  // F12
        ]

        if number >= 1 && number <= 12 {
            let seq = sequences[number - 1]
            seq.withCString { ptr in
                ghostty_surface_text(surface, ptr, UInt(seq.count))
            }
        }
    }

    func keyboardAccessoryDidRequestDismiss(_ accessory: TerminalKeyboardAccessoryView) {
        resignFirstResponder()
    }
}
