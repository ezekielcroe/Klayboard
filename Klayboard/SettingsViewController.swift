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
        case data
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
        
        setupHeaderView()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Header UI
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    
    private func setupHeaderView() {
        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 110))
        
        let titleLabel = UILabel()
        titleLabel.text = "KLAY"
        titleLabel.font = .systemFont(ofSize: 34, weight: .black)
        titleLabel.textColor = UIColor(red: 0.72, green: 0.52, blue: 0.32, alpha: 1.0) // Warm terracotta
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = "The power-user's customizable keyboard"
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        headerView.addSubview(titleLabel)
        headerView.addSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: headerView.centerYAnchor, constant: 4),
            subtitleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
        ])
        
        tableView.tableHeaderView = headerView
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
        case .feedback:         return 4
        case .macros:           return config.macros.count + 1
        case .data:             return 1
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
        case .data:             return "Data & Privacy"
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
        case .data:
            return "Klay operates entirely on-device and never requests network access."
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
            cell.textLabel?.textColor = .label
            cell.imageView?.image = UIImage(systemName: "gearshape.fill")
            cell.imageView?.tintColor = .systemGray
            cell.accessoryType = .disclosureIndicator
            return cell

        case .layout:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            cell.accessoryView = nil
            
            let layouts: [LayoutID] = LayoutID.allCases.filter { $0 != .symbols }
            let id = layouts[indexPath.row]
            cell.textLabel?.text = BaseLayouts.all[id]?.displayName ?? id.rawValue
            cell.textLabel?.textColor = .label
            cell.accessoryType = (config.activeLayoutID == id) ? .checkmark : .none
            
            // Layout Icons
            switch id {
            case .standard: cell.imageView?.image = UIImage(systemName: "keyboard")
            case .coding:   cell.imageView?.image = UIImage(systemName: "chevron.left.forwardslash.chevron.right")
            case .markdown: cell.imageView?.image = UIImage(systemName: "text.format")
            default: break
            }
            cell.imageView?.tintColor = .systemBlue
            return cell

        case .rows:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            cell.accessoryView = nil
            
            let mode = RowMode.allCases[indexPath.row]
            cell.textLabel?.text = mode.displayName
            cell.textLabel?.textColor = .label
            cell.accessoryType = (config.rowMode == mode) ? .checkmark : .none
            
            cell.imageView?.image = UIImage(systemName: mode == .fiveRows ? "rectangle.grid.1x2.fill" : "rectangle.grid.2x2.fill")
            cell.imageView?.tintColor = .systemTeal
            return cell

        case .height:
            let cell = tableView.dequeueReusableCell(withIdentifier: "slider", for: indexPath) as! SliderCell
            cell.configure(
                title: "Scale",
                value: Float(config.height.scaleFactor),
                min: 0.75, max: 1.4,
                valueString: String(format: "%.0f%%", config.height.scaleFactor * 100)
            )
            cell.onValueChanged = { [weak self] val in
                self?.config.height.scaleFactor = CGFloat(val)
                self?.saveConfig()
                cell.updateValueLabel(String(format: "%.0f%%", val * 100))
            }
            return cell

        case .keyCustomization:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            cell.textLabel?.text = "Customize Keys…"
            cell.textLabel?.textColor = .label
            cell.imageView?.image = UIImage(systemName: "switch.2")
            cell.imageView?.tintColor = .systemPurple
            cell.accessoryType = .disclosureIndicator
            return cell

        case .feedback:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            cell.textLabel?.textColor = .label
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Haptic Feedback"
                cell.imageView?.image = UIImage(systemName: "hand.tap.fill")
                cell.imageView?.tintColor = .systemPink
                let sw = UISwitch()
                sw.isOn = config.hapticFeedbackEnabled
                sw.tag = 0
                sw.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 1:
                cell.textLabel?.text = "Sound Feedback"
                cell.imageView?.image = UIImage(systemName: "speaker.wave.2.fill")
                cell.imageView?.tintColor = .systemIndigo
                let sw = UISwitch()
                sw.isOn = config.soundFeedbackEnabled
                sw.tag = 1
                sw.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 2:
                cell.textLabel?.text = "Key Popups"
                cell.imageView?.image = UIImage(systemName: "character.textbox")
                cell.imageView?.tintColor = .systemOrange
                let sw = UISwitch()
                sw.isOn = config.showKeyPopups
                sw.tag = 2
                sw.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 3:
                let sliderCell = tableView.dequeueReusableCell(withIdentifier: "slider", for: indexPath) as! SliderCell
                sliderCell.configure(
                    title: "Long Press",
                    value: Float(config.longPressDuration),
                    min: 0.15, max: 0.8,
                    valueString: String(format: "%.2fs", config.longPressDuration)
                )
                sliderCell.onValueChanged = { [weak self] val in
                    self?.config.longPressDuration = Double(val)
                    self?.saveConfig()
                    sliderCell.updateValueLabel(String(format: "%.2fs", val))
                }
                return sliderCell
            default: break
            }
            return cell

        case .macros:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            if indexPath.row < config.macros.count {
                let macro = config.macros[indexPath.row]
                
                // Use a monospaced font for the trigger to make it look like code
                let attrStr = NSMutableAttributedString(string: "\(macro.trigger)  →  \(macro.expansion.prefix(30))")
                attrStr.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 15, weight: .semibold), range: NSRange(location: 0, length: macro.trigger.count))
                
                cell.textLabel?.attributedText = attrStr
                cell.textLabel?.textColor = macro.isEnabled ? .label : .secondaryLabel
                cell.imageView?.image = UIImage(systemName: "bolt.fill")
                cell.imageView?.tintColor = .systemYellow
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.attributedText = nil
                cell.textLabel?.text = "Add Macro"
                cell.textLabel?.textColor = .systemBlue
                cell.imageView?.image = UIImage(systemName: "plus.circle.fill")
                cell.imageView?.tintColor = .systemBlue
                cell.accessoryType = .none
            }
            return cell
            
        case .data:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            cell.textLabel?.text = "Clear Clipboard History"
            cell.textLabel?.textColor = .systemRed
            cell.imageView?.image = UIImage(systemName: "trash.fill")
            cell.imageView?.tintColor = .systemRed
            cell.accessoryType = .none
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
            
        case .data:
            let alert = UIAlertController(
                title: "Clear Clipboard",
                message: "This will permanently delete your stored clipboard history from the Klay App Group.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Clear History", style: .destructive) { _ in
                // Directly remove the stored clipboard history key from the shared App Group
                if let defaults = UserDefaults(suiteName: AppConstants.appGroupID) {
                    defaults.removeObject(forKey: "clipboardHistory")
                }
            })
            present(alert, animated: true)

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
    private let titleLabel = UILabel()
    private let slider = UISlider()
    private let valueLabel = UILabel()
    var onValueChanged: ((Float) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        // 1. Title on the left
        titleLabel.font = .systemFont(ofSize: 17, weight: .regular)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 2. Value on the right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .regular)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        // 3. Slider in the middle
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        contentView.addSubview(titleLabel)
        contentView.addSubview(slider)
        contentView.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            // Pin title to the left with a fixed width
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 90),

            // Pin slider between title and value label
            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            slider.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            // Pin value label to the right with a fixed width
            valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            valueLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 55)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, value: Float, min: Float, max: Float, valueString: String) {
        titleLabel.text = title
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        valueLabel.text = valueString
    }

    func updateValueLabel(_ text: String) {
        valueLabel.text = text
    }

    @objc private func sliderChanged() {
        onValueChanged?(slider.value)
    }
}
