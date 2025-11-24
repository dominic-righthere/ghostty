import SwiftUI
import GhosttyKit

extension Ghostty {
    /// The UIView implementation for a terminal surface.
    class SurfaceView: UIView, ObservableObject {
        /// Unique ID per surface
        let uuid: UUID

        // The current title of the surface as defined by the pty. This can be
        // changed with escape codes. This is public because the callbacks go
        // to the app level and it is set from there.
        @Published var title: String = "👻"

        // The current pwd of the surface.
        @Published var pwd: String? = nil

        // The cell size of this surface. This is set by the core when the
        // surface is first created and any time the cell size changes (i.e.
        // when the font size changes). This is used to allow windows to be
        // resized in discrete steps of a single cell.
        @Published var cellSize: OSSize = .zero

        // The health state of the surface. This currently only reflects the
        // renderer health. In the future we may want to make this an enum.
        @Published var healthy: Bool = true

        // Any error while initializing the surface.
        @Published var error: Error? = nil

        // The hovered URL
        @Published var hoverUrl: String? = nil
        
        // The progress report (if any)
        @Published var progressReport: Action.ProgressReport? = nil

        // The time this surface last became focused. This is a ContinuousClock.Instant
        // on supported platforms.
        @Published var focusInstant: ContinuousClock.Instant? = nil

        /// True when the bell is active. This is set inactive on focus or event.
        @Published var bell: Bool = false

        // Returns sizing information for the surface. This is the raw C
        // structure because I'm lazy.
        var surfaceSize: ghostty_surface_size_s? {
            guard let surface = self.surface else { return nil }
            return ghostty_surface_size(surface)
        }

        private(set) var surface: ghostty_surface_t?

        init(_ app: ghostty_app_t, baseConfig: SurfaceConfiguration? = nil, uuid: UUID? = nil) {
            self.uuid = uuid ?? .init()

            // Initialize with some default frame size. The important thing is that this
            // is non-zero so that our layer bounds are non-zero so that our renderer
            // can do SOMETHING.
            super.init(frame: CGRect(x: 0, y: 0, width: 800, height: 600))

            // Setup our surface. This will also initialize all the terminal IO.
            let surface_cfg = baseConfig ?? SurfaceConfiguration()
            let surface = surface_cfg.withCValue(view: self) { surface_cfg_c in
                ghostty_surface_new(app, &surface_cfg_c)
            }
            guard let surface = surface else {
                // TODO
                return
            }
            self.surface = surface;
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported for this view")
        }

        deinit {
            guard let surface = self.surface else { return }
            ghostty_surface_free(surface)
        }

        func focusDidChange(_ focused: Bool) {
            guard let surface = self.surface else { return }
            ghostty_surface_set_focus(surface, focused)

            // On macOS 13+ we can store our continuous clock...
            if (focused) {
                focusInstant = ContinuousClock.now
            }
        }

        func sizeDidChange(_ size: CGSize) {
            guard let surface = self.surface else { return }

            // Ghostty wants to know the actual framebuffer size... It is very important
            // here that we use "size" and NOT the view frame. If we're in the middle of
            // an animation (i.e. a fullscreen animation), the frame will not yet be updated.
            // The size represents our final size we're going for.
            let scale = self.contentScaleFactor
            ghostty_surface_set_content_scale(surface, scale, scale)
            ghostty_surface_set_size(
                surface,
                UInt32(size.width * scale),
                UInt32(size.height * scale)
            )
        }

        // MARK: UIView

        override class var layerClass: AnyClass {
            get {
                return CAMetalLayer.self
            }
        }

        override func didMoveToWindow() {
            sizeDidChange(frame.size)

            // Become first responder to receive keyboard input
            if window != nil {
                setupGestures()
                _ = becomeFirstResponder()
            }
        }

        // MARK: - Gesture Setup

        private func setupGestures() {
            // Tap - Show keyboard or send click to terminal
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.numberOfTapsRequired = 1
            addGestureRecognizer(tap)

            // Double tap - Select word (future feature)
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            addGestureRecognizer(doubleTap)

            // Make single tap wait for double tap to fail
            tap.require(toFail: doubleTap)

            // Long press - Text selection mode
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = 0.5
            addGestureRecognizer(longPress)

            // Two-finger pan - Scroll history
            let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
            twoFingerPan.minimumNumberOfTouches = 2
            twoFingerPan.maximumNumberOfTouches = 2
            addGestureRecognizer(twoFingerPan)

            // Pinch - Zoom text size
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            addGestureRecognizer(pinch)
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            // Show keyboard if not already visible
            if !isFirstResponder {
                becomeFirstResponder()
            }

            // If mouse mode is enabled in terminal, send click event
            guard let surface = self.surface else { return }
            if ghostty_surface_mouse_captured(surface) {
                let location = gesture.location(in: self)
                sendMouseClick(at: location)
            }
        }

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            // TODO: Implement word selection
            // For now, just ensure keyboard is shown
            if !isFirstResponder {
                becomeFirstResponder()
            }
        }

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }

            // TODO: Enter text selection mode
            // For now, show a menu for copy/paste
            becomeFirstResponder()

            let menu = UIMenuController.shared
            if !menu.isMenuVisible {
                menu.showMenu(from: self, rect: CGRect(origin: gesture.location(in: self), size: .zero))
            }
        }

        @objc private func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
            guard let surface = self.surface else { return }

            let translation = gesture.translation(in: self)
            let velocityY = gesture.velocity(in: self).y

            // Convert pixels to scroll amount (adjust sensitivity)
            let scrollAmount = Float(translation.y) / 10.0

            // Send scroll event to terminal
            ghostty_surface_mouse_scroll(surface, 0, scrollAmount, 0)

            // Reset translation for continuous scrolling
            gesture.setTranslation(.zero, in: self)

            // Apply momentum scrolling when gesture ends
            if gesture.state == .ended && abs(velocityY) > 100 {
                applyMomentumScroll(velocity: velocityY)
            }
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let surface = self.surface else { return }

            if gesture.state == .changed {
                let scale = gesture.scale

                // Adjust font size based on pinch
                if scale > 1.1 {
                    // Zoom in
                    let action = "increase_font_size:1"
                    ghostty_surface_binding_action(surface, action, UInt(action.count))
                    gesture.scale = 1.0
                } else if scale < 0.9 {
                    // Zoom out
                    let action = "decrease_font_size:1"
                    ghostty_surface_binding_action(surface, action, UInt(action.count))
                    gesture.scale = 1.0
                }
            }
        }

        private func sendMouseClick(at location: CGPoint) {
            guard let surface = self.surface else { return }

            // Convert view coordinates to terminal cell coordinates
            let scale = contentScaleFactor
            let x = Double(location.x * scale)
            let y = Double(location.y * scale)

            // Send mouse button press
            ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_BUTTON_LEFT, 0)

            // Send mouse position
            ghostty_surface_mouse_pos(surface, x, y, 0)

            // Send mouse button release
            ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_BUTTON_LEFT, 0)
        }

        private func applyMomentumScroll(velocity: CGFloat) {
            guard let surface = self.surface else { return }

            // Simple momentum animation
            var currentVelocity = velocity
            let decelerationRate: CGFloat = 0.9

            func scroll() {
                currentVelocity *= decelerationRate

                if abs(currentVelocity) > 10 {
                    let scrollAmount = Float(currentVelocity) / 100.0
                    ghostty_surface_mouse_scroll(surface, 0, scrollAmount, 0)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
                        scroll()
                    }
                }
            }

            scroll()
        }

        // MARK: - First Responder

        override var canBecomeFirstResponder: Bool {
            return true
        }

        override var canResignFirstResponder: Bool {
            return true
        }

        // MARK: - External Keyboard Support

        override var keyCommands: [UIKeyCommand]? {
            // Return empty array to capture all key events
            // This allows us to handle keys in pressesBegan/pressesEnded
            return []
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in presses {
                handleKeyPress(press, isDown: true)
            }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in presses {
                handleKeyPress(press, isDown: false)
            }
        }

        private func handleKeyPress(_ press: UIPress, isDown: Bool) {
            guard let key = press.key else {
                super.pressesBegan([press], with: nil)
                return
            }

            guard let surface = self.surface else { return }

            // Build Ghostty key event
            var keyText = ""
            var ghosttyKey: UInt32 = 0

            // Map UIKey to Ghostty key codes
            switch key.keyCode {
            case .keyboardReturnOrEnter:
                keyText = "\r"
            case .keyboardTab:
                keyText = "\t"
            case .keyboardDeleteOrBackspace:
                keyText = "\u{7F}"
            case .keyboardEscape:
                keyText = "\u{1B}"
            case .keyboardUpArrow:
                keyText = "\u{1B}[A"
            case .keyboardDownArrow:
                keyText = "\u{1B}[B"
            case .keyboardLeftArrow:
                keyText = "\u{1B}[D"
            case .keyboardRightArrow:
                keyText = "\u{1B}[C"
            case .keyboardHome:
                keyText = "\u{1B}[H"
            case .keyboardEnd:
                keyText = "\u{1B}[F"
            case .keyboardPageUp:
                keyText = "\u{1B}[5~"
            case .keyboardPageDown:
                keyText = "\u{1B}[6~"
            default:
                if let characters = key.characters, !characters.isEmpty {
                    keyText = characters
                }
            }

            // Handle modifiers for special keys
            let modifiers = key.modifierFlags
            if modifiers.contains(.control) && !keyText.isEmpty {
                // Apply control modifier
                if let char = keyText.first, char.isASCII {
                    let ascii = char.asciiValue ?? 0
                    if ascii >= 64 && ascii <= 95 {
                        // Convert to control character (A-Z -> 1-26)
                        keyText = String(UnicodeScalar(ascii & 0x1F))
                    }
                }
            }

            // Only send on key press, not release (for now)
            if isDown && !keyText.isEmpty {
                keyText.withCString { ptr in
                    ghostty_surface_text(surface, ptr, UInt(keyText.count))
                }
            }
        }

        // MARK: - Copy/Paste Support

        override func copy(_ sender: Any?) {
            // TODO: Get selected text from terminal
            guard let surface = self.surface else { return }

            // For now, just acknowledge the command
            // Full implementation requires adding selection C API
            UIPasteboard.general.string = ""
        }

        override func paste(_ sender: Any?) {
            guard let text = UIPasteboard.general.string else { return }
            insertText(text)
        }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            if action == #selector(copy(_:)) {
                // Enable copy when there's a selection
                // TODO: Check if terminal has selection
                return false // Disabled until selection is implemented
            }

            if action == #selector(paste(_:)) {
                return UIPasteboard.general.hasStrings
            }

            return super.canPerformAction(action, withSender: sender)
        }
    }
}

// MARK: - UIKeyInput Protocol (Virtual Keyboard)

extension Ghostty.SurfaceView: UIKeyInput {
    var hasText: Bool {
        // Always return true so the keyboard can always delete
        return true
    }

    func insertText(_ text: String) {
        guard let surface = self.surface else { return }

        // Send the text to the terminal
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.count))
        }
    }

    func deleteBackward() {
        // Send backspace (DEL character)
        insertText("\u{7F}")
    }
}

// MARK: - UITextInputTraits (Keyboard Configuration)

extension Ghostty.SurfaceView: UITextInputTraits {
    var keyboardType: UIKeyboardType {
        return .asciiCapable
    }

    var keyboardAppearance: UIKeyboardAppearance {
        // Match the terminal color scheme
        // TODO: Make this dynamic based on theme
        return .dark
    }

    var autocorrectionType: UITextAutocorrectionType {
        return .no
    }

    var autocapitalizationType: UITextAutocapitalizationType {
        return .none
    }

    var spellCheckingType: UITextSpellCheckingType {
        return .no
    }

    var smartQuotesType: UITextSmartQuotesType {
        return .no
    }

    var smartDashesType: UITextSmartDashesType {
        return .no
    }

    var smartInsertDeleteType: UITextSmartInsertDeleteType {
        return .no
    }

    var returnKeyType: UIReturnKeyType {
        return .default
    }

    var enablesReturnKeyAutomatically: Bool {
        return false
    }
}
