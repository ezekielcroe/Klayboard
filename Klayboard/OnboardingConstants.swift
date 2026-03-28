//
//  OnboardingConstants.swift
//  Klayboard
//
//  Created by Zhi Zheng Yeo on 28/3/26.
//


// OnboardingViewController.swift
// First-launch onboarding flow for Klay keyboard.
//
// 5 screens: Welcome → Install → Layout Tour → Hidden Powers → Try It
// Uses UIPageViewController for swipe navigation with manual advance buttons.
// Skippable at any point. Persists completion flag to App Group UserDefaults.
//
// Programmatic UIKit — no storyboards.

import UIKit

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Onboarding Constants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

private enum OnboardingConstants {
    static let hasCompletedKey = "hasCompletedOnboarding"
    static let keyboardActivatedKey = "keyboardExtensionActivated"

    // Klay brand colors — warm, grounded stone palette
    static let stoneBackground  = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.09, blue: 0.08, alpha: 1.0)
            : UIColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 1.0)
    }
    static let warmAccent       = UIColor(red: 0.72, green: 0.52, blue: 0.32, alpha: 1.0) // terracotta
    static let subtleText       = UIColor.secondaryLabel
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Main Onboarding Controller
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final class OnboardingViewController: UIViewController {

    private let pageVC = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal
    )
    private var pages: [UIViewController] = []
    private var currentIndex = 0

    // Page indicator
    private let pageControl = UIPageControl()

    // ── Lifecycle ─────────────────────────────

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OnboardingConstants.stoneBackground

        pages = [
            WelcomePage(delegate: self),
            InstallPage(delegate: self),
            LayoutTourPage(delegate: self),
            HiddenPowersPage(delegate: self),
            TryItPage(delegate: self)
        ]

        setupPageViewController()
        setupPageControl()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    // ── Setup ─────────────────────────────────

    private func setupPageViewController() {
        addChild(pageVC)
        view.addSubview(pageVC.view)
        pageVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pageVC.didMove(toParent: self)
        pageVC.dataSource = self
        pageVC.delegate = self
        pageVC.setViewControllers([pages[0]], direction: .forward, animated: false)
    }

    private func setupPageControl() {
        pageControl.numberOfPages = pages.count
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = OnboardingConstants.warmAccent
        pageControl.pageIndicatorTintColor = OnboardingConstants.warmAccent.withAlphaComponent(0.25)
        pageControl.isUserInteractionEnabled = false
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageControl)
        NSLayoutConstraint.activate([
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Page Navigation Delegate
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

protocol OnboardingPageDelegate: AnyObject {
    func onboardingAdvance()
    func onboardingSkip()
    func onboardingComplete()
}

extension OnboardingViewController: OnboardingPageDelegate {

    func onboardingAdvance() {
        guard currentIndex + 1 < pages.count else {
            onboardingComplete()
            return
        }
        currentIndex += 1
        pageVC.setViewControllers([pages[currentIndex]], direction: .forward, animated: true)
        pageControl.currentPage = currentIndex
    }

    func onboardingSkip() {
        onboardingComplete()
    }

    func onboardingComplete() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID)
        defaults?.set(true, forKey: OnboardingConstants.hasCompletedKey)
        defaults?.synchronize()

        let nav = UINavigationController(rootViewController: SettingsViewController())

        guard let window = view.window else {
            // Fallback: just present
            present(nav, animated: true)
            return
        }

        UIView.transition(with: window, duration: 0.35, options: .transitionCrossDissolve, animations: {
            window.rootViewController = nav
        })
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - UIPageViewControllerDataSource / Delegate
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

extension OnboardingViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let idx = pages.firstIndex(of: viewController), idx > 0 else { return nil }
        return pages[idx - 1]
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let idx = pages.firstIndex(of: viewController), idx + 1 < pages.count else { return nil }
        return pages[idx + 1]
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController],
                            transitionCompleted completed: Bool) {
        guard completed,
              let visible = pageViewController.viewControllers?.first,
              let idx = pages.firstIndex(of: visible) else { return }
        currentIndex = idx
        pageControl.currentPage = idx
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Static Helper: Onboarding Gate
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

extension OnboardingViewController {
    /// Returns true if onboarding has already been completed.
    static var isCompleted: Bool {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID)
        return defaults?.bool(forKey: OnboardingConstants.hasCompletedKey) ?? false
    }
}


// ══════════════════════════════════════════════════════
// MARK: - PAGE 1: Welcome
// ══════════════════════════════════════════════════════

private final class WelcomePage: UIViewController {

    weak var delegate: OnboardingPageDelegate?

    init(delegate: OnboardingPageDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OnboardingConstants.stoneBackground

        // ── Logo / title ──────────────────────
        let titleLabel = UILabel()
        titleLabel.text = "KLAY"
        titleLabel.font = UIFont.systemFont(ofSize: 48, weight: .black)
        titleLabel.textColor = OnboardingConstants.warmAccent
        titleLabel.textAlignment = .center

        let tagline = UILabel()
        tagline.text = "The keyboard that stays\nout of your way."
        tagline.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        tagline.textColor = .label
        tagline.textAlignment = .center
        tagline.numberOfLines = 0

        let philosophy = UILabel()
        philosophy.text = "No AI. No cloud. No lag.\nJust your keys, your way."
        philosophy.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        philosophy.textColor = OnboardingConstants.subtleText
        philosophy.textAlignment = .center
        philosophy.numberOfLines = 0

        // ── Decorative divider ────────────────
        let divider = UIView()
        divider.backgroundColor = OnboardingConstants.warmAccent.withAlphaComponent(0.3)
        divider.translatesAutoresizingMaskIntoConstraints = false

        // ── Buttons ───────────────────────────
        let startButton = makePrimaryButton(title: "Get Started")
        startButton.addTarget(self, action: #selector(didTapStart), for: .touchUpInside)

        let skipButton = UIButton(type: .system)
        skipButton.setTitle("Skip setup", for: .normal)
        skipButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        skipButton.setTitleColor(OnboardingConstants.subtleText, for: .normal)
        skipButton.addTarget(self, action: #selector(didTapSkip), for: .touchUpInside)

        // ── Layout ────────────────────────────
        let stack = UIStackView(arrangedSubviews: [titleLabel, divider, tagline, philosophy])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = UIStackView(arrangedSubviews: [startButton, skipButton])
        buttonStack.axis = .vertical
        buttonStack.alignment = .center
        buttonStack.spacing = 16
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        view.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 40),
            divider.heightAnchor.constraint(equalToConstant: 2),

            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),

            startButton.widthAnchor.constraint(equalToConstant: 260),
            startButton.heightAnchor.constraint(equalToConstant: 50),

            buttonStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60)
        ])
    }

    @objc private func didTapStart() { delegate?.onboardingAdvance() }
    @objc private func didTapSkip() { delegate?.onboardingSkip() }
}


// ══════════════════════════════════════════════════════
// MARK: - PAGE 2: Install the Keyboard
// ══════════════════════════════════════════════════════

private final class InstallPage: UIViewController {

    weak var delegate: OnboardingPageDelegate?
    private let statusLabel = UILabel()
    private let continueButton = UIButton(type: .system)
    private var checkTimer: Timer?

    init(delegate: OnboardingPageDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OnboardingConstants.stoneBackground

        // ── Title ─────────────────────────────
        let title = UILabel()
        title.text = "Enable Klay"
        title.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        title.textColor = .label
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "Follow these steps to add Klay\nas your keyboard."
        subtitle.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        subtitle.textColor = OnboardingConstants.subtleText
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        // ── Steps card ────────────────────────
        let stepsCard = makeStepsCard()

        // ── Open Settings button ──────────────
        let openSettingsButton = makePrimaryButton(title: "Open Settings")
        openSettingsButton.addTarget(self, action: #selector(didTapOpenSettings), for: .touchUpInside)

        // ── Status indicator ──────────────────
        statusLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = OnboardingConstants.subtleText
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        updateStatus()

        // ── Continue ──────────────────────────
        continueButton.setTitle("Continue", for: .normal)
        continueButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        continueButton.setTitleColor(.white, for: .normal)
        continueButton.backgroundColor = OnboardingConstants.warmAccent
        continueButton.layer.cornerRadius = 12
        continueButton.addTarget(self, action: #selector(didTapContinue), for: .touchUpInside)
        continueButton.translatesAutoresizingMaskIntoConstraints = false

        // ── Layout ────────────────────────────
        let topStack = UIStackView(arrangedSubviews: [title, subtitle])
        topStack.axis = .vertical
        topStack.spacing = 8
        topStack.alignment = .center
        topStack.translatesAutoresizingMaskIntoConstraints = false

        let bottomStack = UIStackView(arrangedSubviews: [openSettingsButton, statusLabel, continueButton])
        bottomStack.axis = .vertical
        bottomStack.spacing = 14
        bottomStack.alignment = .center
        bottomStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(topStack)
        view.addSubview(stepsCard)
        view.addSubview(bottomStack)

        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            topStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            topStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            stepsCard.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 28),
            stepsCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stepsCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            openSettingsButton.widthAnchor.constraint(equalToConstant: 260),
            openSettingsButton.heightAnchor.constraint(equalToConstant: 50),
            continueButton.widthAnchor.constraint(equalToConstant: 260),
            continueButton.heightAnchor.constraint(equalToConstant: 50),

            bottomStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            bottomStack.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Poll for keyboard activation when user returns from Settings
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func makeStepsCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor.secondarySystemGroupedBackground
        card.layer.cornerRadius = 14
        card.translatesAutoresizingMaskIntoConstraints = false

        let steps = [
            ("1", "Open Settings"),
            ("2", "General → Keyboard"),
            ("3", "Keyboards → Add New Keyboard…"),
            ("4", "Select \"Klayboard\""),
            ("5", "Tap Klayboard → Allow Full Access")
        ]

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (num, text) in steps {
            let row = makeStepRow(number: num, text: text)
            stack.addArrangedSubview(row)
        }

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])

        return card
    }

    private func makeStepRow(number: String, text: String) -> UIView {
        let container = UIView()

        let badge = UILabel()
        badge.text = number
        badge.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = OnboardingConstants.warmAccent
        badge.layer.cornerRadius = 12
        badge.layer.masksToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(badge)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            badge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 24),
            badge.heightAnchor.constraint(equalToConstant: 24),

            label.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            container.heightAnchor.constraint(equalToConstant: 28)
        ])

        return container
    }

    private func isKeyboardActivated() -> Bool {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupID)
        // Check if the keyboard extension has ever loaded (writes a timestamp)
        return defaults?.object(forKey: OnboardingConstants.keyboardActivatedKey) != nil
    }

    private func updateStatus() {
        if isKeyboardActivated() {
            statusLabel.text = "✓ Klay is enabled"
            statusLabel.textColor = UIColor.systemGreen
            continueButton.alpha = 1.0
        } else {
            statusLabel.text = "Klay not detected yet.\nCome back after adding it in Settings."
            statusLabel.textColor = OnboardingConstants.subtleText
            continueButton.alpha = 0.5
        }
    }

    @objc private func didTapOpenSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    @objc private func didTapContinue() {
        // Allow continuing even if not detected — the user might know what they're doing
        delegate?.onboardingAdvance()
    }
}


// ══════════════════════════════════════════════════════
// MARK: - PAGE 3: Layout Tour
// ══════════════════════════════════════════════════════

private final class LayoutTourPage: UIViewController {

    weak var delegate: OnboardingPageDelegate?
    private var rowLabels: [UILabel] = []
    private var rowViews: [UIView] = []
    private var animationTimer: Timer?
    private var currentHighlight = 0

    init(delegate: OnboardingPageDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // Row descriptions for the standard 6-row layout
    private let rowDescriptions = [
        ("Utility Row",  "Cursor nav, word delete, copy/paste, case toggle"),
        ("Number Row",   "Dedicated number keys — swipe down for symbols"),
        ("Top Alpha",    "Q–P with symbol alternates on every key"),
        ("Mid Alpha",    "A–L with punctuation alternates"),
        ("Bottom Alpha", "Shift, Z–M, backspace"),
        ("Spacebar Row", "Layout switch, globe, spacebar, return")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OnboardingConstants.stoneBackground

        // ── Title ─────────────────────────────
        let title = UILabel()
        title.text = "Your Keyboard"
        title.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        title.textColor = .label
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        // ── Mini keyboard diagram ─────────────
        let diagramContainer = UIView()
        diagramContainer.translatesAutoresizingMaskIntoConstraints = false

        let rowData: [(String, UIColor)] = [
            ("◄◄  ►►  ◄  ►  ⌫  ⌫█  Aa  ⊡  📋", UIColor.systemGray5),
            ("1   2   3   4   5   6   7   8   9   0", UIColor.systemGray4),
            ("q  w  e  r  t  y  u  i  o  p", UIColor.secondarySystemGroupedBackground),
            ("a  s  d  f  g  h  j  k  l", UIColor.secondarySystemGroupedBackground),
            ("⇧  z  x  c  v  b  n  m  ⌫", UIColor.secondarySystemGroupedBackground),
            ("123   🌐   ⎵ space ⎵   ⏎", UIColor.systemGray4)
        ]

        let rowStack = UIStackView()
        rowStack.axis = .vertical
        rowStack.spacing = 3
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        for (i, (text, bgColor)) in rowData.enumerated() {
            let rowView = UIView()
            rowView.backgroundColor = bgColor
            rowView.layer.cornerRadius = 6
            rowView.translatesAutoresizingMaskIntoConstraints = false

            let label = UILabel()
            label.text = text
            label.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .label
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.6
            label.translatesAutoresizingMaskIntoConstraints = false

            rowView.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: rowView.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: rowView.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(lessThanOrEqualTo: rowView.trailingAnchor, constant: -4),
                rowView.heightAnchor.constraint(equalToConstant: i == 0 ? 30 : 34)
            ])

            rowStack.addArrangedSubview(rowView)
            rowViews.append(rowView)
        }

        diagramContainer.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: diagramContainer.topAnchor),
            rowStack.leadingAnchor.constraint(equalTo: diagramContainer.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: diagramContainer.trailingAnchor),
            rowStack.bottomAnchor.constraint(equalTo: diagramContainer.bottomAnchor)
        ])

        // ── Description label (changes with animation) ──
        let descTitle = UILabel()
        descTitle.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        descTitle.textColor = OnboardingConstants.warmAccent
        descTitle.textAlignment = .center
        descTitle.translatesAutoresizingMaskIntoConstraints = false
        rowLabels.append(descTitle)

        let descBody = UILabel()
        descBody.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        descBody.textColor = OnboardingConstants.subtleText
        descBody.textAlignment = .center
        descBody.numberOfLines = 0
        descBody.translatesAutoresizingMaskIntoConstraints = false
        rowLabels.append(descBody)

        // ── Continue ──────────────────────────
        let nextButton = makePrimaryButton(title: "Next")
        nextButton.addTarget(self, action: #selector(didTapNext), for: .touchUpInside)

        let descStack = UIStackView(arrangedSubviews: [descTitle, descBody])
        descStack.axis = .vertical
        descStack.spacing = 4
        descStack.alignment = .center
        descStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(title)
        view.addSubview(diagramContainer)
        view.addSubview(descStack)
        view.addSubview(nextButton)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            diagramContainer.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 24),
            diagramContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            diagramContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            descStack.topAnchor.constraint(equalTo: diagramContainer.bottomAnchor, constant: 24),
            descStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            descStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            nextButton.widthAnchor.constraint(equalToConstant: 260),
            nextButton.heightAnchor.constraint(equalToConstant: 50),
            nextButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startHighlightAnimation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func startHighlightAnimation() {
        animationTimer?.invalidate()
        currentHighlight = 0
        highlightRow(0)

        animationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.currentHighlight = (self.currentHighlight + 1) % self.rowDescriptions.count
            self.highlightRow(self.currentHighlight)
        }
    }

    private func highlightRow(_ index: Int) {
        let (name, desc) = rowDescriptions[index]

        UIView.animate(withDuration: 0.3) {
            for (i, rv) in self.rowViews.enumerated() {
                if i == index {
                    rv.layer.borderWidth = 2.5
                    rv.layer.borderColor = OnboardingConstants.warmAccent.cgColor
                    rv.transform = CGAffineTransform(scaleX: 1.02, y: 1.05)
                } else {
                    rv.layer.borderWidth = 0
                    rv.layer.borderColor = UIColor.clear.cgColor
                    rv.transform = .identity
                }
            }
        }

        UIView.transition(with: rowLabels[0], duration: 0.25, options: .transitionCrossDissolve) {
            self.rowLabels[0].text = name
        }
        UIView.transition(with: rowLabels[1], duration: 0.25, options: .transitionCrossDissolve) {
            self.rowLabels[1].text = desc
        }
    }

    @objc private func didTapNext() { delegate?.onboardingAdvance() }
}


// ══════════════════════════════════════════════════════
// MARK: - PAGE 4: Hidden Powers
// ══════════════════════════════════════════════════════

private final class HiddenPowersPage: UIViewController {

    weak var delegate: OnboardingPageDelegate?

    init(delegate: OnboardingPageDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OnboardingConstants.stoneBackground

        // ── Title ─────────────────────────────
        let title = UILabel()
        title.text = "Hidden Superpowers"
        title.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        title.textColor = .label
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        // ── Feature cards ─────────────────────
        let cards = [
            makeFeatureCard(
                icon: "hand.draw",
                title: "Swipe Down for Symbols",
                body: "Every letter and number key has a secondary character. Swipe down or long-press to type it instantly.\n\nq → +    w → =    1 → !    2 → @"
            ),
            makeFeatureCard(
                icon: "space",
                title: "Double-Space → Period",
                body: "Tap space twice quickly after a word and Klay inserts a period + space, then auto-shifts for the next sentence."
            ),
            makeFeatureCard(
                icon: "delete.left",
                title: "Smart Delete Acceleration",
                body: "Tap delete to remove one character. Hold it to accelerate — first by character, then by whole word."
            ),
            makeFeatureCard(
                icon: "textformat.alt",
                title: "Case Cycling",
                body: "The Aa button in the utility row cycles the previous word: lower → Title → UPPER → lower."
            )
        ]

        let cardStack = UIStackView(arrangedSubviews: cards)
        cardStack.axis = .vertical
        cardStack.spacing = 12
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // ── Continue ──────────────────────────
        let nextButton = makePrimaryButton(title: "Next")
        nextButton.addTarget(self, action: #selector(didTapNext), for: .touchUpInside)

        scrollView.addSubview(cardStack)
        view.addSubview(title)
        view.addSubview(scrollView)
        view.addSubview(nextButton)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -16),

            cardStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            cardStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cardStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            cardStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -8),

            nextButton.widthAnchor.constraint(equalToConstant: 260),
            nextButton.heightAnchor.constraint(equalToConstant: 50),
            nextButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60)
        ])
    }

    private func makeFeatureCard(icon: String, title: String, body: String) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor.secondarySystemGroupedBackground
        card.layer.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        let iconView = UIImageView(image: UIImage(systemName: icon, withConfiguration: iconConfig))
        iconView.tintColor = OnboardingConstants.warmAccent
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .label

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        bodyLabel.textColor = OnboardingConstants.subtleText
        bodyLabel.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(iconView)
        card.addSubview(textStack)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            iconView.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            iconView.widthAnchor.constraint(equalToConstant: 28),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            textStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])

        return card
    }

    @objc private func didTapNext() { delegate?.onboardingAdvance() }
}


// ══════════════════════════════════════════════════════
// MARK: - PAGE 5: Try It
// ══════════════════════════════════════════════════════

private final class TryItPage: UIViewController {

    weak var delegate: OnboardingPageDelegate?
    private let textView = UITextView()
    private var challengeLabels: [UILabel] = []

    // Challenges for the user to try
    private let challenges = [
        ("Type anything", "Start typing a sentence"),
        ("Swipe down on \"1\"", "You should get \"!\""),
        ("Double-tap shift", "Locks caps — tap again to unlock")
    ]

    init(delegate: OnboardingPageDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = OnboardingConstants.stoneBackground

        // ── Title ─────────────────────────────
        let title = UILabel()
        title.text = "Take It for a Spin"
        title.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        title.textColor = .label
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = UILabel()
        subtitle.text = "Switch to Klay using the 🌐 key\nif it's not already active."
        subtitle.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        subtitle.textColor = OnboardingConstants.subtleText
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        // ── Text field to try typing ──────────
        textView.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        textView.backgroundColor = UIColor.secondarySystemGroupedBackground
        textView.layer.cornerRadius = 12
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.text = ""
        textView.tintColor = OnboardingConstants.warmAccent
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self

        // Placeholder
        let placeholder = UILabel()
        placeholder.text = "Try typing here…"
        placeholder.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        placeholder.textColor = UIColor.placeholderText
        placeholder.tag = 999
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 12),
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 16)
        ])

        // ── Mini challenges ───────────────────
        let challengeTitle = UILabel()
        challengeTitle.text = "Try these:"
        challengeTitle.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        challengeTitle.textColor = .label
        challengeTitle.translatesAutoresizingMaskIntoConstraints = false

        let challengeStack = UIStackView()
        challengeStack.axis = .vertical
        challengeStack.spacing = 8
        challengeStack.translatesAutoresizingMaskIntoConstraints = false

        for (title, hint) in challenges {
            let row = makeChallengeRow(title: title, hint: hint)
            challengeStack.addArrangedSubview(row)
        }

        // ── Finish button ─────────────────────
        let doneButton = makePrimaryButton(title: "I'm Ready")
        doneButton.addTarget(self, action: #selector(didTapDone), for: .touchUpInside)

        view.addSubview(title)
        view.addSubview(subtitle)
        view.addSubview(textView)
        view.addSubview(challengeTitle)
        view.addSubview(challengeStack)
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitle.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),

            textView.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 20),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            textView.heightAnchor.constraint(equalToConstant: 100),

            challengeTitle.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 20),
            challengeTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),

            challengeStack.topAnchor.constraint(equalTo: challengeTitle.bottomAnchor, constant: 10),
            challengeStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            challengeStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            doneButton.widthAnchor.constraint(equalToConstant: 260),
            doneButton.heightAnchor.constraint(equalToConstant: 50),
            doneButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Auto-focus the text view so the keyboard appears
        textView.becomeFirstResponder()
    }

    private func makeChallengeRow(title: String, hint: String) -> UIView {
        let container = UIView()

        let circle = UILabel()
        circle.text = "○"
        circle.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        circle.textColor = OnboardingConstants.warmAccent
        circle.translatesAutoresizingMaskIntoConstraints = false
        challengeLabels.append(circle)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let hintLabel = UILabel()
        hintLabel.text = hint
        hintLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        hintLabel.textColor = OnboardingConstants.subtleText
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(circle)
        container.addSubview(titleLabel)
        container.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            circle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            circle.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
            circle.widthAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: circle.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            hintLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            hintLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            hintLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    /// Check typed text for challenge completion
    private func checkChallenges() {
        let text = textView.text ?? ""

        // Challenge 1: typed anything
        if !text.isEmpty && challengeLabels.count > 0 {
            challengeLabels[0].text = "●"
        }

        // Challenge 2: contains "!"
        if text.contains("!") && challengeLabels.count > 1 {
            challengeLabels[1].text = "●"
        }

        // Challenge 3: contains at least 2 consecutive uppercase letters (caps lock evidence)
        if challengeLabels.count > 2 {
            let uppercasePattern = text.range(of: "[A-Z]{2,}", options: .regularExpression)
            if uppercasePattern != nil {
                challengeLabels[2].text = "●"
            }
        }
    }

    @objc private func didTapDone() { delegate?.onboardingComplete() }
}

extension TryItPage: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        // Hide placeholder
        if let placeholder = textView.viewWithTag(999) {
            placeholder.isHidden = !textView.text.isEmpty
        }
        checkChallenges()
    }
}


// ══════════════════════════════════════════════════════
// MARK: - Shared UI Helpers
// ══════════════════════════════════════════════════════

/// Creates a styled primary action button used across all onboarding pages.
private func makePrimaryButton(title: String) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
    button.setTitleColor(.white, for: .normal)
    button.backgroundColor = OnboardingConstants.warmAccent
    button.layer.cornerRadius = 12
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}