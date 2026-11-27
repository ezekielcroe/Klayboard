// EmojiPickerView.swift
// Emoji panel rendered as an overlay within the keyboard bounds, same
// presentation pattern as ClipboardHistoryView.
//
// A keyboard extension has no API to summon the system emoji keyboard, so
// this is a self-contained picker: category tabs, a scrolling grid, and a
// Recents category persisted to App Group UserDefaults. The panel stays
// open across insertions (system-keyboard behavior); the ⌫ button in the
// header deletes without leaving the panel.
//
// The emoji set is a curated, hardcoded list — no Unicode-table generation
// at runtime, no risk of tofu boxes from post-release emoji on older iOS.

import UIKit

protocol EmojiPickerViewDelegate: AnyObject {
    func emojiPickerDidSelect(emoji: String)
    func emojiPickerDidTapBackspace()
    func emojiPickerDidDismiss()
}

final class EmojiPickerView: UIView {

    weak var delegate: EmojiPickerViewDelegate?

    // ── Recents persistence ──────────────────
    private static let recentsKey = "emojiRecents"
    private static let maxRecents = 24

    // ── Data ─────────────────────────────────
    private struct Category {
        let symbol: String      // SF Symbol for the tab
        let emoji: [String]
    }

    private var recents: [String] = []
    private var categories: [Category] = []
    private var activeCategoryIndex = 0

    // ── UI ───────────────────────────────────
    private let headerView = UIView()
    private let tabStack = UIStackView()
    private var collectionView: UICollectionView!
    private let cellID = "EmojiCell"

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Init
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    override init(frame: CGRect) {
        super.init(frame: frame)
        loadRecents()
        buildCategories()
        // Land on Recents if the user has any, otherwise Smileys.
        activeCategoryIndex = recents.isEmpty ? 1 : 0
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Data
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func buildCategories() {
        categories = [
            Category(symbol: "clock", emoji: recents),
            Category(symbol: "face.smiling", emoji: [
                "😀","😃","😄","😁","😆","😅","😂","🤣","🙂","😉","😊","😇",
                "🥰","😍","🤩","😘","😗","😚","😋","😜","🤪","😝","🤑","🤗",
                "🤔","🤐","😐","😑","😶","😏","😒","🙄","😬","😮‍💨","🤥","😌",
                "😔","😪","🤤","😴","😷","🤒","🤕","🤢","🤮","🥵","🥶","🥴",
                "😵","🤯","🥳","😎","🤓","🧐","😕","😟","🙁","😮","😯","😲",
                "😳","🥺","😦","😨","😰","😥","😢","😭","😱","😖","😣","😞",
                "😓","😩","😫","🥱","😤","😡","😠","🤬","💀","💩","🤡","👻",
                "👽","🤖","😺","😸","😹","😻","😼","😽","🙀","😿","😾",
            ]),
            Category(symbol: "hand.wave", emoji: [
                "👋","🤚","✋","🖖","👌","🤌","🤏","✌️","🤞","🤟","🤘","🤙",
                "👈","👉","👆","👇","☝️","👍","👎","✊","👊","🤛","🤜","👏",
                "🙌","👐","🤲","🤝","🙏","💪","🦾","✍️","💅","🤳","👂","👀",
                "👤","🗣️","👶","🧒","👦","👧","🧑","👨","👩","🧓","👴","👵",
                "🙋","🤦","🤷","💁","🙆","🙅","🧏","👮","💂","🕵️","👷","🤴",
                "👸","🦸","🦹","🧙","🧚","🧛","🧟","💆","💇","🚶","🏃","🧍",
            ]),
            Category(symbol: "pawprint", emoji: [
                "🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐨","🐯","🦁","🐮",
                "🐷","🐸","🐵","🐔","🐧","🐦","🐤","🦆","🦅","🦉","🦇","🐺",
                "🐗","🐴","🦄","🐝","🐛","🦋","🐌","🐞","🐜","🦂","🐢","🐍",
                "🦎","🐙","🦑","🦞","🦀","🐠","🐟","🐬","🐳","🦈","🐊","🐘",
                "🦒","🦘","🐪","🦬","🐎","🐖","🐏","🐑","🐐","🦌","🐕","🐈",
                "🌵","🎄","🌲","🌳","🌴","🌱","🌿","☘️","🍀","🍁","🍄","🌸",
                "🌼","🌻","🌞","🌙","⭐","🌈","☀️","⛅","☁️","🌧️","⛈️","❄️",
            ]),
            Category(symbol: "fork.knife", emoji: [
                "🍏","🍎","🍐","🍊","🍋","🍌","🍉","🍇","🍓","🫐","🍒","🍑",
                "🥭","🍍","🥥","🥝","🍅","🥑","🥦","🥬","🥒","🌶️","🌽","🥕",
                "🥔","🍠","🥐","🍞","🥖","🥨","🧀","🥚","🍳","🥞","🧇","🥓",
                "🍗","🍖","🌭","🍔","🍟","🍕","🥪","🌮","🌯","🥗","🍝","🍜",
                "🍲","🍣","🍱","🥟","🍤","🍚","🍘","🍥","🍡","🍦","🍰","🎂",
                "🧁","🍫","🍬","🍭","🍮","🍯","☕","🍵","🥤","🧃","🍺","🍷",
            ]),
            Category(symbol: "soccerball", emoji: [
                "⚽","🏀","🏈","⚾","🥎","🎾","🏐","🏉","🥏","🎱","🏓","🏸",
                "🏒","🏑","🥍","🏏","🥅","⛳","🏹","🎣","🥊","🥋","🎽","🛹",
                "⛸️","🥌","🎿","⛷️","🏂","🏋️","🤸","🤺","🤾","🏌️","🏇","🧘",
                "🏄","🏊","🤽","🚣","🧗","🚴","🚵","🏆","🥇","🥈","🥉","🏅",
                "🎖️","🎗️","🎫","🎪","🤹","🎭","🎨","🎬","🎤","🎧","🎼","🎹",
                "🥁","🎷","🎺","🎸","🎻","🎲","♟️","🎯","🎳","🎮","🎰","🧩",
            ]),
            Category(symbol: "car", emoji: [
                "🚗","🚕","🚙","🚌","🚎","🏎️","🚓","🚑","🚒","🚐","🛻","🚚",
                "🚛","🚜","🛴","🚲","🛵","🏍️","🚨","🚔","🚍","🚘","🚖","✈️",
                "🛫","🛬","🛩️","💺","🚁","🚀","🛸","⛵","🚤","🛥️","🛳️","⛴️",
                "🚢","⚓","🚉","🚂","🚆","🚇","🚊","🚝","🗼","🏰","🏯","🏟️",
                "🎡","🎢","🎠","⛲","🏖️","🏝️","🏜️","🌋","⛰️","🏔️","🗻","🏕️",
                "🏠","🏡","🏢","🏬","🏥","🏦","🏨","🏪","🏫","💒","⛪","🕌",
            ]),
            Category(symbol: "lightbulb", emoji: [
                "⌚","📱","💻","⌨️","🖥️","🖨️","🖱️","💽","💾","💿","📀","📷",
                "📸","📹","🎥","📞","☎️","📟","📠","📺","📻","🎙️","⏰","⏳",
                "🔋","🔌","💡","🔦","🕯️","🗑️","🛢️","💸","💵","💰","💳","💎",
                "⚖️","🔧","🔨","⚒️","🛠️","⛏️","🔩","⚙️","🧲","🔫","💣","🔪",
                "🛡️","🚬","⚰️","🔮","📿","💈","⚗️","🔭","🔬","🕳️","💊","💉",
                "🧬","🦠","🧫","🌡️","🧹","🧺","🧻","🚽","🚿","🛁","🔑","🚪",
            ]),
            Category(symbol: "heart", emoji: [
                "❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💔","❤️‍🔥","💕",
                "💞","💓","💗","💖","💘","💝","💟","☮️","✝️","☪️","🕉️","☸️",
                "✡️","☯️","♈","♉","♊","♋","♌","♍","♎","♏","♐","♑",
                "♒","♓","⚛️","✅","❌","❓","❗","💯","🔞","📵","🚭","⚠️",
                "🔱","⚜️","🔰","♻️","✳️","❇️","✴️","🌀","💤","🏧","🚾","♿",
                "🅿️","🈚","🈯","💹","❎","🔆","🔅","➕","➖","➗","✖️","♾️",
            ]),
        ]
    }

    private func loadRecents() {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupID),
              let stored = defaults.stringArray(forKey: Self.recentsKey) else { return }
        recents = Array(stored.prefix(Self.maxRecents))
    }

    private func saveRecents() {
        UserDefaults(suiteName: AppConstants.appGroupID)?
            .set(recents, forKey: Self.recentsKey)
    }

    /// Called by the owner after an emoji is inserted so Recents stays current.
    func recordUse(of emoji: String) {
        recents.removeAll { $0 == emoji }
        recents.insert(emoji, at: 0)
        if recents.count > Self.maxRecents {
            recents = Array(recents.prefix(Self.maxRecents))
        }
        saveRecents()
        categories[0] = Category(symbol: "clock", emoji: recents)
        if activeCategoryIndex == 0 { collectionView.reloadData() }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - UI
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func setupUI() {
        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.97)
        layer.cornerRadius = 10
        layer.masksToBounds = true

        // ── Header: category tabs + backspace + close ──
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = UIColor.secondarySystemBackground
        addSubview(headerView)

        tabStack.axis = .horizontal
        tabStack.distribution = .fillEqually
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(tabStack)

        for (i, cat) in categories.enumerated() {
            let btn = UIButton(type: .system)
            btn.setImage(
                UIImage(systemName: cat.symbol,
                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)),
                for: .normal
            )
            btn.tag = i
            btn.addTarget(self, action: #selector(didTapTab(_:)), for: .touchUpInside)
            tabStack.addArrangedSubview(btn)
        }

        let backspaceButton = UIButton(type: .system)
        backspaceButton.setImage(
            UIImage(systemName: "delete.left",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)),
            for: .normal
        )
        backspaceButton.tintColor = .label
        backspaceButton.addTarget(self, action: #selector(didTapBackspace), for: .touchUpInside)
        backspaceButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(backspaceButton)

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

        // ── Grid ──────────────────────────────
        let flow = UICollectionViewFlowLayout()
        flow.itemSize = CGSize(width: 40, height: 40)
        flow.minimumInteritemSpacing = 2
        flow.minimumLineSpacing = 4
        flow.sectionInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flow)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(EmojiCell.self, forCellWithReuseIdentifier: cellID)
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 40),

            tabStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 6),
            tabStack.topAnchor.constraint(equalTo: headerView.topAnchor),
            tabStack.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            tabStack.trailingAnchor.constraint(equalTo: backspaceButton.leadingAnchor, constant: -6),

            backspaceButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backspaceButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -10),
            backspaceButton.widthAnchor.constraint(equalToConstant: 34),

            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            collectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateTabTints()
    }

    private func updateTabTints() {
        for case let btn as UIButton in tabStack.arrangedSubviews {
            btn.tintColor = (btn.tag == activeCategoryIndex) ? .systemBlue : .secondaryLabel
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    @objc private func didTapTab(_ sender: UIButton) {
        guard sender.tag != activeCategoryIndex else { return }
        activeCategoryIndex = sender.tag
        updateTabTints()
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
    }

    @objc private func didTapBackspace() {
        delegate?.emojiPickerDidTapBackspace()
    }

    @objc private func didTapClose() {
        delegate?.emojiPickerDidDismiss()
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Collection View
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

extension EmojiPickerView: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        categories[activeCategoryIndex].emoji.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellID, for: indexPath) as! EmojiCell
        cell.label.text = categories[activeCategoryIndex].emoji[indexPath.item]
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let emoji = categories[activeCategoryIndex].emoji[indexPath.item]
        delegate?.emojiPickerDidSelect(emoji: emoji)
    }
}

private final class EmojiCell: UICollectionViewCell {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = UIFont.systemFont(ofSize: 28)
        label.textAlignment = .center
        label.frame = contentView.bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }
}
