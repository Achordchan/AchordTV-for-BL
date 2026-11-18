//
//  AutoplayTransitionCardView.swift
//  BilibiliLive
//
//  自动连播切换到下一条时，左上角浮出的过渡卡片：「下一集 / 为你推荐」+ 封面 + 标题。
//  只做提示，不拦截焦点、不影响加载；起播后几秒自动淡出。
//

import Kingfisher
import SnapKit
import UIKit

/// 一次自动连播切换的展示信息
struct AutoplayTransition: Equatable {
    enum Kind: Equatable {
        /// 番剧 / 影视的下一集
        case nextEpisode
        /// 同一视频的下一个分 P
        case nextPart
        /// UGC 合集里的下一个视频
        case nextInCollection
        /// 循环播放：序列播完回到第一条
        case restart
        /// 序列播完后接相关推荐
        case recommended
    }

    var kind: Kind
    var title: String?
    var subtitle: String?
    var coverURL: URL?
}

extension AutoplayTransition.Kind {
    var badgeTitle: String {
        switch self {
        case .nextEpisode: return "下一集"
        case .nextPart: return "下一 P"
        case .nextInCollection: return "合集下一个"
        case .restart: return "从头循环"
        case .recommended: return "为你推荐"
        }
    }

    var badgeIcon: String {
        switch self {
        case .nextEpisode, .nextPart: return "forward.end.fill"
        case .nextInCollection: return "rectangle.stack.fill"
        case .restart: return "repeat"
        case .recommended: return "sparkles"
        }
    }

    /// 续播（同一系列）用粉色，推荐（换到别的视频）用蓝色，一眼区分
    var badgeColor: UIColor {
        switch self {
        case .recommended:
            return UIColor(red: 0.0, green: 0.55, blue: 0.82, alpha: 1)
        case .nextEpisode, .nextPart, .nextInCollection, .restart:
            return UIColor(red: 0.90, green: 0.32, blue: 0.50, alpha: 1)
        }
    }
}

final class AutoplayTransitionCardView: UIView {
    enum Phase {
        /// 上一条已播完，下一条正在加载
        case upcoming
        /// 下一条已开始播放
        case playing
    }

    static let coverSize = CGSize(width: 224, height: 126)

    private let backgroundView = BLGlass.makeVideoOverlayView(cornerRadius: 28)
    private let coverView = UIImageView()
    private let coverPlaceholder = UIImageView(image: UIImage(systemName: "play.rectangle.fill"))
    private let badgeView = UIView()
    private let badgeIconView = UIImageView()
    private let badgeLabel = UILabel()
    private let phaseLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var currentCoverURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(backgroundView)
        backgroundView.snp.makeConstraints { $0.edges.equalToSuperview() }
        // 内容放在普通容器里（不放进 effect view 的 contentView），卡片高度才能由封面和文字共同撑开
        let content = UIView()
        addSubview(content)
        content.snp.makeConstraints { $0.edges.equalToSuperview() }

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 14
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = UIColor(white: 1, alpha: 0.08)
        content.addSubview(coverView)
        coverView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(18)
            make.top.greaterThanOrEqualToSuperview().inset(18)
            make.bottom.lessThanOrEqualToSuperview().inset(18)
            make.bottom.equalToSuperview().inset(18).priority(.low)
            make.centerY.equalToSuperview()
            make.size.equalTo(Self.coverSize)
        }
        coverPlaceholder.tintColor = UIColor(white: 1, alpha: 0.35)
        coverPlaceholder.contentMode = .scaleAspectFit
        coverPlaceholder.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        coverView.addSubview(coverPlaceholder)
        coverPlaceholder.snp.makeConstraints { $0.center.equalToSuperview() }

        // 类型标签：彩色 Chip（图标 + 文字）
        badgeView.layer.cornerRadius = 17
        badgeView.layer.cornerCurve = .continuous
        badgeIconView.tintColor = .white
        badgeIconView.contentMode = .scaleAspectFit
        badgeIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        badgeLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        badgeLabel.textColor = .white
        let badgeStack = UIStackView(arrangedSubviews: [badgeIconView, badgeLabel])
        badgeStack.spacing = 6
        badgeStack.alignment = .center
        badgeView.addSubview(badgeStack)
        badgeStack.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(14)
            make.centerY.equalToSuperview()
        }
        badgeView.snp.makeConstraints { $0.height.equalTo(34) }

        phaseLabel.font = BLFont.caption
        phaseLabel.textColor = BLGlass.Color.secondaryText

        let headerRow = UIStackView(arrangedSubviews: [badgeView, phaseLabel])
        headerRow.spacing = 12
        headerRow.alignment = .center

        titleLabel.font = BLFont.cardTitleLarge
        titleLabel.textColor = BLGlass.Color.text
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = BLFont.caption
        subtitleLabel.textColor = BLGlass.Color.secondaryText
        subtitleLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [headerRow, titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 8
        textStack.setCustomSpacing(12, after: headerRow)
        content.addSubview(textStack)
        textStack.snp.makeConstraints { make in
            make.leading.equalTo(coverView.snp.trailing).offset(20)
            make.trailing.equalToSuperview().inset(24)
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().inset(18)
            make.bottom.lessThanOrEqualToSuperview().inset(18)
            make.bottom.equalToSuperview().inset(18).priority(.low)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ transition: AutoplayTransition) {
        let kind = transition.kind
        badgeView.backgroundColor = kind.badgeColor
        badgeIconView.image = UIImage(systemName: kind.badgeIcon)
        badgeLabel.text = kind.badgeTitle

        let title = transition.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = (title?.isEmpty == false) ? title : "下一个视频"
        let subtitle = transition.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty ?? true

        setCover(transition.coverURL)
    }

    func setPhase(_ phase: Phase) {
        switch phase {
        case .upcoming: phaseLabel.text = "即将播放"
        case .playing: phaseLabel.text = "正在播放"
        }
    }

    private func setCover(_ url: URL?) {
        guard url != currentCoverURL else { return }
        currentCoverURL = url
        coverView.kf.cancelDownloadTask()
        guard let url else {
            coverView.image = nil
            coverPlaceholder.isHidden = false
            return
        }
        coverPlaceholder.isHidden = false
        let size = CGSize(width: Self.coverSize.width * 2, height: Self.coverSize.height * 2)
        coverView.kf.setImage(with: url,
                              options: [.processor(DownsamplingImageProcessor(size: size)),
                                        .cacheOriginalImage,
                                        .transition(.fade(0.2))])
        { [weak self] result in
            if case .success = result {
                self?.coverPlaceholder.isHidden = true
            }
        }
    }
}

/// 管理过渡卡片的出现与淡出：切换发起时立即显示（与加载并行，不延迟起播），
/// 起播后再停留几秒淡出；迟迟没起播时最多停留 `maxWaitingDuration` 秒。
@MainActor
final class AutoplayTransitionPresenter {
    static let visibleDurationAfterStart: TimeInterval = 4
    static let maxWaitingDuration: TimeInterval = 20

    private weak var hostView: UIView?
    private var card: AutoplayTransitionCardView?
    private var isPlaying = false
    private var hideWorkItem: DispatchWorkItem?

    init(hostView: UIView) {
        self.hostView = hostView
    }

    func show(_ transition: AutoplayTransition, isUpdate: Bool) {
        if let card {
            card.configure(transition)
            if !isUpdate {
                // 又切了一次（例如推荐加载失败改播下一个）：回到「即将播放」
                isPlaying = false
                card.setPhase(.upcoming)
                scheduleHide(after: Self.maxWaitingDuration)
            }
            return
        }
        // 卡片已经淡出后才到的补全信息不再重新弹出
        guard !isUpdate, let hostView else { return }

        let card = AutoplayTransitionCardView()
        card.configure(transition)
        card.setPhase(.upcoming)
        hostView.addSubview(card)
        card.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(80)
            make.top.equalToSuperview().inset(60)
            make.width.equalTo(640)
        }
        self.card = card
        isPlaying = false
        card.alpha = 0
        card.transform = CGAffineTransform(translationX: -48, y: 0)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
            card.alpha = 1
            card.transform = .identity
        }
        scheduleHide(after: Self.maxWaitingDuration)
    }

    /// 新视频开始播放
    func markPlaying() {
        guard let card, !isPlaying else { return }
        isPlaying = true
        card.setPhase(.playing)
        scheduleHide(after: Self.visibleDurationAfterStart)
    }

    func hide(animated: Bool) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        guard let card else { return }
        self.card = nil
        isPlaying = false
        guard animated else {
            card.removeFromSuperview()
            return
        }
        UIView.animate(withDuration: 0.5, animations: {
            card.alpha = 0
            card.transform = CGAffineTransform(translationX: -24, y: 0)
        }, completion: { _ in
            card.removeFromSuperview()
        })
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hide(animated: true)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
