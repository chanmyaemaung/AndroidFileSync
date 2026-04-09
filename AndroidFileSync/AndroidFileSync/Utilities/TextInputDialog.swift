//
//  TextInputDialog.swift
//  AndroidFileSync
//
//  Clean native macOS text-input dialog — centered on the app window,
//  no icon, no empty space.
//

import AppKit

enum TextInputDialog {

    /// Presents a clean modal text-input dialog centered on the app window.
    /// Returns the trimmed text or nil if cancelled.
    @MainActor
    static func show(
        title: String,
        message: String = "",
        placeholder: String = "",
        initialValue: String = "",
        confirmLabel: String = "OK"
    ) -> String? {

        // ── Panel ─────────────────────────────────────────────────────────
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 140),
            styleMask:   [.titled, .closable],
            backing:     .buffered,
            defer:       false
        )
        panel.title                      = title
        panel.isMovableByWindowBackground = true
        panel.level                      = .modalPanel

        let content = panel.contentView!

        // ── Message label ─────────────────────────────────────────────────
        let msgLabel = NSTextField(labelWithString: message)
        msgLabel.translatesAutoresizingMaskIntoConstraints = false
        msgLabel.font            = .systemFont(ofSize: 12)
        msgLabel.textColor       = .secondaryLabelColor
        msgLabel.lineBreakMode   = .byWordWrapping
        msgLabel.preferredMaxLayoutWidth = 320
        msgLabel.isHidden        = message.isEmpty
        content.addSubview(msgLabel)

        // ── Text field ────────────────────────────────────────────────────
        let tf = NSTextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.bezelStyle        = .roundedBezel
        tf.font              = .systemFont(ofSize: 13)
        tf.stringValue       = initialValue
        tf.placeholderString = placeholder
        content.addSubview(tf)

        // ── Buttons ───────────────────────────────────────────────────────
        let cancelBtn = NSButton(title: "Cancel", target: nil, action: nil)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.bezelStyle    = .rounded
        cancelBtn.keyEquivalent = "\u{1B}"
        content.addSubview(cancelBtn)

        let confirmBtn = NSButton(title: confirmLabel, target: nil, action: nil)
        confirmBtn.translatesAutoresizingMaskIntoConstraints = false
        confirmBtn.bezelStyle    = .rounded
        confirmBtn.keyEquivalent = "\r"
        content.addSubview(confirmBtn)

        // ── Constraints ───────────────────────────────────────────────────
        let h: CGFloat = 20   // horizontal padding
        let v: CGFloat = 16   // vertical padding

        if message.isEmpty {
            // No message — larger top gap for the text field
            NSLayoutConstraint.activate([
                tf.topAnchor.constraint(equalTo: content.topAnchor, constant: v + 4),
            ])
        } else {
            NSLayoutConstraint.activate([
                msgLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: v),
                msgLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: h),
                msgLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -h),

                tf.topAnchor.constraint(equalTo: msgLabel.bottomAnchor, constant: 10),
            ])
        }

        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: h),
            tf.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -h),
            tf.heightAnchor.constraint(equalToConstant: 26),

            confirmBtn.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -h),
            confirmBtn.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -v),
            confirmBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 82),

            cancelBtn.trailingAnchor.constraint(equalTo: confirmBtn.leadingAnchor, constant: -8),
            cancelBtn.bottomAnchor.constraint(equalTo: confirmBtn.bottomAnchor),
            cancelBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 82),
        ])

        // ── Center on app window ──────────────────────────────────────────
        if let appWindow = NSApp.keyWindow ?? NSApp.mainWindow {
            let wf = appWindow.frame
            let pf = panel.frame
            let x  = wf.midX - pf.width / 2
            let y  = wf.midY - pf.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        // ── Result ────────────────────────────────────────────────────────
        var confirmed = false

        let cancelAction = Trampoline { NSApp.stopModal() }
        cancelBtn.target = cancelAction
        cancelBtn.action = #selector(Trampoline.fire)

        let confirmAction = Trampoline {
            confirmed = true
            NSApp.stopModal(withCode: .OK)
        }
        confirmBtn.target = confirmAction
        confirmBtn.action = #selector(Trampoline.fire)

        // Focus & select all text so user can immediately retype
        panel.initialFirstResponder = tf
        panel.makeKeyAndOrderFront(nil)
        tf.currentEditor()?.selectAll(nil)

        NSApp.runModal(for: panel)
        panel.orderOut(nil)

        guard confirmed else { return nil }
        let result = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

// MARK: - Trampoline helper

private final class Trampoline: NSObject {
    private let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func fire() { block() }
}
