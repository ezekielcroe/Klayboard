// ClipboardHistoryView.swift
// Overlay panel that displays clipboard history within the keyboard bounds.
//
// Shows a scrollable list of recent clipboard items. Tap an item to paste it.
// Rendered as an overlay on top of the keyboard rows.

import UIKit

protocol ClipboardHistoryViewDelegate: AnyObject {
    func clipboardHistoryDidSelect(text: String)
    func clipboardHistoryDidDismiss()
    func clipboardHistoryDidClear()
}

final class ClipboardHistoryView: UIView {

    weak var delegate: ClipboardHistoryViewDelegate?

    private var items: [String] = []
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let headerView = UIView()
    private let emptyLabel = UILabel()
    private let cellID = "ClipboardCell"

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Init
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    init(items: [String]) {
        self.items = items
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Setup
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func setupUI() {
        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.97)
        layer.cornerRadius = 10
        layer.masksToBounds = true

        // ── Header bar ────────────────────────
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = UIColor.secondarySystemBackground
        addSubview(headerView)

        let titleLabel = UILabel()
        titleLabel.text = "Clipboard History"
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(
            UIImage(systemName: "xmark.circle.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)),
            for: .normal
        )
        closeButton.tintColor = .secondaryLabel
        closeButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(closeButton)

        let clearButton = UIButton(type: .system)
        clearButton.setTitle("Clear", for: .normal)
        clearButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        clearButton.setTitleColor(.systemRed, for: .normal)
        clearButton.addTarget(self, action: #selector(didTapClear), for: .touchUpInside)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isHidden = items.isEmpty
        headerView.addSubview(clearButton)

        // ── Table view ────────────────────────
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellID)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
        addSubview(tableView)

        // ── Empty state ───────────────────────
        emptyLabel.text = "No clipboard history yet.\nCopy some text and it will appear here."
        emptyLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = !items.isEmpty
        addSubview(emptyLabel)

        // ── Constraints ───────────────────────
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 14),

            clearButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -10),

            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 10),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 30),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -30),
        ])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    @objc private func didTapClose() {
        delegate?.clipboardHistoryDidDismiss()
    }

    @objc private func didTapClear() {
        delegate?.clipboardHistoryDidClear()
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Update
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func updateItems(_ newItems: [String]) {
        items = newItems
        emptyLabel.isHidden = !items.isEmpty
        tableView.reloadData()
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - UITableViewDataSource / Delegate
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

extension ClipboardHistoryView: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath)
        let text = items[indexPath.row]

        // Truncate long items for display
        let preview = text.replacingOccurrences(of: "\n", with: " ↵ ")
        let maxLen = 80
        let displayText = preview.count > maxLen
            ? String(preview.prefix(maxLen)) + "…"
            : preview

        cell.textLabel?.text = displayText
        cell.textLabel?.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        cell.textLabel?.textColor = .label
        cell.textLabel?.numberOfLines = 2
        cell.backgroundColor = .clear
        cell.selectionStyle = .default

        // Badge the most recent item
        if indexPath.row == 0 {
            cell.textLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            let attachment = NSTextAttachment()
            let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            attachment.image = UIImage(systemName: "doc.on.clipboard.fill", withConfiguration: config)?
                .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
            let icon = NSMutableAttributedString(attachment: attachment)
            icon.append(NSAttributedString(string: "  " + displayText))
            cell.textLabel?.attributedText = icon
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let text = items[indexPath.row]
        delegate?.clipboardHistoryDidSelect(text: text)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, completion in
            self?.items.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            self?.emptyLabel.isHidden = !(self?.items.isEmpty ?? true)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
