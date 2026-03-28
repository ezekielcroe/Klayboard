// SettingsViewController.swift
// Container App configuration dashboard.
// Programmatic UIKit — no storyboards.

import UIKit

final class SettingsViewController: UITableViewController {

    // ── Config ───────────────────────────────
    private var config: UserConfiguration = .default

    // ── Sections ─────────────────────────────
    private enum Section: Int, CaseIterable {
        case setup = 0
        case layout
        case rows
        case height
        case keyCustomization
        case feedback
        case macros
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Lifecycle
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Klayboard"
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(SliderCell.self, forCellReuseIdentifier: "slider")
        config = UserConfiguration.load()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Table View Data Source
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let s = Section(rawValue: section) else { return 0 }
        switch s {
        case .setup:            return 1
        case .layout:           return LayoutID.allCases.filter { $0 != .symbols }.count
        case .rows:             return RowMode.allCases.count
        case .height:           return 1
        case .keyCustomization: return 1
        case .feedback:         return 3
        case .macros:           return config.macros.count + 1  // +1 for "Add Macro"
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let s = Section(rawValue: section) else { return nil }
        switch s {
        case .setup:            return "Setup"
        case .layout:           return "Default Layout"
        case .rows:             return "Row Mode"
        case .height:           return "Key Height"
        case .keyCustomization: return "Key Customization"
        case .feedback:         return "Feedback"
        case .macros:           return "Text Expansion Macros"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let s = Section(rawValue: section) else { return nil }
        switch s {
        case .setup:
            return "Go to Settings → General → Keyboard → Keyboards → Add New Keyboard → Klayboard."
        case .rows:
            return "5 Rows hides the utility row (cursor/clipboard). Tap the ≡ button to toggle it back temporarily."
        case .height:
            return "Adjust the height of all keys. Drag left for compact, right for taller keys."
        case .keyCustomization:
            let count = config.overrides.count
            return count > 0 ? "\(count) key\(count == 1 ? "" : "s") customized." : "Tap to remap any key's primary and long-press characters."
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        }

        switch section {

        case .setup:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            cell.textLabel?.text = "Open Keyboard Settings"
            cell.textLabel?.textColor = .systemBlue
            cell.accessoryType = .disclosureIndicator
            return cell

        case .layout:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            let layouts: [LayoutID] = LayoutID.allCases.filter { $0 != .symbols }
            let id = layouts[indexPath.row]
            cell.textLabel?.text = BaseLayouts.all[id]?.displayName ?? id.rawValue
            cell.textLabel?.textColor = .label
            cell.accessoryType = (config.activeLayoutID == id) ? .checkmark : .none
            return cell

        case .rows:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            let mode = RowMode.allCases[indexPath.row]
            cell.textLabel?.text = mode.displayName
            cell.textLabel?.textColor = .label
            cell.accessoryType = (config.rowMode == mode) ? .checkmark : .none
            return cell

        case .height:
            let cell = tableView.dequeueReusableCell(withIdentifier: "slider", for: indexPath) as! SliderCell
            cell.configure(
                value: Float(config.height.scaleFactor),
                min: 0.75, max: 1.4,
                label: "Scale: \(String(format: "%.0f%%", config.height.scaleFactor * 100))"
            )
            cell.onValueChanged = { [weak self] val in
                self?.config.height.scaleFactor = CGFloat(val)
                self?.saveConfig()
                // Update the label live
                cell.updateLabel("Scale: \(String(format: "%.0f%%", val * 100))")
            }
            return cell

        case .keyCustomization:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            cell.textLabel?.text = "Customize Keys…"
            cell.textLabel?.textColor = .systemBlue
            cell.accessoryType = .disclosureIndicator
            return cell

        case .feedback:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            cell.textLabel?.textColor = .label
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Haptic Feedback"
                let sw = UISwitch()
                sw.isOn = config.hapticFeedbackEnabled
                sw.tag = 0
                sw.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 1:
                cell.textLabel?.text = "Sound Feedback"
                let sw = UISwitch()
                sw.isOn = config.soundFeedbackEnabled
                sw.tag = 1
                sw.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 2:
                cell.textLabel?.text = "Key Popups"
                let sw = UISwitch()
                sw.isOn = config.showKeyPopups
                sw.tag = 2
                sw.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            default: break
            }
            return cell

        case .macros:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            if indexPath.row < config.macros.count {
                let macro = config.macros[indexPath.row]
                cell.textLabel?.text = "\(macro.trigger) → \(macro.expansion.prefix(40))"
                cell.textLabel?.textColor = macro.isEnabled ? .label : .secondaryLabel
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "+ Add Macro"
                cell.textLabel?.textColor = .systemBlue
                cell.accessoryType = .none
            }
            return cell
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Selection
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }

        switch section {
        case .setup:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }

        case .layout:
            let layouts: [LayoutID] = LayoutID.allCases.filter { $0 != .symbols }
            config.activeLayoutID = layouts[indexPath.row]
            saveConfig()
            tableView.reloadSections(IndexSet(integer: section.rawValue), with: .none)

        case .rows:
            config.rowMode = RowMode.allCases[indexPath.row]
            saveConfig()
            tableView.reloadSections(IndexSet(integer: section.rawValue), with: .none)

        case .keyCustomization:
            let vc = KeyCustomizationViewController()
            vc.config = config
            vc.layoutID = config.activeLayoutID
            vc.delegate = self
            navigationController?.pushViewController(vc, animated: true)

        case .macros:
            if indexPath.row < config.macros.count {
                showEditMacro(at: indexPath.row)
            } else {
                showAddMacro()
            }

        default: break
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let section = Section(rawValue: indexPath.section) else { return false }
        return section == .macros && indexPath.row < config.macros.count
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            config.macros.remove(at: indexPath.row)
            saveConfig()
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Toggle Switches
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    @objc private func toggleChanged(_ sender: UISwitch) {
        switch sender.tag {
        case 0: config.hapticFeedbackEnabled = sender.isOn
        case 1: config.soundFeedbackEnabled = sender.isOn
        case 2: config.showKeyPopups = sender.isOn
        default: break
        }
        saveConfig()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Macro Editing
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func showAddMacro() {
        let alert = UIAlertController(title: "New Macro", message: "Enter a trigger and its expansion.", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Trigger (e.g., @@)" }
        alert.addTextField { $0.placeholder = "Expansion (e.g., user@example.com)" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            guard let self = self,
                  let trigger = alert.textFields?[0].text, !trigger.isEmpty,
                  let expansion = alert.textFields?[1].text, !expansion.isEmpty else { return }
            let macro = MacroDefinition(trigger: trigger, expansion: expansion)
            self.config.macros.append(macro)
            self.saveConfig()
            self.tableView.reloadSections(IndexSet(integer: Section.macros.rawValue), with: .automatic)
        })
        present(alert, animated: true)
    }

    private func showEditMacro(at index: Int) {
        let macro = config.macros[index]
        let alert = UIAlertController(title: "Edit Macro", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = macro.trigger; $0.placeholder = "Trigger" }
        alert.addTextField { $0.text = macro.expansion; $0.placeholder = "Expansion" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self = self,
                  let trigger = alert.textFields?[0].text, !trigger.isEmpty,
                  let expansion = alert.textFields?[1].text, !expansion.isEmpty else { return }
            self.config.macros[index] = MacroDefinition(trigger: trigger, expansion: expansion)
            self.saveConfig()
            self.tableView.reloadSections(IndexSet(integer: Section.macros.rawValue), with: .automatic)
        })
        present(alert, animated: true)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Persistence
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func saveConfig() {
        config.save()
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - KeyCustomizationDelegate
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

extension SettingsViewController: KeyCustomizationDelegate {
    func keyCustomization(didUpdate overrides: [UserOverride]) {
        config.overrides = overrides
        // Reload the key customization section to update the footer count
        tableView.reloadSections(IndexSet(integer: Section.keyCustomization.rawValue), with: .none)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Slider Cell
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final class SliderCell: UITableViewCell {
    private let slider = UISlider()
    private let valueLabel = UILabel()
    var onValueChanged: ((Float) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        contentView.addSubview(valueLabel)
        contentView.addSubview(slider)

        NSLayoutConstraint.activate([
            valueLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            valueLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 90),

            slider.leadingAnchor.constraint(equalTo: valueLabel.trailingAnchor, constant: 12),
            slider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            slider.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(value: Float, min: Float, max: Float, label: String) {
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        valueLabel.text = label
    }

    func updateLabel(_ text: String) {
        valueLabel.text = text
    }

    @objc private func sliderChanged() {
        onValueChanged?(slider.value)
    }
}
