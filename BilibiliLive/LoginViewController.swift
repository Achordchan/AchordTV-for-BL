//
//  LoginViewController.swift
//  BilibiliLive
//
//  Created by Etan Chen on 2021/3/28.
//

import Foundation
import SnapKit
import UIKit

class LoginViewController: UIViewController {
    private enum Phase: String {
        case loading
        case waiting
        case scanned
        case expired
        case failed
        case success
    }

    private enum Layout {
        static let panelSize = CGSize(width: 1320, height: 720)
        static let panelRadius: CGFloat = 52
        static let qrCardSize: CGFloat = 500
        static let qrInset: CGFloat = 40
        static let qrCardRadius: CGFloat = 32
        static let horizontalPadding: CGFloat = 100
    }

    private enum Palette {
        static let waiting = UIColor(red: 0.50, green: 0.77, blue: 1.00, alpha: 1) // #7FC4FF，取自背景插画
        static let done = UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        static let error = UIColor(red: 1.00, green: 0.42, blue: 0.42, alpha: 1)
        static let idle = UIColor(white: 1, alpha: 0.45)
        static let secondaryText = UIColor(white: 1, alpha: 0.6)
        static let statusText = UIColor(white: 1, alpha: 0.78)
        static let brandPink = UIColor(red: 0.98, green: 0.45, blue: 0.60, alpha: 1) // #FB7299
    }

    /// TV 端二维码有效期约 180 秒
    private let qrLifetime: TimeInterval = 180
    /// 每隔几秒轮询一次扫码状态
    private let pollEvery = 2
    /// 无人操作时最多自动刷新几次，之后停下等用户手动刷新
    private let maxAutoRefresh = 5

    private let ciContext = CIContext()

    // MARK: Views

    private let backdropView: UIImageView = {
        let view = UIImageView(image: UIImage(named: "LoginBackdrop"))
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }()

    private let shadeLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        let base = UIColor(red: 10 / 255, green: 14 / 255, blue: 24 / 255, alpha: 1)
        layer.colors = [base.withAlphaComponent(0.2).cgColor, base.withAlphaComponent(0.55).cgColor]
        return layer
    }()

    private let panelShadowView: UIView = {
        let view = UIView()
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.45
        view.layer.shadowRadius = 60
        view.layer.shadowOffset = CGSize(width: 0, height: 40)
        view.layer.shadowPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: Layout.panelSize),
            cornerRadius: Layout.panelRadius
        ).cgPath
        return view
    }()

    private let panelView = BLGlass.makeView(cornerRadius: Layout.panelRadius)

    private let qrCardView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = Layout.qrCardRadius
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()

    private let qrImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.layer.magnificationFilter = .nearest
        return view
    }()

    private let spinner: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .large)
        view.color = UIColor(white: 0, alpha: 0.5)
        view.hidesWhenStopped = true
        return view
    }()

    private let qrOverlayView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(white: 1, alpha: 0.86)
        view.alpha = 0
        return view
    }()

    private let overlayIconView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 130, weight: .medium)
        return view
    }()

    private let overlayLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 36, weight: .semibold)
        label.textColor = UIColor(white: 0.1, alpha: 1)
        label.textAlignment = .center
        return label
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "登录哔哩哔哩"
        label.font = .systemFont(ofSize: 64, weight: .bold)
        label.textColor = .white
        return label
    }()

    private let stepTexts = [
        "用哔哩哔哩 App 扫码",
        "在手机上点「确认登录」",
    ]

    private lazy var stepRows: [(number: UILabel, text: UILabel)] = stepTexts.enumerated().map { index, text in
        let number = UILabel()
        number.text = "\(index + 1)"
        number.font = .monospacedDigitSystemFont(ofSize: 34, weight: .semibold)
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 34)
        return (number, label)
    }

    private let statusDotView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 7
        return view
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 30, weight: .regular)
        label.textColor = Palette.statusText
        return label
    }()

    private let refreshButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "刷新二维码"
        config.image = UIImage(systemName: "arrow.clockwise")
        config.imagePadding = 14
        config.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 44, bottom: 20, trailing: 44)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 32, weight: .semibold)
            return attributes
        }
        return UIButton(configuration: config)
    }()

    // MARK: State

    private var phase: Phase = .loading
    private var authCode = ""
    private var expireDate = Date()
    private var tickTimer: Timer?
    private var tickCount = 0
    private var autoRefreshCount = 0
    /// 每次请求新二维码都会递增，用来丢弃旧二维码迟到的回调
    private var generation = 0
    private var hasAppeared = false

    static func create() -> LoginViewController {
        LoginViewController()
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        apply(phase: .loading, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        shadeLayer.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasAppeared {
            hasAppeared = true
            playEntrance()
        }
        #if DEBUG
            if let preview = ProcessInfo.processInfo.environment["LOGIN_PREVIEW_PHASE"].flatMap(Phase.init(rawValue:)) {
                showPreview(phase: preview)
                return
            }
        #endif
        autoRefreshCount = 0
        requestQRCode()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        generation += 1
        stopTimer()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [refreshButton]
    }

    // MARK: Flow

    private func requestQRCode() {
        generation += 1
        let current = generation
        stopTimer()
        apply(phase: .loading)

        ApiRequest.requestLoginQR(handler: { [weak self] code, url in
            guard let self, current == self.generation else { return }
            self.authCode = code
            self.expireDate = Date().addingTimeInterval(self.qrLifetime)
            UIView.transition(with: self.qrImageView, duration: 0.3, options: .transitionCrossDissolve) {
                self.qrImageView.image = self.generateQRCode(from: url)
            }
            self.apply(phase: .waiting)
            self.startTimer()
        }, onError: { [weak self] in
            guard let self, current == self.generation else { return }
            self.apply(phase: .failed)
        })
    }

    private func startTimer() {
        stopTimer()
        tickCount = 0
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        tickCount += 1
        if expireDate.timeIntervalSinceNow <= 0 {
            handleExpired()
            return
        }
        if phase == .waiting {
            updateStatusText()
        }
        if tickCount % pollEvery == 0 {
            poll()
        }
    }

    private func poll() {
        let current = generation
        ApiRequest.verifyLoginQR(code: authCode) { [weak self] state in
            guard let self, current == self.generation, self.phase != .success else { return }
            switch state {
            case .waiting:
                // 手机上取消确认后会回到未扫码状态
                if self.phase == .scanned { self.apply(phase: .waiting) }
            case .scanned:
                if self.phase != .scanned { self.apply(phase: .scanned) }
            case .expire:
                self.handleExpired()
            case let .success(token, cookies):
                self.stopTimer()
                self.apply(phase: .success)
                // 只有被采用的登录结果才写入 cookie（registerAccount 拉取资料时需要新账号的 cookie）
                CookieHandler.shared.saveCookie(list: cookies, syncWithAccount: false)
                AccountManager.shared.registerAccount(token: token, cookies: cookies) { [weak self] _ in
                    self?.didLoginSucceed()
                }
            case .fail:
                break
            }
        }
    }

    private func handleExpired() {
        stopTimer()
        if autoRefreshCount < maxAutoRefresh {
            autoRefreshCount += 1
            requestQRCode()
        } else {
            generation += 1
            apply(phase: .expired)
        }
    }

    private func didLoginSucceed() {
        generation += 1
        stopTimer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            AppDelegate.shared.resetTabBar()
        }
    }

    @objc private func actionRefresh() {
        autoRefreshCount = 0
        requestQRCode()
    }

    // MARK: Phase UI

    private func apply(phase: Phase, animated: Bool = true) {
        self.phase = phase

        switch phase {
        case .loading:
            qrImageView.alpha = qrImageView.image == nil ? 0 : 0.15
            spinner.startAnimating()
            setOverlay(nil, animated: animated)
            setStatus(color: Palette.idle, pulsing: false, text: "正在获取二维码…")
            highlightStep(0, animated: animated)
            setRefreshButton(title: "刷新二维码", enabled: false)
        case .waiting:
            qrImageView.alpha = 1
            spinner.stopAnimating()
            setOverlay(nil, animated: animated)
            setStatus(color: Palette.waiting, pulsing: true, text: nil)
            updateStatusText()
            highlightStep(0, animated: animated)
            setRefreshButton(title: "刷新二维码", enabled: true)
        case .scanned:
            spinner.stopAnimating()
            setOverlay((symbol: "checkmark.circle.fill", tint: Palette.done, text: "已扫码"), animated: animated)
            setStatus(color: nil, pulsing: false, text: nil)
            highlightStep(1, animated: animated)
            setRefreshButton(title: "刷新二维码", enabled: false)
        case .expired:
            spinner.stopAnimating()
            setOverlay((symbol: "clock.arrow.circlepath", tint: UIColor(white: 0.35, alpha: 1), text: "二维码已过期"), animated: animated)
            setStatus(color: nil, pulsing: false, text: nil)
            highlightStep(nil, animated: animated)
            setRefreshButton(title: "重新获取", enabled: true)
        case .failed:
            spinner.stopAnimating()
            setOverlay((symbol: "wifi.exclamationmark", tint: Palette.error, text: "获取失败"), animated: animated)
            setStatus(color: Palette.error, pulsing: false, text: "请检查网络连接")
            highlightStep(nil, animated: animated)
            setRefreshButton(title: "重新获取", enabled: true)
        case .success:
            spinner.stopAnimating()
            setOverlay((symbol: "checkmark.circle.fill", tint: Palette.done, text: "登录成功"), animated: animated)
            setStatus(color: Palette.done, pulsing: false, text: "正在进入首页…")
            highlightStep(nil, animated: animated)
            setRefreshButton(title: "刷新二维码", enabled: false)
        }
    }

    private func setRefreshButton(title: String, enabled: Bool) {
        refreshButton.configuration?.title = title
        refreshButton.isEnabled = enabled
        refreshButton.alpha = enabled ? 1 : 0
        if enabled {
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }
    }

    private func updateStatusText() {
        let remaining = max(0, Int(expireDate.timeIntervalSinceNow.rounded(.up)))
        statusLabel.text = String(format: "等待扫码 · %d:%02d 后自动刷新", remaining / 60, remaining % 60)
    }

    /// color 为 nil 时隐藏整行状态
    private func setStatus(color: UIColor?, pulsing: Bool, text: String?) {
        statusDotView.superview?.alpha = color == nil ? 0 : 1
        statusDotView.backgroundColor = color
        if let text { statusLabel.text = text }

        statusDotView.layer.removeAnimation(forKey: "pulse")
        guard pulsing else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.6
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        statusDotView.layer.add(pulse, forKey: "pulse")
    }

    private func setOverlay(_ content: (symbol: String, tint: UIColor, text: String)?, animated: Bool) {
        let duration = animated ? 0.28 : 0
        guard let content else {
            UIView.animate(withDuration: duration) {
                self.qrOverlayView.alpha = 0
            }
            return
        }

        overlayIconView.image = UIImage(systemName: content.symbol)
        overlayIconView.tintColor = content.tint
        overlayLabel.text = content.text

        let wasHidden = qrOverlayView.alpha == 0
        if wasHidden {
            overlayIconView.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        }
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.4) {
            self.qrOverlayView.alpha = 1
            self.overlayIconView.transform = .identity
        }
    }

    /// active 为 nil 时所有步骤都压暗
    private func highlightStep(_ active: Int?, animated: Bool) {
        for (index, row) in stepRows.enumerated() {
            let isActive = index == active
            let update = {
                row.number.textColor = isActive ? Palette.brandPink : Palette.secondaryText
                row.text.textColor = isActive ? .white : Palette.secondaryText
                row.text.font = .systemFont(ofSize: 34, weight: isActive ? .semibold : .regular)
            }
            if animated {
                UIView.transition(with: row.text, duration: 0.25, options: .transitionCrossDissolve, animations: update)
            } else {
                update()
            }
        }
    }

    private func playEntrance() {
        backdropView.alpha = 0
        panelShadowView.alpha = 0
        panelShadowView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        UIView.animate(withDuration: 0.4) {
            self.backdropView.alpha = 1
        }
        UIView.animate(withDuration: 0.6, delay: 0.1, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.panelShadowView.alpha = 1
            self.panelShadowView.transform = .identity
        }
    }

    #if DEBUG
        /// 调试用：设置环境变量 LOGIN_PREVIEW_PHASE=scanned 等直接查看各状态，不发起登录请求
        private func showPreview(phase: Phase) {
            generation += 1
            stopTimer()
            qrImageView.image = generateQRCode(from: "https://passport.bilibili.com/x/passport-tv-login/h5/qrcode/auth?auth_code=preview")
            expireDate = Date().addingTimeInterval(168)
            apply(phase: phase, animated: false)
        }
    #endif

    // MARK: QR

    private func generateQRCode(from string: String) -> UIImage? {
        guard
            let data = string.data(using: .ascii),
            let filter = CIFilter(name: "CIQRCodeGenerator")
        else {
            return nil
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }
        let extent = outputImage.extent.integral
        guard !extent.isEmpty else { return nil }

        let targetSize: CGFloat = 840
        let scale = max(1, floor(targetSize / max(extent.width, extent.height)))
        let width = Int(extent.width * scale)
        let height = Int(extent.height * scale)

        guard
            let cgImage = ciContext.createCGImage(outputImage, from: extent),
            let bitmapContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else {
            return nil
        }

        bitmapContext.interpolationQuality = .none
        bitmapContext.scaleBy(x: scale, y: scale)
        bitmapContext.draw(cgImage, in: extent)

        guard let scaledImage = bitmapContext.makeImage() else { return nil }
        return UIImage(cgImage: scaledImage)
    }

    // MARK: Layout

    private func setupUI() {
        view.backgroundColor = UIColor(red: 27 / 255, green: 36 / 255, blue: 51 / 255, alpha: 1)

        view.addSubview(backdropView)
        view.layer.addSublayer(shadeLayer)
        view.addSubview(panelShadowView)
        panelShadowView.addSubview(panelView)

        let content = panelView.contentView

        // 左：二维码卡片
        content.addSubview(qrCardView)
        qrCardView.addSubview(qrImageView)
        qrCardView.addSubview(spinner)
        qrCardView.addSubview(qrOverlayView)

        let overlayStack = UIStackView(arrangedSubviews: [overlayIconView, overlayLabel])
        overlayStack.axis = .vertical
        overlayStack.alignment = .center
        overlayStack.spacing = 24
        qrOverlayView.addSubview(overlayStack)

        // 右：标题、步骤、状态、按钮
        let stepsStack = UIStackView(arrangedSubviews: stepRows.map { row in
            row.number.snp.makeConstraints { make in
                make.width.equalTo(36)
            }
            let stack = UIStackView(arrangedSubviews: [row.number, row.text])
            stack.axis = .horizontal
            stack.spacing = 18
            stack.alignment = .firstBaseline
            return stack
        })
        stepsStack.axis = .vertical
        stepsStack.spacing = 26

        let statusStack = UIStackView(arrangedSubviews: [statusDotView, statusLabel])
        statusStack.axis = .horizontal
        statusStack.alignment = .center
        statusStack.spacing = 16

        let infoStack = UIStackView(arrangedSubviews: [titleLabel, stepsStack, statusStack, refreshButton])
        infoStack.axis = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 44
        infoStack.setCustomSpacing(48, after: stepsStack)
        content.addSubview(infoStack)

        refreshButton.addTarget(self, action: #selector(actionRefresh), for: .primaryActionTriggered)

        backdropView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        panelShadowView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(Layout.panelSize)
        }

        panelView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        qrCardView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.horizontalPadding)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(Layout.qrCardSize)
        }

        qrImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(Layout.qrInset)
        }

        spinner.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        qrOverlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        overlayStack.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        statusDotView.snp.makeConstraints { make in
            make.width.height.equalTo(14)
        }

        infoStack.snp.makeConstraints { make in
            make.leading.equalTo(qrCardView.snp.trailing).offset(Layout.horizontalPadding)
            make.trailing.lessThanOrEqualToSuperview().offset(-Layout.horizontalPadding)
            make.centerY.equalToSuperview()
        }
    }
}
