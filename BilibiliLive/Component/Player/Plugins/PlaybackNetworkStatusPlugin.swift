//
//  PlaybackNetworkStatusPlugin.swift
//  BilibiliLive
//
//  播放页网络状态：
//  - 进度条显示时，右下角浮出一个玻璃胶囊：CDN 传输状态 + 实时加载速度 + 已缓冲时长；
//  - 画面中心转圈加载时，在转圈下方显示「正在加载 · 速度」。
//  速度取自 AVPlayerItem 的 access log（播放器实际收到的字节），直连与多 CDN 加速都适用。
//

import AVKit
import SnapKit
import UIKit

/// 当前播放资源的传输方式
enum PlaybackTransportStatus: Equatable {
    case unknown
    case direct
    case accelerated(hostCount: Int)
    /// 加速中，但有部分请求改走了直连
    case acceleratedPartiallyDirect
    /// 设置开启了加速，但加速不可用，已回退直连
    case fellBackToDirect
    /// 直播：当前清晰度与线路（如「原画 · 线路 1」）
    case live(description: String)
}

final class PlaybackNetworkStatusPlugin: NSObject, CommonPlayerPlugin {
    private let statusProvider: () -> PlaybackTransportStatus

    private weak var playerVC: AVPlayerViewController?
    private var timer: Timer?
    private var isTransportBarVisible = false

    // 速度采样
    private weak var sampledItem: AVPlayerItem?
    private var lastBytes: Int64 = 0
    private var lastSampleTime: TimeInterval = 0
    /// 平滑后的速度（字节/秒）；nil 表示还没有可用样本
    private var smoothedSpeed: Double?

    // 右下角状态胶囊
    /// 与左侧系统信息标签（简介 / 章节…）同高、同一水平中线，圆角做成胶囊
    private let chipView = BLGlass.makeView(cornerRadius: 32)
    private let modeIconView = UIImageView()
    private let modeLabel = UILabel()
    private let separatorView = UIView()
    private let speedIconView = UIImageView(image: UIImage(systemName: "arrow.down"))
    private let speedLabel = UILabel()

    // 中心加载提示
    private let loadingView = BLGlass.makeView(cornerRadius: 20, border: false)
    private let loadingLabel = UILabel()

    init(statusProvider: @escaping () -> PlaybackTransportStatus) {
        self.statusProvider = statusProvider
        super.init()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - CommonPlayerPlugin

    func addViewToPlayerOverlay(container: UIView) {
        setupChip(in: container)
        setupLoading(in: container)
        startTimer()
    }

    func playerDidLoad(playerVC: AVPlayerViewController) {
        self.playerVC = playerVC
    }

    /// 插件被移除（换集、退出）时停表并移除自己的视图；换 player 时不处理，继续采样新 player
    func playerWillCleanUp(playerVC: AVPlayerViewController) {
        stopTimer()
        chipView.removeFromSuperview()
        loadingView.removeFromSuperview()
    }

    func playerTransportBarVisibilityWillChange(visible: Bool, coordinator: AVPlayerViewControllerAnimationCoordinator) {
        isTransportBarVisible = visible
        if visible { refreshChip() }
        coordinator.addCoordinatedAnimations { [weak self] in
            self?.chipView.alpha = visible ? 1 : 0
        }
    }

    // MARK: - 布局

    private func setupChip(in container: UIView) {
        chipView.alpha = 0
        chipView.isUserInteractionEnabled = false
        container.addSubview(chipView)
        chipView.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(80)
            make.bottom.equalToSuperview().inset(48)
            make.height.equalTo(64)
        }

        let secondary = BLGlass.Color.secondaryText
        modeIconView.tintColor = .white
        modeIconView.contentMode = .scaleAspectFit
        modeIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        modeLabel.font = UIFont.systemFont(ofSize: 21, weight: .medium)
        modeLabel.textColor = .white

        separatorView.backgroundColor = UIColor(white: 1, alpha: 0.25)
        separatorView.snp.makeConstraints { make in
            make.width.equalTo(1.5)
            make.height.equalTo(20)
        }

        speedIconView.tintColor = secondary
        speedIconView.contentMode = .scaleAspectFit
        speedIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        speedLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 21, weight: .regular)
        speedLabel.textColor = secondary

        let modeStack = UIStackView(arrangedSubviews: [modeIconView, modeLabel])
        modeStack.spacing = 8
        modeStack.alignment = .center
        let speedStack = UIStackView(arrangedSubviews: [speedIconView, speedLabel])
        speedStack.spacing = 6
        speedStack.alignment = .center
        let stack = UIStackView(arrangedSubviews: [modeStack, separatorView, speedStack])
        stack.spacing = 14
        stack.alignment = .center
        chipView.contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(26)
            make.centerY.equalToSuperview()
        }
    }

    private func setupLoading(in container: UIView) {
        loadingView.alpha = 0
        loadingView.isUserInteractionEnabled = false
        container.addSubview(loadingView)
        loadingView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            // 放在系统加载转圈的下方
            make.centerY.equalToSuperview().offset(96)
            make.height.equalTo(40)
        }
        loadingLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .medium)
        loadingLabel.textColor = .white
        loadingView.contentView.addSubview(loadingLabel)
        loadingLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(18)
            make.centerY.equalToSuperview()
        }
    }

    // MARK: - 刷新

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        sampleSpeed()
        refreshLoading()
        if isTransportBarVisible {
            refreshChip()
        }
    }

    /// 按 access log 里累计传输字节的增量计算速度，指数平滑避免跳动
    private func sampleSpeed() {
        guard let item = playerVC?.player?.currentItem else {
            sampledItem = nil
            smoothedSpeed = nil
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let bytes = item.accessLog()?.events.reduce(Int64(0)) { $0 + max(0, $1.numberOfBytesTransferred) } ?? 0
        if sampledItem !== item {
            sampledItem = item
            lastBytes = bytes
            lastSampleTime = now
            smoothedSpeed = nil
            return
        }
        let interval = now - lastSampleTime
        guard interval > 0.2 else { return }
        let instant = Double(max(0, bytes - lastBytes)) / interval
        lastBytes = bytes
        lastSampleTime = now
        if let previous = smoothedSpeed {
            smoothedSpeed = previous * 0.5 + instant * 0.5
        } else {
            smoothedSpeed = instant
        }
    }

    private func refreshChip() {
        let (icon, text) = Self.describe(statusProvider())
        modeIconView.image = icon.flatMap { UIImage(systemName: $0) }
        modeIconView.isHidden = icon == nil
        modeLabel.text = text
        modeLabel.isHidden = text == nil
        separatorView.isHidden = text == nil

        var parts = [String]()
        if let speed = smoothedSpeed {
            parts.append(Self.format(speed: speed))
        } else {
            parts.append("—")
        }
        if let buffered = bufferedAhead(), buffered >= 1 {
            parts.append("已缓冲 \(Self.format(duration: buffered))")
        }
        speedLabel.text = parts.joined(separator: "  ·  ")
    }

    private func refreshLoading() {
        let player = playerVC?.player
        let item = player?.currentItem
        let isLoading = player == nil
            || item == nil
            || item?.status == .unknown
            || player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
        let failed = item?.status == .failed
        let shouldShow = isLoading && !failed
        if shouldShow {
            if let speed = smoothedSpeed, speed > 0 {
                loadingLabel.text = "正在加载  ·  \(Self.format(speed: speed))"
            } else {
                loadingLabel.text = "正在加载…"
            }
        }
        let targetAlpha: CGFloat = shouldShow ? 1 : 0
        if loadingView.alpha != targetAlpha {
            UIView.animate(withDuration: 0.25) {
                self.loadingView.alpha = targetAlpha
            }
        }
    }

    /// 当前播放位置之后已缓冲的秒数
    private func bufferedAhead() -> Double? {
        guard let player = playerVC?.player, let item = player.currentItem else { return nil }
        let current = player.currentTime().seconds
        guard current.isFinite else { return nil }
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            let start = range.start.seconds
            let end = range.end.seconds
            if start <= current + 0.5, end >= current {
                return max(0, end - current)
            }
        }
        return nil
    }

    // MARK: - 文案

    private static func describe(_ status: PlaybackTransportStatus) -> (icon: String?, text: String?) {
        switch status {
        case .unknown:
            return (nil, nil)
        case .direct:
            return ("network", "直连")
        case let .accelerated(hostCount):
            return ("bolt.fill", hostCount > 1 ? "多 CDN 加速 · \(hostCount) 个节点" : "CDN 加速")
        case .acceleratedPartiallyDirect:
            return ("bolt.fill", "多 CDN 加速 · 部分直连")
        case .fellBackToDirect:
            return ("bolt.slash.fill", "加速不可用 · 已直连")
        case let .live(description):
            return ("dot.radiowaves.left.and.right", description)
        }
    }

    private static func format(speed bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1024 / 1024)
        }
        return String(format: "%.0f KB/s", bytesPerSecond / 1024)
    }

    private static func format(duration seconds: Double) -> String {
        let total = Int(seconds)
        if total >= 60 {
            return "\(total / 60) 分 \(total % 60) 秒"
        }
        return "\(total) 秒"
    }
}
