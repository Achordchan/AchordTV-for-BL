//
//  VideoPlayerViewModel.swift
//  BilibiliLive
//
//  Created by yicheng on 2024/5/23.
//

import AVFoundation
import Combine
import UIKit

struct PlayerDetailData {
    let aid: Int
    let cid: Int
    let epid: Int? // 港澳台解锁需要
    let seasonId: Int? // 番剧 season_id
    let subType: Int? // 0: 普通视频 1：番剧 2：电影 3：纪录片 4：国创 5：电视剧 7：综艺

    var playerStartPos: Int?
    var detail: VideoDetail?
    var clips: [VideoPlayURLInfo.ClipInfo]?
    var playerInfo: PlayerInfo?
    var videoPlayURLInfo: VideoPlayURLInfo

    var isBangumi: Bool {
        return epid ?? 0 > 0 || seasonId ?? 0 > 0
    }
}

@MainActor
class VideoPlayerViewModel {
    let loadResult = PassthroughSubject<Result<[CommonPlayerPlugin], String>, Never>()
    var onExit: (() -> Void)?
    var onPlayInfoChanged: ((PlayInfo) -> Void)?
    var onShowDetail: ((PlayInfo) -> Void)?
    /// 自动连播切到下一条时通知界面显示过渡卡片；第二个参数为 true 表示加载完成后补全的信息（只更新已显示的卡片）
    var onAutoplayTransition: ((AutoplayTransition, _ isUpdate: Bool) -> Void)?
    var sequenceProvider: VideoSequenceProvider?

    private var playInfo: PlayInfo
    private let playMode: VideoPlayerMode
    private let playContextCache: PlayContextCache?
    private let mediaWarmupManager: PlayerMediaWarmupManager?
    private let previewMuted: Bool
    private let startTimeOverride: Int?
    private let startTimeOverrideContentIdentity: String
    private var videoDetail: VideoDetail?
    private var cancellable = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?
    private var danmuLoadTask: Task<Void, Never>?
    private var loadGeneration = 0
    /// 本次播放会话里已经播过（或尝试过）的 aid，自动播相关推荐时跳过，避免 A↔B 来回
    private var playedAids = Set<Int>()
    /// 自动跳到相关推荐后若加载失败，按顺序改试的后备候选（只对该次加载有效）
    private var relatedFallbacks = [PlayInfo]()
    private var relatedFallbackGeneration: Int?
    /// 已显示、等待加载完成后补全封面 / 标题的过渡卡片信息
    private var pendingTransition: (generation: Int, transition: AutoplayTransition)?

    init(playInfo: PlayInfo,
         playMode: VideoPlayerMode = .regular,
         playContextCache: PlayContextCache? = nil,
         mediaWarmupManager: PlayerMediaWarmupManager? = nil,
         previewMuted: Bool = true,
         startTimeOverride: Int? = nil)
    {
        self.playInfo = playInfo
        self.playMode = playMode
        self.playContextCache = playContextCache
        self.mediaWarmupManager = mediaWarmupManager
        self.previewMuted = previewMuted
        self.startTimeOverride = startTimeOverride
        startTimeOverrideContentIdentity = playInfo.contentIdentity
    }

    var currentPlayInfo: PlayInfo {
        playInfo
    }

    func useInitialVideoDetail(_ detail: VideoDetail?) {
        guard loadTask == nil, detail?.View.aid == playInfo.aid else { return }
        videoDetail = detail
    }

    func load() {
        startLoad(for: playInfo)
    }

    func cancelLoading() {
        danmuLoadTask?.cancel()
        danmuLoadTask = nil
        loadTask?.cancel()
        loadTask = nil
        loadGeneration += 1
    }

    private func startLoad(for requestedPlayInfo: PlayInfo) {
        danmuLoadTask?.cancel()
        danmuLoadTask = nil
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await performLoad(for: requestedPlayInfo, generation: generation)
        }
        loadTask = task
    }

    private func performLoad(for requestedPlayInfo: PlayInfo, generation: Int) async {
        defer {
            if loadGeneration == generation {
                loadTask = nil
            }
        }
        do {
            let (resolvedPlayInfo, data) = try await loadVideoInfo(for: requestedPlayInfo)
            guard !Task.isCancelled, loadGeneration == generation else { return }

            let danmuProvider = VideoDanmuProvider(enableDanmuFilter: Settings.enableDanmuFilter,
                                                   enableDanmuRemoveDup: Settings.enableDanmuRemoveDup)
            // Previews do not install a danmaku plugin. For other modes, install
            // an initialized provider without blocking media setup on its requests.
            if playMode != .preview {
                let startPos = data.playerStartPos ?? 0
                danmuProvider.prepareVideo(cid: data.cid, startPos: startPos)
                danmuLoadTask = Task {
                    await danmuProvider.loadInitialDanmu(startPos: startPos)
                }
            }
            // 番剧序列要在生成插件前就位（播放列表插件创建时捕获 provider），这里等它返回
            let bangumiSequence = await loadBangumiSequenceIfNeeded(for: resolvedPlayInfo)
            guard !Task.isCancelled, loadGeneration == generation else { return }

            completePendingTransition(generation: generation, playInfo: resolvedPlayInfo, detail: data.detail)
            playInfo = resolvedPlayInfo
            videoDetail = data.detail
            playedAids.insert(resolvedPlayInfo.aid)
            updateSequence(for: resolvedPlayInfo, data: data, bangumiSequence: bangumiSequence)
            BiliBiliUpnpDMR.shared.sendVideoSwitch(aid: resolvedPlayInfo.aid, cid: data.cid)
            cancellable.removeAll()
            let plugins = generatePlayerPlugin(data,
                                               playInfo: resolvedPlayInfo,
                                               danmuProvider: danmuProvider)
            guard !Task.isCancelled, loadGeneration == generation else { return }
            loadResult.send(.success(plugins))
        } catch is CancellationError {
            return
        } catch let err {
            guard !Task.isCancelled, loadGeneration == generation else { return }
            reportLoadFailure(err.localizedDescription)
        }
    }

    /// 加载失败：若是自动跳到的相关推荐，改试下一个候选；否则照常上报
    private func reportLoadFailure(_ message: String) {
        if relatedFallbackGeneration == loadGeneration, !relatedFallbacks.isEmpty {
            let next = relatedFallbacks.removeFirst()
            Logger.info("[autoplay] 相关推荐加载失败（\(message)），改播 aid \(next.aid)")
            playRelated(next, fallbacks: relatedFallbacks)
            return
        }
        loadResult.send(.failure(message))
    }

    private func loadVideoInfo(for playInfo: PlayInfo) async throws -> (PlayInfo, PlayerDetailData) {
        let resolvedPlayInfo = try await PlayInfoResolver.resolve(playInfo)
        try Task.checkCancellation()
        let data = try await fetchVideoData(for: resolvedPlayInfo)
        try Task.checkCancellation()
        return (resolvedPlayInfo, data)
    }

    private func fetchVideoDetail(aid: Int, existing: VideoDetail?) async -> VideoDetail? {
        if let existing { return existing }
        return try? await WebRequest.requestDetailVideo(aid: aid)
    }

    private func fetchVideoData(for playInfo: PlayInfo) async throws -> PlayerDetailData {
        assert(playInfo.isCidVaild)
        let existingVideoDetail = videoDetail?.View.aid == playInfo.aid ? videoDetail : nil
        if !playInfo.isBangumi, let playContextCache {
            let cached = try await playContextCache.context(for: playInfo, mode: playContextMode)
            let resolvedDetail = cached.detail ?? existingVideoDetail

            var detail = PlayerDetailData(aid: playInfo.aid,
                                          cid: cached.cid,
                                          epid: playInfo.epid,
                                          seasonId: playInfo.seasonId,
                                          subType: playInfo.subType,
                                          detail: resolvedDetail,
                                          clips: nil,
                                          playerInfo: cached.playerInfo,
                                          videoPlayURLInfo: cached.videoPlayURLInfo)

            let lastPlayCid = playInfo.lastPlayCid ?? cached.playerInfo?.last_play_cid ?? 0
            let playTimeInSecond = playInfo.playTimeInSecond ?? cached.playerInfo?.playTimeInSecond ?? 0
            detail.playerStartPos = resolvedPlayerStartPos(cid: cached.cid,
                                                           duration: cached.videoPlayURLInfo.dash.duration,
                                                           lastPlayCid: lastPlayCid,
                                                           playTimeInSecond: playTimeInSecond,
                                                           playInfo: playInfo)
            return detail
        }

        let aid = playInfo.aid
        let cid = playInfo.cid!
        async let infoReq = try? WebRequest.requestPlayerInfo(aid: aid, cid: cid)
        async let detailReq = fetchVideoDetail(aid: aid, existing: existingVideoDetail)
        do {
            let playData: VideoPlayURLInfo
            var clipInfos: [VideoPlayURLInfo.ClipInfo]?

            if playInfo.isBangumi {
                do {
                    playData = try await WebRequest.requestPcgPlayUrl(aid: aid, cid: cid, options: playContextMode.requestOptions)
                } catch let err as RequestError {
                    if case let .statusFail(code, _) = err,
                       code == -404 || code == -10403,
                       let data = try await fetchAreaLimitPcgVideoData(for: playInfo)
                    {
                        playData = data
                    } else {
                        throw err
                    }
                }

                clipInfos = playData.clip_info_list
            } else {
                playData = try await WebRequest.requestPlayUrl(aid: aid, cid: cid, options: playContextMode.requestOptions)
            }

            let info = await infoReq
            let resolvedDetail = await detailReq

            var detail = PlayerDetailData(aid: playInfo.aid, cid: playInfo.cid!, epid: playInfo.epid, seasonId: playInfo.seasonId, subType: playInfo.subType, detail: resolvedDetail, clips: clipInfos, playerInfo: info, videoPlayURLInfo: playData)

            let last_play_cid = playInfo.lastPlayCid ?? info?.last_play_cid ?? 0
            let playTimeInSecond = playInfo.playTimeInSecond ?? info?.playTimeInSecond ?? 0
            detail.playerStartPos = resolvedPlayerStartPos(cid: cid,
                                                           duration: playData.dash.duration,
                                                           lastPlayCid: last_play_cid,
                                                           playTimeInSecond: playTimeInSecond,
                                                           playInfo: playInfo)

            return detail

        } catch let err {
            if case let .statusFail(code, message) = err as? RequestError {
                throw "\(code) \(message)，可能需要大会员"
            } else if await infoReq?.is_upower_exclusive == true {
                throw "该视频为充电专属视频 \(err)"
            } else {
                throw err
            }
        }
    }

    private func updatePlayInfo(_ newPlayInfo: PlayInfo) {
        playInfo = newPlayInfo
        onPlayInfoChanged?(newPlayInfo)
        startLoad(for: newPlayInfo)
    }

    private func resolvedPlayerStartPos(cid: Int,
                                        duration: Int,
                                        lastPlayCid: Int,
                                        playTimeInSecond: Int,
                                        playInfo: PlayInfo) -> Int?
    {
        if let startTimeOverride,
           startTimeOverrideContentIdentity == playInfo.contentIdentity,
           duration - startTimeOverride > 5
        {
            return startTimeOverride
        }
        if lastPlayCid == cid,
           duration - playTimeInSecond > 5,
           Settings.continuePlay
        {
            return playTimeInSecond
        }
        return nil
    }

    func retryCurrent() {
        load()
    }

    // MARK: - 连续播放

    /// 普通播放没有外部传入序列时（例如「不显示详情页直接进入视频」、自动跳到相关推荐），
    /// 番剧需要先拉取剧集列表。其余情况返回 nil，不发请求。
    private func loadBangumiSequenceIfNeeded(for info: PlayInfo) async -> (seq: [PlayInfo], index: Int)? {
        guard playMode == .regular, sequenceProvider == nil, info.isBangumi else { return nil }
        let bangumi: BangumiInfo?
        if let epid = info.epid, epid > 0 {
            bangumi = try? await WebRequest.requestBangumiInfo(epid: epid)
        } else if let seasonId = info.seasonId, seasonId > 0 {
            bangumi = try? await WebRequest.requestBangumiInfo(seasonID: seasonId)
        } else {
            bangumi = nil
        }
        return bangumi.flatMap { VideoSequenceProvider.makeSequence(bangumi: $0, current: info) }
    }

    /// 生成插件前同步整理续播序列（插件创建时会捕获 provider）：
    /// - 没有序列时，按详情自行构建分 P / 合集序列（番剧用上面预先拉到的剧集列表）；
    /// - 已有序列且播到合集里的多 P 视频时，把这一条展开成各个分 P。
    /// 只作用于普通播放，沉浸式 Feed 的序列由 FeedFlowBrowserViewController 按索引管理，不能改动。
    private func updateSequence(for info: PlayInfo, data: PlayerDetailData, bangumiSequence: (seq: [PlayInfo], index: Int)?) {
        guard playMode == .regular else { return }
        if let sequenceProvider {
            guard !info.isBangumi,
                  let detail = data.detail, detail.View.aid == info.aid,
                  let pages = detail.View.pages, pages.count > 1
            else { return }
            sequenceProvider.expandCurrent(into: pages.map { PlayInfo(aid: info.aid, cid: $0.cid, title: $0.part) },
                                           currentCid: data.cid)
            return
        }
        if info.isBangumi {
            if let bangumiSequence {
                sequenceProvider = VideoSequenceProvider(seq: bangumiSequence.seq, currentIndex: bangumiSequence.index)
            }
        } else if let detail = data.detail,
                  let built = VideoSequenceProvider.makeSequence(detail: detail, aid: info.aid, cid: data.cid)
        {
            sequenceProvider = VideoSequenceProvider(seq: built.seq, currentIndex: built.index)
        }
    }

    /// 播放结束后的去向：序列下一条 → 循环 → 相关推荐 → 退出
    private func handlePlaybackEnded(player: AVPlayer) async {
        let autoAdvance = playMode == .feedFlow || Settings.continouslyPlay
        let finished = currentPlayInfo
        let finishedDetail = videoDetail
        if autoAdvance, await playNextFromSequence() {
            announceTransition(Self.sequenceTransitionKind(from: finished, to: currentPlayInfo),
                               to: currentPlayInfo,
                               previousDetail: finishedDetail)
            return
        }

        if Settings.loopPlay {
            if autoAdvance, let provider = sequenceProvider, provider.count > 1,
               let first = provider.restart(),
               first.sequenceKey != currentPlayInfo.sequenceKey
            {
                updatePlayInfo(first)
                announceTransition(.restart, to: first, previousDetail: finishedDetail)
            } else {
                _ = await player.seek(to: .zero)
                player.play()
            }
            return
        }

        // 关掉「连续播放」时，还有下一集就不跳去推荐（开关含义是「没有下一集时」）
        if playMode == .regular, Settings.continouslyPlayRelated, sequenceProvider?.hasNext != true {
            let candidates = relatedCandidates()
            if let next = candidates.first {
                Logger.info("[autoplay] 序列已播完，继续播放相关推荐 aid \(next.aid)")
                playRelated(next, fallbacks: Array(candidates.dropFirst().prefix(2)))
                return
            }
        }

        if playMode == .regular {
            onExit?()
        }
    }

    /// 当前视频详情里的相关推荐，去掉本次已播过的和番剧跳转条目。
    /// 番剧/电影播完不接推荐，与详情页对番剧隐藏推荐区保持一致。
    private func relatedCandidates() -> [PlayInfo] {
        guard !playInfo.isBangumi, let detail = videoDetail, detail.View.aid == playInfo.aid else { return [] }
        var seen = playedAids
        return detail.Related.compactMap { info -> PlayInfo? in
            guard info.aid > 0, info.redirect_url == nil, seen.insert(info.aid).inserted else { return nil }
            return PlayInfo(aid: info.aid,
                            cid: info.cid,
                            title: info.title,
                            ownerName: info.ownerName,
                            coverURL: info.pic)
        }
    }

    private func playRelated(_ info: PlayInfo, fallbacks: [PlayInfo]) {
        playedAids.insert(info.aid)
        // 换到另一个视频：丢掉旧序列，加载后按新视频的分 P / 合集重新构建
        sequenceProvider = nil
        updatePlayInfo(info)
        relatedFallbacks = fallbacks
        relatedFallbackGeneration = loadGeneration
        announceTransition(.recommended, to: info, previousDetail: nil)
    }

    // MARK: - 连播过渡提示

    private static func sequenceTransitionKind(from previous: PlayInfo, to next: PlayInfo) -> AutoplayTransition.Kind {
        if next.isBangumi { return .nextEpisode }
        if next.aid == previous.aid { return .nextPart }
        return .nextInCollection
    }

    /// 切换已经发起（加载照常进行，不等这里）后，用手头已有的信息立即显示过渡卡片。
    /// 只在普通播放里提示；沉浸式 Feed 的上下切换本身就是用户操作。
    private func announceTransition(_ kind: AutoplayTransition.Kind, to info: PlayInfo, previousDetail: VideoDetail?) {
        guard playMode == .regular else { return }
        let sameVideoDetail = previousDetail?.View.aid == info.aid ? previousDetail : nil
        var transition = AutoplayTransition(kind: kind,
                                            title: info.title,
                                            subtitle: info.ownerName,
                                            coverURL: info.coverURL ?? sameVideoDetail?.pic)
        switch kind {
        case .nextPart:
            if let detail = sameVideoDetail {
                transition.title = Self.partTitle(info: info, detail: detail)
                transition.subtitle = detail.title
            }
        case .nextEpisode:
            transition.title = info.title.map(Self.episodeTitle)
        case .nextInCollection, .restart, .recommended:
            break
        }
        pendingTransition = (loadGeneration, transition)
        onAutoplayTransition?(transition, false)
    }

    /// 加载完成：用新视频的详情补全卡片上缺的封面 / 标题 / 副标题
    private func completePendingTransition(generation: Int, playInfo info: PlayInfo, detail: VideoDetail?) {
        guard let pending = pendingTransition, pending.generation == generation else { return }
        pendingTransition = nil
        guard let detail, detail.View.aid == info.aid else { return }
        var transition = pending.transition
        if transition.coverURL == nil {
            transition.coverURL = detail.pic
        }
        if transition.title?.isEmpty ?? true {
            transition.title = transition.kind == .nextPart ? Self.partTitle(info: info, detail: detail) : detail.title
        }
        if transition.subtitle?.isEmpty ?? true {
            switch transition.kind {
            case .nextPart:
                transition.subtitle = detail.title
            case .nextEpisode:
                transition.subtitle = detail.title == transition.title ? nil : detail.title
            case .nextInCollection, .restart, .recommended:
                transition.subtitle = detail.ownerName
            }
        }
        if transition != pending.transition {
            onAutoplayTransition?(transition, true)
        }
    }

    /// 分 P 标题：「P3 · 分 P 名」
    private static func partTitle(info: PlayInfo, detail: VideoDetail) -> String? {
        let pages = detail.View.pages ?? []
        guard let index = pages.firstIndex(where: { $0.cid == info.cid }) else { return info.title }
        let part = pages[index].part
        return part.isEmpty ? "P\(index + 1)" : "P\(index + 1) · \(part)"
    }

    /// 番剧剧集标题以纯数字开头时（如「4 夏日祭」）补成「第4话 夏日祭」
    private static func episodeTitle(_ title: String) -> String {
        let parts = title.split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = parts.first, Int(first) != nil else { return title }
        return (["第\(first)话"] + parts.dropFirst()).joined(separator: " ")
    }

    func playNextFromSequence() async -> Bool {
        guard let next = await sequenceProvider?.moveNext() else { return false }
        updatePlayInfo(next)
        return true
    }

    func playPreviousFromSequence() async -> Bool {
        guard let previous = sequenceProvider?.movePrevious() else { return false }
        updatePlayInfo(previous)
        return true
    }

    func playTemporaryOverride(_ temporaryPlayInfo: PlayInfo) {
        guard temporaryPlayInfo.sequenceKey != currentPlayInfo.sequenceKey else { return }
        sequenceProvider.map { provider in
            MainActor.assumeIsolated {
                provider.pushTemporary(temporaryPlayInfo)
            }
        }
        updatePlayInfo(temporaryPlayInfo)
    }

    func preloadNeighborsIfNeeded() async {
        guard playMode == .feedFlow, let playContextCache, let sequenceProvider else { return }
        let current = sequenceProvider.current() ?? currentPlayInfo
        let priority = [current,
                        sequenceProvider.peekNext(),
                        sequenceProvider.peekPrevious()].compactMap { $0 }.uniqued()
        for info in priority {
            guard !Task.isCancelled else { return }
            await playContextCache.preload(playInfo: info, mode: .regular)
        }
        guard !Task.isCancelled else { return }
        await playContextCache.trim(keeping: priority)
        for info in priority {
            guard !Task.isCancelled else { return }
            await mediaWarmupManager?.preload(playInfo: info)
        }
    }

    private func generatePlayerPlugin(_ data: PlayerDetailData,
                                      playInfo: PlayInfo,
                                      danmuProvider: VideoDanmuProvider) -> [CommonPlayerPlugin]
    {
        let playplugin = BVideoPlayPlugin(playInfo: playInfo,
                                          detailData: data,
                                          reportWatchHistory: playMode != .preview,
                                          minimizeStalling: true,
                                          isMuted: playMode == .preview && previewMuted,
                                          mediaWarmupManager: playMode == .feedFlow ? mediaWarmupManager : nil)
        playplugin.onLoadFailure = { [weak self] message in
            self?.reportLoadFailure(message)
        }

        if playMode == .preview {
            return [playplugin]
        }

        let danmu = DanmuViewPlugin(provider: danmuProvider)
        let upnp = BUpnpPlugin(duration: data.detail?.View.duration)
        let debug = DebugPlugin()
        debug.additionDebugInfo = { [weak playplugin] in
            playplugin?.networkDebugInfo ?? ""
        }
        let playSpeed = SpeedChangerPlugin()
        playSpeed.$currentPlaySpeed.sink { [weak danmu] speed in
            danmu?.danMuView.playingSpeed = speed.value
        }.store(in: &cancellable)

        let playlist = VideoPlayListPlugin(sequenceProvider: sequenceProvider)
        playlist.onPlayerDidStart = { [weak self] in
            // 推荐视频已经开始播放：后备候选只用于「加载失败」，起播后清空，
            // 避免之后切画质失败之类的错误被静默换成下一条推荐
            self?.relatedFallbacks.removeAll()
            self?.relatedFallbackGeneration = nil
        }
        playlist.onPlayerDidEnd = { [weak self] player in
            Task { @MainActor [weak self] in
                await self?.handlePlaybackEnded(player: player)
            }
        }
        playlist.onPlayNextWithInfo = {
            [weak self] info in
            guard let self else { return }
            updatePlayInfo(info)
        }
        playlist.onShowCurrentDetail = { [weak self] info in
            self?.onShowDetail?(info)
        }

        // 底栏按钮的顺序由 PlayerMenu.arrange 统一决定，与插件添加顺序无关
        var plugins: [CommonPlayerPlugin] = [playSpeed, playplugin, danmu, upnp, debug, playlist]

        if !data.isBangumi, let detail = data.detail {
            let infoTabs = VideoPlayerInfoTabsPlugin(detail: detail,
                                                     currentPlayInfo: playInfo,
                                                     sequenceProvider: sequenceProvider)
            infoTabs.onSelectDiscovery = { [weak self] info in
                self?.playTemporaryOverride(info)
            }
            plugins.append(infoTabs)
        }

        // 添加画质选择器插件
        let qualitySelector = BVideoQualityPlugin(detailData: data) { [weak playplugin] qualityId, streamIndex in
            Task { @MainActor in
                await playplugin?.switchQuality(to: qualityId, streamIndex: streamIndex)
            }
        }

        plugins.append(qualitySelector)

        if let clips = data.clips {
            let clip = BVideoClipsPlugin(clipInfos: clips)
            plugins.append(clip)
        }

        if Settings.enableSponsorBlock != .none, let bvid = data.detail?.View.bvid, let duration = data.detail?.View.duration {
            let sponsor = SponsorSkipPlugin(bvid: bvid, duration: duration)
            plugins.append(sponsor)
        }

        if Settings.danmuMask {
            if let mask = data.playerInfo?.dm_mask,
               let video = data.videoPlayURLInfo.dash.video.first,
               mask.fps > 0
            {
                let maskProvider = BMaskProvider(info: mask, videoSize: CGSize(width: video.width ?? 0, height: video.height ?? 0))
                plugins.append(MaskViewPugin(maskView: danmu.danMuView, maskProvider: maskProvider))
            } else if Settings.vnMask {
                let maskProvider = VMaskProvider()
                plugins.append(MaskViewPugin(maskView: danmu.danMuView, maskProvider: maskProvider))
            }
        }

        // 默认视频标题作主标题 up主用户名作副标题
        if let detail = data.detail {
            var title = detail.title
            var subTitle = detail.ownerName
            // 分页播放时则以分页标题作主标题 up主用户名+视频标题作副标题
            let pages = detail.View.pages ?? []
            if pages.count > 1, let index = pages.firstIndex(where: { $0.cid == playInfo.cid }) {
                let page = pages[index]
                title = page.part
                subTitle += "·\(detail.title)"
            }
            let infoPlugin = BVideoInfoPlugin(title: title, subTitle: subTitle, desp: detail.View.desc, pic: detail.pic, viewPoints: data.playerInfo?.view_points)
            plugins.append(infoPlugin)
            Logger.debug("updateInfoPlugin: title: \(title) subTitle: \(subTitle)")
        }

        // 最后添加，保证状态浮层盖在弹幕等其他浮层之上
        let networkStatus = PlaybackNetworkStatusPlugin { [weak playplugin] in
            playplugin?.transportStatus ?? .unknown
        }
        plugins.append(networkStatus)

        return plugins
    }

    private var playContextMode: PlayContextMode {
        switch playMode {
        case .preview:
            return .preview
        case .regular, .feedFlow:
            return .regular
        }
    }
}

// 港澳台解锁
extension VideoPlayerViewModel {
    private func fetchAreaLimitPcgVideoData(for playInfo: PlayInfo) async throws -> VideoPlayURLInfo? {
        guard Settings.areaLimitUnlock else { return nil }
        guard let epid = playInfo.epid, epid > 0 else { return nil }

        let season = try await WebRequest.requestBangumiSeasonView(epid: epid)
        let checkTitle = season.title.contains("僅") ? season.title : season.series_title
        let checkAreaList = parseAreaByTitle(title: checkTitle)
        guard !checkAreaList.isEmpty else { return nil }

        let playData = try await requestAreaLimitPcgPlayUrl(epid: epid, cid: playInfo.cid!, areaList: checkAreaList)
        return playData
    }

    private func requestAreaLimitPcgPlayUrl(epid: Int, cid: Int, areaList: [String]) async throws -> VideoPlayURLInfo? {
        for area in areaList {
            do {
                return try await WebRequest.requestAreaLimitPcgPlayUrl(epid: epid,
                                                                       cid: cid,
                                                                       area: area,
                                                                       options: playContextMode.requestOptions)
            } catch let err {
                if area == areaList.last {
                    throw err
                } else {
                    print(err)
                }
            }
        }
        return nil
    }

    private func parseAreaByTitle(title: String) -> [String] {
        if title.isMatch(pattern: "[仅|僅].*[东南亚|其他]") {
            // TODO: 未支持
            return []
        }

        var areas: [String] = []
        if title.isMatch(pattern: "僅.*台") {
            areas.append("tw")
        }
        if title.isMatch(pattern: "僅.*港") {
            areas.append("hk")
        }

        if areas.isEmpty {
            // 标题没有地区限制信息，返回尝试检测的区域
            return ["tw", "hk"]
        } else {
            return areas
        }
    }
}
