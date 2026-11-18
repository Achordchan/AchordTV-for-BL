//
//  VideoPlayerViewController.swift
//  BilibiliLive
//
//  Created by yicheng on 2024/5/23.
//

import AVKit
import Combine
import UIKit

struct PlayInfo: Hashable {
    var aid: Int
    var cid: Int? = 0
    var epid: Int? = 0 // 港澳台解锁需要
    var seasonId: Int? = 0 // 番剧 season_id
    var ctime: Int? = 0
    var subType: Int? = nil // 0: 普通视频 1：番剧 2：电影 3：纪录片 4：国创 5：电视剧 7：综艺
    var lastPlayCid: Int?
    var playTimeInSecond: Int?
    var title: String?
    var ownerName: String?
    var coverURL: URL?

    var isCidVaild: Bool {
        return cid ?? 0 > 0
    }

    var isBangumi: Bool {
        return epid ?? 0 > 0 || seasonId ?? 0 > 0
    }

    var sequenceKey: String {
        "\(aid)-\(cid ?? 0)-\(epid ?? 0)-\(seasonId ?? 0)"
    }

    var contentIdentity: String {
        if let epid, epid > 0 { return "epid-\(epid)" }
        if let seasonId, seasonId > 0 { return "season-\(seasonId)" }
        return "aid-\(aid)"
    }

    var contextKey: PlayContextKey {
        PlayContextKey(aid: aid,
                       cid: cid ?? 0,
                       epid: epid ?? 0,
                       seasonId: seasonId ?? 0)
    }
}

enum VideoPlayerMode {
    case regular
    case preview
    case feedFlow
}

@MainActor
final class VideoSequenceProvider {
    private(set) var playSeq: [PlayInfo]
    private(set) var currentIndex: Int
    private(set) var temporaryOverrides = [PlayInfo]()
    private let preloadThreshold: Int
    var onNeedMore: (() async -> Void)?

    init(seq: [PlayInfo], currentIndex: Int = 0, preloadThreshold: Int = 8) {
        playSeq = seq.uniqued()
        self.currentIndex = max(0, min(currentIndex, max(playSeq.count - 1, 0)))
        self.preloadThreshold = preloadThreshold
    }

    var count: Int {
        playSeq.count
    }

    var hasPrevious: Bool {
        currentIndex > 0
    }

    var hasNext: Bool {
        currentIndex + 1 < playSeq.count
    }

    func current() -> PlayInfo? {
        if let temporary = temporaryOverrides.last {
            return temporary
        }
        guard playSeq.indices.contains(currentIndex) else { return nil }
        return playSeq[currentIndex]
    }

    func setCurrentIndex(_ index: Int) {
        guard playSeq.indices.contains(index) else { return }
        clearTemporaryOverrides()
        currentIndex = index
    }

    func reset() {
        clearTemporaryOverrides()
        currentIndex = 0
    }

    func append(_ seq: [PlayInfo]) {
        var existing = Set(playSeq.map(\.sequenceKey))
        let newItems = seq.filter { existing.insert($0.sequenceKey).inserted }
        playSeq.append(contentsOf: newItems)
    }

    func peekPrevious() -> PlayInfo? {
        guard hasPrevious else { return nil }
        return playSeq[currentIndex - 1]
    }

    func peekNext() -> PlayInfo? {
        guard hasNext else { return nil }
        return playSeq[currentIndex + 1]
    }

    func neighborItems(radius: Int) -> [PlayInfo] {
        guard !playSeq.isEmpty else { return temporaryOverrides.uniqued() }
        let lower = max(0, currentIndex - radius)
        let upper = min(playSeq.count - 1, currentIndex + radius)
        return ([current()].compactMap { $0 } + Array(playSeq[lower...upper])).uniqued()
    }

    func pushTemporary(_ playInfo: PlayInfo) {
        temporaryOverrides.append(playInfo)
    }

    func clearTemporaryOverrides() {
        temporaryOverrides.removeAll()
    }

    func movePrevious() -> PlayInfo? {
        guard hasPrevious else { return nil }
        clearTemporaryOverrides()
        currentIndex -= 1
        return playSeq[currentIndex]
    }

    func moveNext() async -> PlayInfo? {
        await prefetchMoreIfNeeded()
        guard hasNext else { return nil }
        clearTemporaryOverrides()
        currentIndex += 1
        await prefetchMoreIfNeeded()
        return playSeq[currentIndex]
    }

    func prefetchMoreIfNeeded() async {
        guard count - currentIndex - 1 < preloadThreshold else { return }
        await onNeedMore?()
    }

    /// 序列走到合集里的一个多 P 视频时，把这一条替换成它的各个分 P。
    /// 该 aid 在序列里已经不止一条（已展开过）或正在播临时插入的视频时不处理。
    func expandCurrent(into pages: [PlayInfo], currentCid: Int) {
        guard temporaryOverrides.isEmpty,
              pages.count > 1,
              playSeq.indices.contains(currentIndex)
        else { return }
        let aid = playSeq[currentIndex].aid
        guard pages.allSatisfy({ $0.aid == aid }),
              playSeq.filter({ $0.aid == aid }).count == 1
        else { return }
        let existingKeys = Set(playSeq.map(\.sequenceKey))
        let newPages = pages.filter { !existingKeys.contains($0.sequenceKey) || $0.cid == playSeq[currentIndex].cid }
        guard newPages.count > 1 else { return }
        playSeq.replaceSubrange(currentIndex...currentIndex, with: newPages)
        currentIndex += newPages.firstIndex(where: { $0.cid == currentCid }) ?? 0
    }

    /// 回到序列第一条（循环播放用），返回第一条
    func restart() -> PlayInfo? {
        clearTemporaryOverrides()
        currentIndex = 0
        return playSeq.first
    }
}

extension VideoSequenceProvider {
    /// 用普通视频详情构建续播序列：UGC 合集优先（当前这一集若有多 P 则展开），否则用分 P。
    /// 只有一条可播内容时返回 nil。
    nonisolated static func makeSequence(detail: VideoDetail, aid: Int, cid: Int) -> (seq: [PlayInfo], index: Int)? {
        let pages = detail.View.aid == aid ? (detail.View.pages ?? []) : []
        let pageInfos = pages.map { PlayInfo(aid: aid, cid: $0.cid, title: $0.part, coverURL: detail.pic) }

        var episodes = [VideoDetail.Info.UgcSeason.UgcVideoInfo]()
        if let season = detail.View.ugc_season {
            if season.sections.count > 1 {
                episodes = season.sections.first(where: { $0.episodes.contains(where: { $0.aid == aid }) })?.episodes ?? []
            } else {
                episodes = season.sections.first?.episodes ?? []
            }
            episodes.sort { $0.arc.ctime < $1.arc.ctime }
        }

        var seq = [PlayInfo]()
        if episodes.contains(where: { $0.aid == aid }) {
            for episode in episodes {
                if episode.aid == aid, pageInfos.count > 1 {
                    seq.append(contentsOf: pageInfos)
                } else {
                    seq.append(PlayInfo(aid: episode.aid, cid: episode.cid, title: episode.title, coverURL: episode.arc.pic))
                }
            }
        } else {
            seq = pageInfos
        }
        guard seq.count > 1 else { return nil }
        let index = seq.firstIndex(where: { $0.aid == aid && $0.cid == cid })
            ?? seq.firstIndex(where: { $0.aid == aid })
            ?? 0
        return (seq, index)
    }

    /// 用番剧信息构建正片序列
    nonisolated static func makeSequence(bangumi: BangumiInfo, current: PlayInfo) -> (seq: [PlayInfo], index: Int)? {
        let seq = bangumi.episodes.map {
            PlayInfo(aid: $0.aid,
                     cid: $0.cid,
                     epid: $0.id,
                     seasonId: bangumi.season_id,
                     subType: current.subType ?? bangumi.type,
                     title: [$0.title, $0.long_title].filter { !$0.isEmpty }.joined(separator: " "),
                     coverURL: $0.cover)
        }
        guard seq.count > 1 else { return nil }
        let index = seq.firstIndex(where: { ($0.epid ?? 0) > 0 && $0.epid == current.epid })
            ?? seq.firstIndex(where: { $0.cid == current.cid })
        guard let index else { return nil }
        return (seq, index)
    }
}

class VideoPlayerViewController: CommonPlayerViewController {
    enum AutoTriggeredInfoAction: String {
        case previous
        case next

        init?(title: String) {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedTitle.contains("上一条") {
                self = .previous
            } else if trimmedTitle.contains("下一条") {
                self = .next
            } else {
                return nil
            }
        }
    }

    var data: VideoDetail? {
        didSet { viewModel.useInitialVideoDetail(data) }
    }

    var sequenceProvider: VideoSequenceProvider?
    var onLoadFailure: ((String) -> Void)?
    var onPlaybackStarted: (() -> Void)?
    var onPlayInfoChanged: ((PlayInfo) -> Void)?
    var onDismissWithPlayInfo: ((PlayInfo) -> Void)?

    private let playMode: VideoPlayerMode
    private let playContextCache: PlayContextCache?
    private let mediaWarmupManager: PlayerMediaWarmupManager?
    private let previewMuted: Bool
    private let viewModel: VideoPlayerViewModel
    private var cancelable = Set<AnyCancellable>()
    private var neighborPreloadTask: Task<Void, Never>?
    private var currentRetryKey: String
    private var hasRetriedCurrentItem = false
    private var isStopping = false
    private var pendingAutoTriggeredInfoActionKey: String?
    /// 自动连播的过渡卡片（只在切换期间存在）
    private var transitionCard: AutoplayTransitionCardView?
    private var transitionCardIsPlaying = false
    private var transitionHideWorkItem: DispatchWorkItem?

    init(playInfo: PlayInfo,
         playMode: VideoPlayerMode = .regular,
         playContextCache: PlayContextCache? = nil,
         mediaWarmupManager: PlayerMediaWarmupManager? = nil,
         previewMuted: Bool = true,
         startTimeOverride: Int? = nil)
    {
        self.playMode = playMode
        self.playContextCache = playContextCache
        self.mediaWarmupManager = mediaWarmupManager
        self.previewMuted = previewMuted
        viewModel = VideoPlayerViewModel(playInfo: playInfo,
                                         playMode: playMode,
                                         playContextCache: playContextCache,
                                         mediaWarmupManager: mediaWarmupManager,
                                         previewMuted: previewMuted,
                                         startTimeOverride: startTimeOverride)
        currentRetryKey = playInfo.sequenceKey
        super.init(nibName: nil, bundle: nil)
        if playMode == .preview {
            showsPlaybackControls = false
            allowsPictureInPicturePlayback = false
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var currentPlayInfo: PlayInfo {
        viewModel.currentPlayInfo
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.sequenceProvider = sequenceProvider
        viewModel.onPlayInfoChanged = { [weak self] info in
            self?.handlePlayInfoChanged(info)
        }
        viewModel.onShowDetail = { [weak self] info in
            self?.showDetail(for: info)
        }
        viewModel.onAutoplayTransition = { [weak self] transition, isUpdate in
            self?.showAutoplayTransition(transition, isUpdate: isUpdate)
        }
        viewModel.loadResult.receive(on: DispatchQueue.main).sink { [weak self] result in
            switch result {
            case let .failure(err):
                self?.handleLoadFailure(message: err)
            case let .success(plugins):
                self?.neighborPreloadTask?.cancel()
                self?.removeAllPlugins()
                plugins.forEach { self?.addPlugin(plugin: $0) }
                self?.neighborPreloadTask = Task { [weak self] in
                    await self?.viewModel.preloadNeighborsIfNeeded()
                }
            }
        }.store(in: &cancelable)

        if playMode == .regular {
            viewModel.onExit = { [weak self] in
                self?.dismiss(animated: true)
            }
        }

        if playMode == .feedFlow {
            // 添加双击上方向键切回上一条视频的全局手势拦截 (作为面板“上一条”被折叠的补偿方案)
            let doubleUpTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleUpTap))
            doubleUpTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.upArrow.rawValue)]
            doubleUpTap.numberOfTapsRequired = 2
            view.addGestureRecognizer(doubleUpTap)

            let doubleDownTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleDownTap))
            doubleDownTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.downArrow.rawValue)]
            doubleDownTap.numberOfTapsRequired = 2
            view.addGestureRecognizer(doubleDownTap)

            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(handleInfoActionFocusedNotification(_:)),
                                                   name: UICollectionViewCell.infoActionFocusedNotification,
                                                   object: nil)
            if #available(tvOS 11.0, *) {
                NotificationCenter.default.addObserver(self,
                                                       selector: #selector(handleSystemFocusUpdate(_:)),
                                                       name: UIFocusSystem.didUpdateNotification,
                                                       object: nil)
            }
        }

        viewModel.load()
    }

    override func viewDidDisappear(_ animated: Bool) {
        let isExiting = isBeingDismissed || isMovingFromParent || navigationController?.isBeingDismissed == true
        let dismissPlayInfo = playMode == .feedFlow ? viewModel.currentPlayInfo : nil
        super.viewDidDisappear(animated)
        guard isExiting else { return }
        if playMode == .feedFlow {
            if let dismissPlayInfo {
                onDismissWithPlayInfo?(dismissPlayInfo)
            }
        }
        stopAsyncWork()
    }

    override func stopPlayback() {
        stopAsyncWork()
        super.stopPlayback()
    }

    override func playerDidStart(player: AVPlayer) {
        markAutoplayTransitionPlaying()
        switch playMode {
        case .preview:
            onPlaybackStarted?()
        case .feedFlow, .regular:
            break
        }
    }

    override func playerDidStall(player: AVPlayer) {
        guard playMode == .feedFlow else { return }
        attemptRetryOrShowRecovery(message: "播放卡住了，请选择重试或切换下一条。")
    }

    override func playerDidFail(player: AVPlayer) {
        guard playMode == .feedFlow else {
            super.playerDidFail(player: player)
            return
        }
        attemptRetryOrShowRecovery(message: "当前视频加载失败，请选择重试或切换下一条。")
    }

    private func handlePlayInfoChanged(_ info: PlayInfo) {
        neighborPreloadTask?.cancel()
        neighborPreloadTask = nil
        if currentRetryKey != info.sequenceKey {
            currentRetryKey = info.sequenceKey
            hasRetriedCurrentItem = false
        }
        pendingAutoTriggeredInfoActionKey = nil
        onPlayInfoChanged?(info)
    }

    private func stopAsyncWork() {
        guard !isStopping else { return }
        isStopping = true
        hideAutoplayTransition(animated: false)
        neighborPreloadTask?.cancel()
        neighborPreloadTask = nil
        viewModel.cancelLoading()
        cancelable.removeAll()
        Task { [mediaWarmupManager] in
            await mediaWarmupManager?.cancelAll()
        }
    }

    private func handleLoadFailure(message: String) {
        hideAutoplayTransition(animated: false)
        switch playMode {
        case .preview:
            onLoadFailure?(message)
        case .feedFlow:
            attemptRetryOrShowRecovery(message: message)
        case .regular:
            showErrorAlertAndExit(message: message)
        }
    }

    private func attemptRetryOrShowRecovery(message: String) {
        guard !hasRetriedCurrentItem else {
            showFeedFlowRecoveryAlert(message: message)
            return
        }
        hasRetriedCurrentItem = true
        viewModel.retryCurrent()
    }

    private func showFeedFlowRecoveryAlert(message: String) {
        let alert = UIAlertController(title: "播放异常", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in
            self?.hasRetriedCurrentItem = true
            self?.viewModel.retryCurrent()
        })
        alert.addAction(UIAlertAction(title: "下一条", style: .default) { [weak self] _ in
            Task { [weak self] in
                if await self?.viewModel.playNextFromSequence() == false {
                    self?.dismiss(animated: true)
                }
            }
        })
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - 自动连播过渡卡片

    /// 卡片在发起切换的同一时刻显示，和加载并行，不延迟起播。
    /// 起播后再停留几秒淡出；迟迟没起播时最多停留 `maxWaitingDuration` 秒。
    private static let visibleDurationAfterStart: TimeInterval = 4
    private static let maxWaitingDuration: TimeInterval = 20

    private func showAutoplayTransition(_ transition: AutoplayTransition, isUpdate: Bool) {
        if let card = transitionCard {
            card.configure(transition)
            if !isUpdate {
                // 又切了一次（例如推荐加载失败改播下一个）：回到「即将播放」
                transitionCardIsPlaying = false
                card.setPhase(.upcoming)
                scheduleAutoplayTransitionHide(after: Self.maxWaitingDuration)
            }
            return
        }
        // 卡片已经淡出后才到的补全信息不再重新弹出
        guard !isUpdate else { return }

        let card = AutoplayTransitionCardView()
        card.configure(transition)
        card.setPhase(.upcoming)
        view.addSubview(card)
        card.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(80)
            make.top.equalToSuperview().inset(60)
            make.width.equalTo(640)
        }
        transitionCard = card
        transitionCardIsPlaying = false
        card.alpha = 0
        card.transform = CGAffineTransform(translationX: -48, y: 0)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
            card.alpha = 1
            card.transform = .identity
        }
        scheduleAutoplayTransitionHide(after: Self.maxWaitingDuration)
    }

    private func markAutoplayTransitionPlaying() {
        guard let card = transitionCard, !transitionCardIsPlaying else { return }
        transitionCardIsPlaying = true
        card.setPhase(.playing)
        scheduleAutoplayTransitionHide(after: Self.visibleDurationAfterStart)
    }

    private func scheduleAutoplayTransitionHide(after delay: TimeInterval) {
        transitionHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hideAutoplayTransition(animated: true)
        }
        transitionHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func hideAutoplayTransition(animated: Bool) {
        transitionHideWorkItem?.cancel()
        transitionHideWorkItem = nil
        guard let card = transitionCard else { return }
        transitionCard = nil
        transitionCardIsPlaying = false
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

    private func showDetail(for info: PlayInfo) {
        guard playMode != .preview else { return }
        let detailVC: VideoDetailViewController
        if let seasonId = info.seasonId, seasonId > 0 {
            detailVC = VideoDetailViewController.create(seasonId: seasonId)
        } else {
            detailVC = VideoDetailViewController.create(aid: info.aid, cid: info.cid, epid: info.epid)
        }
        detailVC.present(from: self, direatlyEnterVideo: false)
    }

    @objc private func handleDoubleUpTap() {
        guard playMode == .feedFlow else { return }
        Logger.debug("[FeedFlow] 捕获双击上键，准备切换至上一条")
        Task { [weak self] in
            guard let self else { return }
            _ = await self.viewModel.playPreviousFromSequence()
        }
    }

    @objc private func handleDoubleDownTap() {
        guard playMode == .feedFlow else { return }
        Logger.debug("[FeedFlow] 捕获双击下键，准备切换至下一条")
        Task { [weak self] in
            guard let self else { return }
            _ = await self.viewModel.playNextFromSequence()
        }
    }

    @available(tvOS 11.0, *)
    @objc private func handleSystemFocusUpdate(_ note: Notification) {
        guard playMode == .feedFlow,
              let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext,
              let nextView = context.nextFocusedView
        else { return }

        installAVInfoPanelHookIfNeeded(for: nextView)
        #if DEBUG
            Logger.debug("[FocusDiag] 焦点落在了类: \(type(of: nextView))")
            let dumpResult = dumpViewHierarchy(nextView, depth: 0)
            Logger.debug("[FocusDiag] 子视图结构:\n\(dumpResult)")
        #endif
    }

    #if DEBUG
        private func dumpViewHierarchy(_ view: UIView, depth: Int) -> String {
            guard depth < 6 else { return "" }
            let indent = String(repeating: "  ", count: depth)
            var result = "\(indent)- \(type(of: view))"
            if let label = view as? UILabel {
                result += " text: '\(label.text ?? "")' attr: '\(label.attributedText?.string ?? "")'"
            } else if let btn = view as? UIButton {
                result += " title: '\(btn.title(for: .normal) ?? "")'"
            }
            result += "\n"
            for subview in view.subviews {
                result += dumpViewHierarchy(subview, depth: depth + 1)
            }
            return result
        }
    #endif

    private func installAVInfoPanelHookIfNeeded(for view: UIView) {
        guard containsAVInfoPanelHierarchy(from: view) else { return }
        guard AVInfoPanelCollectionViewThumbnailCellHook.start(),
              let title = extractInfoActionTitle(from: view)
        else { return }
        handleFocusedInfoAction(title: title)
    }

    private func containsAVInfoPanelHierarchy(from view: UIView) -> Bool {
        var currentView: UIView? = view
        var remainingDepth = 8

        while let ancestorView = currentView, remainingDepth > 0 {
            if NSStringFromClass(type(of: ancestorView)).contains("AVInfoPanel") {
                return true
            }
            remainingDepth -= 1
            currentView = ancestorView.superview
        }

        return false
    }

    private func extractInfoActionTitle(from view: UIView) -> String? {
        var currentView: UIView? = view
        var remainingDepth = 8

        while let candidate = currentView, remainingDepth > 0 {
            if let title = matchingInfoActionTitle(in: candidate, maxDepth: 0) {
                return title
            }
            let isActionContainer = candidate is UICollectionViewCell ||
                NSStringFromClass(type(of: candidate)).contains("AVInfoPanel")
            if isActionContainer,
               let title = matchingInfoActionTitle(in: candidate, maxDepth: 4)
            {
                return title
            }
            remainingDepth -= 1
            currentView = candidate.superview
        }
        return nil
    }

    private func matchingInfoActionTitle(in view: UIView, maxDepth: Int) -> String? {
        let titles: [String?]
        if let label = view as? UILabel {
            titles = [label.text, label.attributedText?.string, label.accessibilityLabel]
        } else if let button = view as? UIButton {
            titles = [button.title(for: .focused), button.title(for: .normal), button.accessibilityLabel]
        } else {
            titles = [view.accessibilityLabel]
        }
        if let title = titles.compactMap({ $0 }).first(where: { AutoTriggeredInfoAction(title: $0) != nil }) {
            return title
        }
        guard maxDepth > 0 else { return nil }
        for subview in view.subviews {
            if let title = matchingInfoActionTitle(in: subview, maxDepth: maxDepth - 1) {
                return title
            }
        }
        return nil
    }

    @objc private func handleInfoActionFocusedNotification(_ note: Notification) {
        guard let title = note.userInfo?["title"] as? String else { return }
        handleFocusedInfoAction(title: title)
    }

    private func handleFocusedInfoAction(title: String) {
        guard playMode == .feedFlow,
              let action = AutoTriggeredInfoAction(title: title)
        else { return }

        let actionKey = "\(currentPlayInfo.sequenceKey)::\(action.rawValue)"
        guard pendingAutoTriggeredInfoActionKey != actionKey else { return }
        pendingAutoTriggeredInfoActionKey = actionKey

        Task { [weak self] in
            guard let self else { return }
            let didTrigger: Bool
            switch action {
            case .previous:
                didTrigger = await self.viewModel.playPreviousFromSequence()
            case .next:
                didTrigger = await self.viewModel.playNextFromSequence()
            }
            if !didTrigger, self.pendingAutoTriggeredInfoActionKey == actionKey {
                self.pendingAutoTriggeredInfoActionKey = nil
            }
        }
    }
}
