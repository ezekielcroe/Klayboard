// KeyCustomizationViewController.swift
// Visual tap-to-select keyboard customizer.
// Renders a miniature keyboard; user taps a key to select it, then edits
// its primary tap character and long-press character via a detail panel below.

import UIKit

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Delegate Protocol
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

protocol KeyCustomizationDelegate: AnyObject {
    func keyCustomization(didUpdate overrides: [UserOverride])
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - View Controller
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final class KeyCustomizationViewController: UIViewController {

    // ── External ─────────────────────────────
    weak var delegate: KeyCustomizationDelegate?
    var config: UserConfiguration = .default
    var layoutID: LayoutID = .standard

    // ── Internal ─────────────────────────────
    private var layout: KeyboardLayout!
    private var allKeyDefs: [(rowIndex: Int, keyIndex: Int, def: KeyDefinition)] = []
    private var miniKeyViews: [MiniKeyView] = []
    private var selectedKeyID: String?

    // ── UI ────────────────────────────────────
    private let scrollView = UIScrollView()
    private let miniKeyboardContainer = UIView()
    private let detailPanel = UIView()
    private let selectedKeyLabel = UILabel()
    private let primaryField = UITextField()
    private let longPressField = UITextField()
    private let applyButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let infoLabel = UILabel()

    // ── Sizing ───────────────────────────────
    private let miniKeyHeight: CGFloat = 36
    private let miniKeySpacing: CGFloat = 3
    private let miniEdgeInset: CGFloat = 4
    private let miniRowSpacing: CGFloat = 4

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Lifecycle
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Customize Keys"
        view.backgroundColor = .systemGroupedBackground

        layout = BaseLayouts.layout(for: layoutID, rowMode: config.rowMode)
        flattenKeys()
        buildUI()
        buildMiniKeyboard()
        updateDetailPanel()

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Reset All", style: .plain, target: self, action: #selector(resetAllOverrides)
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutMiniKeyboard()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Data
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func flattenKeys() {
        allKeyDefs.removeAll()
        for (ri, row) in layout.rows.enumerated() {
            for (ki, key) in row.keys.enumerated() {
                allKeyDefs.append((ri, ki, key))
            }
        }
    }

    /// Returns the effective KeyDefinition after applying any existing override.
    private func effectiveDefinition(for keyID: String) -> KeyDefinition? {
        guard let base = allKeyDefs.first(where: { $0.def.id == keyID })?.def else { return nil }
        if let ov = config.overrides.first(where: {
            $0.targetKeyID == keyID &&
            ($0.appliesToLayouts.isEmpty || $0.appliesToLayouts.contains(layoutID))
        }) {
            return KeyDefinition(
                id: base.id,
                label: ov.newLabel ?? base.label,
                action: ov.newAction,
                altAction: ov.newAltAction ?? base.altAction,
                widthMultiplier: base.widthMultiplier,
                style: base.style
            )
        }
        return base
    }

    /// Extracts the character string from a KeyAction, if it's a .character action.
    private func characterFrom(_ action: KeyAction?) -> String? {
        guard let action = action else { return nil }
        if case .character(let c) = action { return c }
        return nil
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - UI Construction
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func buildUI() {
        // Scroll view for the whole page
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Mini keyboard container
        miniKeyboardContainer.translatesAutoresizingMaskIntoConstraints = false
        miniKeyboardContainer.backgroundColor = UIColor.secondarySystemGroupedBackground
        miniKeyboardContainer.layer.cornerRadius = 12
        scrollView.addSubview(miniKeyboardContainer)

        // Info label above mini keyboard
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.text = "Tap a key to customize it"
        infoLabel.font = .systemFont(ofSize: 14, weight: .medium)
        infoLabel.textColor = .secondaryLabel
        infoLabel.textAlignment = .center
        scrollView.addSubview(infoLabel)

        // Detail panel
        detailPanel.translatesAutoresizingMaskIntoConstraints = false
        detailPanel.backgroundColor = UIColor.secondarySystemGroupedBackground
        detailPanel.layer.cornerRadius = 12
        detailPanel.isHidden = true
        scrollView.addSubview(detailPanel)

        buildDetailPanelContents()

        let totalMiniHeight = CGFloat(layout.rows.count) * miniKeyHeight
            + CGFloat(max(layout.rows.count - 1, 0)) * miniRowSpacing
            + 16 // vertical padding

        NSLayoutConstraint.activate([
            infoLabel.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            miniKeyboardContainer.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 12),
            miniKeyboardContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            miniKeyboardContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            miniKeyboardContainer.heightAnchor.constraint(equalToConstant: totalMiniHeight),

            detailPanel.topAnchor.constraint(equalTo: miniKeyboardContainer.bottomAnchor, constant: 20),
            detailPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            detailPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            detailPanel.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.bottomAnchor, constant: -20),
        ])
    }

    private func buildDetailPanelContents() {
        // Selected key display
        selectedKeyLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        selectedKeyLabel.textAlignment = .center
        selectedKeyLabel.translatesAutoresizingMaskIntoConstraints = false
        detailPanel.addSubview(selectedKeyLabel)

        // Primary character field
        let primaryLabel = makeFieldLabel("Primary tap:")
        detailPanel.addSubview(primaryLabel)

        primaryField.borderStyle = .roundedRect
        primaryField.placeholder = "Character"
        primaryField.textAlignment = .center
        primaryField.font = .monospacedSystemFont(ofSize: 20, weight: .regular)
        primaryField.autocapitalizationType = .none
        primaryField.autocorrectionType = .no
        primaryField.translatesAutoresizingMaskIntoConstraints = false
        detailPanel.addSubview(primaryField)

        // Long-press character field
        let longPressLabel = makeFieldLabel("Long-press:")
        detailPanel.addSubview(longPressLabel)

        longPressField.borderStyle = .roundedRect
        longPressField.placeholder = "Character (optional)"
        longPressField.textAlignment = .center
        longPressField.font = .monospacedSystemFont(ofSize: 20, weight: .regular)
        longPressField.autocapitalizationType = .none
        longPressField.autocorrectionType = .no
        longPressField.translatesAutoresizingMaskIntoConstraints = false
        detailPanel.addSubview(longPressField)

        // Buttons
        applyButton.setTitle("Apply", for: .normal)
        applyButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        applyButton.backgroundColor = .systemBlue
        applyButton.setTitleColor(.white, for: .normal)
        applyButton.layer.cornerRadius = 8
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.addTarget(self, action: #selector(applyOverride), for: .touchUpInside)
        detailPanel.addSubview(applyButton)

        clearButton.setTitle("Reset to Default", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        clearButton.setTitleColor(.systemRed, for: .normal)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.addTarget(self, action: #selector(clearOverride), for: .touchUpInside)
        detailPanel.addSubview(clearButton)

        NSLayoutConstraint.activate([
            selectedKeyLabel.topAnchor.constraint(equalTo: detailPanel.topAnchor, constant: 16),
            selectedKeyLabel.leadingAnchor.constraint(equalTo: detailPanel.leadingAnchor, constant: 16),
            selectedKeyLabel.trailingAnchor.constraint(equalTo: detailPanel.trailingAnchor, constant: -16),

            primaryLabel.topAnchor.constraint(equalTo: selectedKeyLabel.bottomAnchor, constant: 16),
            primaryLabel.leadingAnchor.constraint(equalTo: detailPanel.leadingAnchor, constant: 16),

            primaryField.topAnchor.constraint(equalTo: primaryLabel.bottomAnchor, constant: 6),
            primaryField.leadingAnchor.constraint(equalTo: detailPanel.leadingAnchor, constant: 16),
            primaryField.trailingAnchor.constraint(equalTo: detailPanel.trailingAnchor, constant: -16),
            primaryField.heightAnchor.constraint(equalToConstant: 44),

            longPressLabel.topAnchor.constraint(equalTo: primaryField.bottomAnchor, constant: 14),
            longPressLabel.leadingAnchor.constraint(equalTo: detailPanel.leadingAnchor, constant: 16),

            longPressField.topAnchor.constraint(equalTo: longPressLabel.bottomAnchor, constant: 6),
            longPressField.leadingAnchor.constraint(equalTo: detailPanel.leadingAnchor, constant: 16),
            longPressField.trailingAnchor.constraint(equalTo: detailPanel.trailingAnchor, constant: -16),
            longPressField.heightAnchor.constraint(equalToConstant: 44),

            applyButton.topAnchor.constraint(equalTo: longPressField.bottomAnchor, constant: 18),
            applyButton.leadingAnchor.constraint(equalTo: detailPanel.leadingAnchor, constant: 16),
            applyButton.trailingAnchor.constraint(equalTo: detailPanel.trailingAnchor, constant: -16),
            applyButton.heightAnchor.constraint(equalToConstant: 44),

            clearButton.topAnchor.constraint(equalTo: applyButton.bottomAnchor, constant: 8),
            clearButton.centerXAnchor.constraint(equalTo: detailPanel.centerXAnchor),
            clearButton.bottomAnchor.constraint(equalTo: detailPanel.bottomAnchor, constant: -16),
        ])
    }

    private func makeFieldLabel(_ text: String) -> UILabel {
        let lbl = UILabel()
        lbl.text = text
        lbl.font = .systemFont(ofSize: 13, weight: .medium)
        lbl.textColor = .secondaryLabel
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Mini Keyboard Rendering
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func buildMiniKeyboard() {
        miniKeyViews.forEach { $0.removeFromSuperview() }
        miniKeyViews.removeAll()

        for entry in allKeyDefs {
            let effective = effectiveDefinition(for: entry.def.id) ?? entry.def
            let mkv = MiniKeyView(definition: effective, hasOverride: hasOverride(for: entry.def.id))
            mkv.addTarget(self, action: #selector(miniKeyTapped(_:)), for: .touchUpInside)
            miniKeyboardContainer.addSubview(mkv)
            miniKeyViews.append(mkv)
        }
    }

    private func layoutMiniKeyboard() {
        let containerWidth = miniKeyboardContainer.bounds.width
        guard containerWidth > 0 else { return }

        var yOffset: CGFloat = 8
        var keyIndex = 0

        for row in layout.rows {
            let totalUnits = row.keys.reduce(CGFloat(0)) { $0 + $1.widthMultiplier }
            let totalSpacing = miniKeySpacing * CGFloat(max(row.keys.count - 1, 0)) + miniEdgeInset * 2
            let unitWidth = (containerWidth - totalSpacing) / totalUnits
            var xOffset = miniEdgeInset

            for keyDef in row.keys {
                guard keyIndex < miniKeyViews.count else { break }
                let mkv = miniKeyViews[keyIndex]
                let keyW = unitWidth * keyDef.widthMultiplier
                mkv.frame = CGRect(x: xOffset, y: yOffset, width: keyW, height: miniKeyHeight)
                mkv.updateSelection(isSelected: keyDef.id == selectedKeyID)
                xOffset += keyW + miniKeySpacing
                keyIndex += 1
            }
            yOffset += miniKeyHeight + miniRowSpacing
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Key Selection
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    @objc private func miniKeyTapped(_ sender: MiniKeyView) {
        let keyID = sender.definition.id

        // Only allow customizing character keys (not shift, backspace, globe, etc.)
        guard isCustomizable(sender.definition) else {
            showNotCustomizableHint(for: sender.definition)
            return
        }

        selectedKeyID = keyID

        // Update selection highlight
        for mkv in miniKeyViews {
            mkv.updateSelection(isSelected: mkv.definition.id == keyID)
        }

        updateDetailPanel()
    }

    private func isCustomizable(_ def: KeyDefinition) -> Bool {
        // Allow customization of character keys and keys that already have character actions
        switch def.action {
        case .character: return true
        default: break
        }
        // Also allow if the key had a character action before override
        if let base = allKeyDefs.first(where: { $0.def.id == def.id })?.def {
            if case .character = base.action { return true }
        }
        return false
    }

    private func showNotCustomizableHint(for def: KeyDefinition) {
        let label = def.label.hasPrefix("sf:") ? "This key" : "'\(def.label)'"
        let hint = "\(label) is a system key and can't be remapped to a character."

        let alert = UIAlertController(title: nil, message: hint, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Detail Panel
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func updateDetailPanel() {
        guard let keyID = selectedKeyID,
              let effective = effectiveDefinition(for: keyID) else {
            detailPanel.isHidden = true
            infoLabel.text = "Tap a key to customize it"
            return
        }

        detailPanel.isHidden = false
        infoLabel.text = "Editing key:"

        let hasOv = hasOverride(for: keyID)
        let displayLabel = effective.label.hasPrefix("sf:") ? keyID : effective.label
        selectedKeyLabel.text = hasOv ? "🔵 \(displayLabel.uppercased()) (customized)" : displayLabel.uppercased()

        // Fill fields with current values
        primaryField.text = characterFrom(effective.action)
        longPressField.text = characterFrom(effective.altAction)

        // Show/hide reset button
        clearButton.isHidden = !hasOv
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Apply / Clear
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    @objc private func applyOverride() {
        guard let keyID = selectedKeyID else { return }

        let primaryChar = primaryField.text.flatMap { $0.isEmpty ? nil : String($0.prefix(1)) }
        let longPressChar = longPressField.text.flatMap { $0.isEmpty ? nil : String($0.prefix(1)) }

        guard let primary = primaryChar, !primary.isEmpty else {
            showValidationError("Primary character cannot be empty.")
            return
        }

        // Remove any existing override for this key+layout
        config.overrides.removeAll {
            $0.targetKeyID == keyID &&
            ($0.appliesToLayouts.isEmpty || $0.appliesToLayouts.contains(layoutID))
        }

        // Check if this matches the base definition — if so, no override needed
        let baseDef = allKeyDefs.first(where: { $0.def.id == keyID })?.def
        let basePrimary = characterFrom(baseDef?.action)
        let baseAlt = characterFrom(baseDef?.altAction)

        let primaryMatches = (primary == basePrimary)
        let altMatches = (longPressChar == baseAlt) || (longPressChar == nil && baseAlt == nil)

        if !(primaryMatches && altMatches) {
            // Create new override
            let altAction: KeyAction? = longPressChar.map { .character($0) }
            let override = UserOverride(
                targetKeyID: keyID,
                newLabel: primary,
                newAction: .character(primary),
                newAltAction: altAction,
                appliesToLayouts: [layoutID]
            )
            config.overrides.append(override)
        }

        saveAndRefresh()
        showBriefConfirmation()
    }

    @objc private func clearOverride() {
        guard let keyID = selectedKeyID else { return }

        config.overrides.removeAll {
            $0.targetKeyID == keyID &&
            ($0.appliesToLayouts.isEmpty || $0.appliesToLayouts.contains(layoutID))
        }

        saveAndRefresh()
    }

    @objc private func resetAllOverrides() {
        let alert = UIAlertController(
            title: "Reset All Customizations",
            message: "This will remove all key overrides for the \(layout.displayName) layout. This can't be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            self.config.overrides.removeAll {
                $0.appliesToLayouts.contains(self.layoutID) || $0.appliesToLayouts.isEmpty
            }
            self.saveAndRefresh()
        })
        present(alert, animated: true)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Helpers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func hasOverride(for keyID: String) -> Bool {
        config.overrides.contains {
            $0.targetKeyID == keyID &&
            ($0.appliesToLayouts.isEmpty || $0.appliesToLayouts.contains(layoutID))
        }
    }

    private func saveAndRefresh() {
        config.save()
        delegate?.keyCustomization(didUpdate: config.overrides)

        // Rebuild the mini keyboard to reflect changes
        buildMiniKeyboard()
        layoutMiniKeyboard()
        updateDetailPanel()
    }

    private func showValidationError(_ message: String) {
        let alert = UIAlertController(title: "Invalid", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func showBriefConfirmation() {
        let checkmark = UILabel()
        checkmark.text = "✓"
        checkmark.font = .systemFont(ofSize: 40, weight: .bold)
        checkmark.textColor = .systemGreen
        checkmark.sizeToFit()
        checkmark.center = CGPoint(x: applyButton.bounds.midX, y: applyButton.bounds.midY)
        applyButton.addSubview(checkmark)
        checkmark.alpha = 0
        UIView.animate(withDuration: 0.15, animations: { checkmark.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.3, delay: 0.4, options: [], animations: {
                checkmark.alpha = 0
            }) { _ in
                checkmark.removeFromSuperview()
            }
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - MiniKeyView
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// A small, tappable representation of a single key in the customization screen.
final class MiniKeyView: UIControl {

    let definition: KeyDefinition
    private let label = UILabel()
    private let altIndicator = UIView()  // small dot for keys with alt actions
    private let overrideDot = UIView()   // blue dot for overridden keys
    private var isSelectedKey = false

    init(definition: KeyDefinition, hasOverride: Bool) {
        self.definition = definition
        super.init(frame: .zero)
        setupAppearance(hasOverride: hasOverride)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupAppearance(hasOverride: Bool) {
        layer.cornerRadius = 4
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        backgroundColor = colorForStyle(definition.style)

        // Key label
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.4
        label.baselineAdjustment = .alignCenters
        addSubview(label)

        let text = definition.label
        if text.hasPrefix("sf:") {
            let symbolName = String(text.dropFirst(3))
            let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            if let img = UIImage(systemName: symbolName, withConfiguration: config) {
                let attachment = NSTextAttachment()
                attachment.image = img.withTintColor(.label, renderingMode: .alwaysOriginal)
                label.attributedText = NSAttributedString(attachment: attachment)
            } else {
                label.text = symbolName
                label.font = .systemFont(ofSize: 10)
            }
        } else {
            label.text = text
            label.font = .systemFont(ofSize: 14, weight: .regular)
        }

        // Alt action indicator (small gray dot in top-right corner)
        if definition.altAction != nil {
            altIndicator.backgroundColor = UIColor.systemGray3
            altIndicator.layer.cornerRadius = 2.5
            altIndicator.frame = CGRect(x: 0, y: 0, width: 5, height: 5)
            addSubview(altIndicator)
        }

        // Override indicator (blue dot in top-left corner)
        if hasOverride {
            overrideDot.backgroundColor = .systemBlue
            overrideDot.layer.cornerRadius = 3
            overrideDot.frame = CGRect(x: 0, y: 0, width: 6, height: 6)
            addSubview(overrideDot)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 2, dy: 2)
        altIndicator.frame.origin = CGPoint(x: bounds.width - 8, y: 3)
        overrideDot.frame.origin = CGPoint(x: 3, y: 3)
    }

    func updateSelection(isSelected: Bool) {
        isSelectedKey = isSelected
        if isSelected {
            layer.borderColor = UIColor.systemBlue.cgColor
            layer.borderWidth = 2.5
            backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        } else {
            layer.borderColor = UIColor.separator.cgColor
            layer.borderWidth = 1
            backgroundColor = colorForStyle(definition.style)
        }
    }

    private func colorForStyle(_ style: KeyStyle) -> UIColor {
        switch style {
        case .standard: return .systemBackground
        case .modifier: return UIColor.systemGray4
        case .utility:  return UIColor.systemGray5
        case .spacebar: return .systemBackground
        }
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.6 : 1.0
        }
    }
}
