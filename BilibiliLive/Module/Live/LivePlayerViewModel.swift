//
//  LivePlayerViewModel.swift
//  BilibiliLive
//
//  Created by yicheng on 2024/5/13.
//

import Alamofire
import Foundation
import SwiftyJSON

enum LiveError: String, LocalizedError {
    case noLiving
    case noPlaybackUrl
    case fetchApiFail

    var errorDescription: String? {
        rawValue
    }
}

class LivePlayerViewModel {
    init(room: LiveRoom) {
        self.room = room
        roomID = room.room_id
    }

    deinit {
        danMuProvider?.stop()
    }

    var onPluginReady: (([CommonPlayerPlugin]) -> Void)?
    var onError: ((String) -> Void)?

    private let playPlugin = URLPlayPlugin(referer: Keys.liveReferer, isLive: true)
    private let debugPlugin = DebugPlugin()

    func start() {
        playPlugin.onPlayFail = { [weak self] in
            self?.playerDidFailToPlay()
        }

        debugPlugin.additionDebugInfo = { [weak self] in
            self?.debugInfo() ?? ""
        }

        onPluginReady?([playPlugin, debugPlugin])
        Task {
            do {
                try await refreshRoomsID()
                try await initPlayer()

                let danmu = await initDanmu()
                let optionsPlugin = await makeOptionsPlugin()
                // 状态浮层最后添加，保证盖在弹幕之上
                let networkStatus = await MainActor.run {
                    PlaybackNetworkStatusPlugin { [weak self] in
                        self?.transportStatus() ?? .unknown
                    }
                }
                self.onPluginReady?(danmu + [optionsPlugin, networkStatus])

                if let info = await fetchDespInfo() {
                    let subtitle = "\(room.ownerName)·\(info.parent_area_name) \(info.area_name)"
                    let desp = "\(info.description)\nTags:\(info.tags ?? "")"
                    let infoPlugin = BVideoInfoPlugin(title: info.title, subTitle: subtitle, desp: desp, pic: room.pic, viewPoints: nil)
                    self.onPluginReady?([infoPlugin])
                } else {
                    let infoPlugin = BVideoInfoPlugin(title: room.title, subTitle: nil, desp: nil, pic: room.pic, viewPoints: nil)
                    self.onPluginReady?([infoPlugin])
                }
            } catch is CancellationError {
                // 取流请求已被更新的请求（例如切换清晰度）取代
            } catch let err {
                await MainActor.run {
                    onError?(String(describing: err))
                }
            }
        }
    }

    func playerDidFailToPlay() {
        Task {
            do {
                playInfos = Array(playInfos.dropFirst())
                if playInfos.isEmpty {
                    retryCount += 1
                    if retryCount > 3 {
                        await MainActor.run {
                            onError?("播放失败")
                        }
                        return
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    try await initPlayer()
                    return
                } else {
                    try await playFirstInfo()
                }
            } catch is CancellationError {
                // 已被更新的取流请求取代
            } catch let err {
                await MainActor.run {
                    onError?(err.localizedDescription)
                }
            }
        }
    }

    /// 切换清晰度（在主线程调用）：按新的 qn 重新取流并从推荐线路开始播放。
    /// 连续切换时只有最后一次生效：之前的任务被取消，迟到的响应和失败都会被丢弃（见 initPlayer）。
    /// 切换尚未完成时选回正在播放的清晰度，等于撤回这次切换。
    func switchQuality(qn: Int) {
        if qn == activePlayInfo?.current_qn {
            guard pendingSwitchID != 0 else { return }
            // 撤回尚未完成的切换：作废它的请求，保持当前播放
            qualitySwitchTask?.cancel()
            qualitySwitchTask = nil
            pendingSwitchID = 0
            streamGeneration += 1
            requestedQn = qn
            optionsPlugin?.reloadMenus()
            return
        }

        switchCounter += 1
        let switchID = switchCounter
        pendingSwitchID = switchID
        requestedQn = qn
        retryCount = 0
        qualitySwitchTask?.cancel()
        qualitySwitchTask = Task {
            do {
                try await initPlayer()
                optionsPlugin?.reloadMenus()
            } catch is CancellationError {
                // 被更新的切换取代或已撤回
            } catch let err {
                if !Task.isCancelled {
                    await MainActor.run {
                        onError?(err.localizedDescription)
                    }
                }
            }
            await MainActor.run {
                if pendingSwitchID == switchID { pendingSwitchID = 0 }
            }
        }
    }

    /// 当前实际在播的那条流；同一次取流里不同封装/编码的实际清晰度可能不同，必须按在播地址取
    private var activePlayInfo: LivePlayUrlInfo? {
        let currentUrl = playPlugin.currentURLString
        return allPlayInfos.first { $0.url == currentUrl } ?? allPlayInfos.first
    }

    /// 右下角状态：当前清晰度 · 线路（直播没有多 CDN 加速，按线路展示）
    @MainActor private func transportStatus() -> PlaybackTransportStatus {
        guard let active = activePlayInfo else { return .unknown }
        var parts = [String]()
        if let qn = active.current_qn, let name = qualityOptions.first(where: { $0.qn == qn })?.name {
            parts.append(name)
        }
        let currentUrl = playPlugin.currentURLString
        if allPlayInfos.count > 1, let currentUrl, let index = allPlayInfos.firstIndex(where: { $0.url == currentUrl }) {
            parts.append("线路 \(index + 1)")
        }
        return parts.isEmpty ? .live(description: "直播") : .live(description: parts.joined(separator: " · "))
    }

    @MainActor private func makeOptionsPlugin() -> LiveStreamOptionsPlugin {
        let plugin = LiveStreamOptionsPlugin()
        plugin.qualities = { [weak self] in self?.qualityOptions ?? [] }
        plugin.currentQn = { [weak self] in self?.activePlayInfo?.current_qn }
        plugin.lines = { [weak self] in self?.allPlayInfos ?? [] }
        plugin.onSelectQuality = { [weak self] qn in
            self?.switchQuality(qn: qn)
        }
        plugin.onSelectLine = { [weak self] url in
            self?.playPlugin.play(urlString: url)
        }
        optionsPlugin = plugin
        return plugin
    }

    func debugInfo() -> String {
        let active = activePlayInfo
        return "\(active?.formate ?? "") \(active?.current_qn ?? 0) retry:\(retryCount)"
    }

    func fetchDespInfo() async -> WebRequest.LiveRoomInfo? {
        return try? await WebRequest.requestLiveBaseInfo(roomID: roomID)
    }

    // Private
    private var allPlayInfos = [LivePlayUrlInfo]()
    private var playInfos = [LivePlayUrlInfo]()
    private var roomID: Int
    private let room: LiveRoom
    private var danMuProvider: LiveDanMuProvider?
    private var retryCount = 0
    private var liveTime: String?
    /// 请求的清晰度（默认原画；未登录或直播间不支持时接口会自动降级）
    private var requestedQn = 10000
    private var qualityOptions = [LiveQualityOption]()
    private weak var optionsPlugin: LiveStreamOptionsPlugin?
    private var qualitySwitchTask: Task<Void, Never>?
    /// 尚未完成的清晰度切换编号；0 表示没有
    private var pendingSwitchID = 0
    private var switchCounter = 0
    /// 每次取流加一；只有最新一次取流的结果会被提交和播放
    private var streamGeneration = 0

    private func refreshRoomsID() async throws {
        let info = try await WebRequest.requestLiveRoomInit(roomID: roomID)
        if info.live_status != 1 {
            throw LiveError.noLiving
        }
        roomID = info.room_id
        liveTime = info.live_time
    }

    /// 按 requestedQn 取流。结果先在本地组装，回到主线程确认仍是最新一次请求后才提交并开始播放；
    /// 被更新的请求取代时抛 CancellationError，不改动任何状态。
    private func initPlayer() async throws {
        let (generation, qn) = await MainActor.run { () -> (Int, Int) in
            streamGeneration += 1
            return (streamGeneration, requestedQn)
        }

        let playUrl: WebRequest.LivePlayUrl
        do {
            playUrl = try await WebRequest.requestLiveStreams(roomID: roomID, qn: qn)
        } catch {
            // 请求期间已有更新的取流请求，或任务已取消：这次失败已无意义，不能报给用户
            let superseded = await MainActor.run { generation != streamGeneration }
            if superseded || Task.isCancelled { throw CancellationError() }
            throw error
        }
        let streams = playUrl.stream

        var infos = [LivePlayUrlInfo]()
        for stream in streams {
            for content in stream.format {
                let formate = content.formatName
                for codec in content.codec {
                    let baseUrl = codec.baseurl
                    for url_info in codec.urlInfo {
                        let url = "\(url_info.host)\(baseUrl)\(url_info.extra)"
                        infos.append(LivePlayUrlInfo(formate: formate, url: url, current_qn: codec.currentQn, codec_name: codec.codecName))
                    }
                }
            }
        }

        infos.sort { a, b in
            return a.current_qn ?? 0 > b.current_qn ?? 0
        }
        infos.sort { a, _ in
            return a.formate == "fmp4"
        }

        // 可选清晰度 = 各路流 accept_qn 的并集，名称取 g_qn_desc（原画、蓝光、超清…）
        let accepted = Set(streams.flatMap { $0.format.flatMap { $0.codec.flatMap { $0.acceptQn ?? [$0.currentQn] } } })
        let options = (playUrl.g_qn_desc ?? [])
            .filter { accepted.contains($0.qn) }
            .sorted { $0.qn > $1.qn }
            .map { LiveQualityOption(qn: $0.qn, name: $0.desc) }

        guard let first = infos.first else { throw LiveError.noPlaybackUrl }
        let resolved = infos
        let committed = await MainActor.run { () -> Bool in
            guard generation == streamGeneration else { return false }
            allPlayInfos = resolved
            playInfos = resolved
            qualityOptions = options
            Logger.debug("play => \(first.url)")
            playPlugin.play(urlString: first.url)
            return true
        }
        if !committed { throw CancellationError() }
    }

    func playFirstInfo() async throws {
        if let info = playInfos.first {
            Logger.debug("play => \(playInfos)")
            await MainActor.run {
                playPlugin.play(urlString: info.url)
            }
        } else {
            throw LiveError.noPlaybackUrl
        }
    }

    @MainActor private func initDanmu() async -> [CommonPlayerPlugin] {
        danMuProvider = LiveDanMuProvider(roomID: roomID, removeDup: Settings.enableDanmuRemoveDup)
        let danmuPlugin = DanmuViewPlugin(provider: danMuProvider!)

        // Retrieve only the history for the current broadcast session
        let sessionKey = liveTime.flatMap { $0.hasPrefix("0000") ? nil : $0 } ?? "unknown"
        let historyStore = LiveDanmuHistoryStore(roomID: roomID, sessionKey: sessionKey)
        danMuProvider?.historyStore = historyStore
        Task { await historyStore.loadRemoteHistory() }

        try? await danMuProvider?.start()
        var plugins: [CommonPlayerPlugin] = [danmuPlugin, LiveDanmuHistoryPlugin(store: historyStore)]
        if Settings.danmuMask, Settings.vnMask {
            let plugin = MaskViewPugin(maskView: danmuPlugin.danMuView, maskProvider: VMaskProvider())
            plugins.append(plugin)
        }

        return plugins
    }
}

struct LivePlayUrlInfo {
    let formate: String?
    let url: String
    let current_qn: Int?
    let codec_name: String?
}

extension WebRequest.EndPoint {
    static let liveRoomInfo = "https://api.live.bilibili.com/room/v1/Room/get_info"
    static let liveRoomStream = "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo"
    static let liveRoomInit = "https://api.live.bilibili.com/room/v1/Room/room_init"
}

extension WebRequest {
    struct LiveRoomInfo: Codable {
        let description: String
        let parent_area_name: String
        let title: String
        let tags: String?
        let area_name: String
        let hot_words: [String]?
    }

    static func requestLiveBaseInfo(roomID: Int) async throws -> LiveRoomInfo {
        return try await request(url: EndPoint.liveRoomInfo, parameters: ["room_id": roomID])
    }

    struct LiveRoomInit: Codable {
        var live_status: Int
        var room_id: Int
        var live_time: String?
    }

    static func requestLiveRoomInit(roomID: Int) async throws -> LiveRoomInit {
        return try await request(url: EndPoint.liveRoomInfo, parameters: ["id": roomID])
    }

    struct LivePlayUrl: Codable {
        struct QnDesc: Codable {
            let qn: Int
            let desc: String
        }

        let cid: Int
        let g_qn_desc: [QnDesc]?
        let stream: [LiveStream]
    }

    static func requestLiveStreams(roomID: Int, qn: Int = 10000) async throws -> LivePlayUrl {
        struct LiveRoomStreamInfo: Codable {
            let playurl_info: PlayUrlInfo

            struct PlayUrlInfo: Codable {
                let playurl: LivePlayUrl
            }
        }
        let info: LiveRoomStreamInfo = try await request(url: EndPoint.liveRoomStream,
                                                         parameters: ["room_id": roomID,
                                                                      "protocol": "1",
                                                                      "format": "0,1,2",
                                                                      "codec": "0,1",
                                                                      "qn": "\(qn)",
                                                                      "platform": "web",
                                                                      "ptype": "8",
                                                                      "dolby": "5",
                                                                      "panorama": 1])
        return info.playurl_info.playurl
    }
}

struct LiveStream: Codable {
    let format: [Format]
    let protocol_name: String

    struct Format: Codable {
        let formatName: String
        let codec: [Codec]
        let masterurl: String

        enum CodingKeys: String, CodingKey {
            case formatName = "format_name"
            case codec
            case masterurl = "master_url"
        }

        struct Codec: Codable {
            let urlInfo: [URLInfo]
            let codecName: String
            let currentQn: Int
            let acceptQn: [Int]?
            let baseurl: String

            enum CodingKeys: String, CodingKey {
                case urlInfo = "url_info"
                case codecName = "codec_name"
                case currentQn = "current_qn"
                case acceptQn = "accept_qn"
                case baseurl = "base_url"
            }

            struct URLInfo: Codable {
                let host: String
                let extra: String
            }
        }
    }
}
