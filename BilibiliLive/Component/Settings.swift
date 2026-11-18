//
//  Settings.swift
//  BilibiliLive
//
//  Created by whw on 2022/10/19.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

enum FeedDisplayStyle: Codable, CaseIterable {
    case large
    case normal
    case sideBar

    var hideInSetting: Bool {
        self == .sideBar
    }
}

class Defaults {
    static let shared = Defaults()
    private init() {}

    @Published(key: "Settings.danmuStatus") var showDanmu = true
}

enum Settings {
    @UserDefaultCodable("Settings.displayStyle", defaultValue: .normal)
    static var displayStyle: FeedDisplayStyle

    @UserDefault("Settings.direatlyEnterVideo", defaultValue: false)
    static var direatlyEnterVideo: Bool

    /// 默认「自动」：大会员按电视能力放开到 4K / 杜比视界，非大会员 1080p
    @UserDefaultCodable("Settings.mediaQuality", defaultValue: .auto)
    static var mediaQuality: MediaQualityEnum

    @UserDefaultCodable("Settings.mediaPlayerSpeed", defaultValue: PlaySpeed.default)
    static var mediaPlayerSpeed: PlaySpeed

    @UserDefaultCodable("Settings.danmuArea", defaultValue: .style_75)
    static var danmuArea: DanmuArea

    @UserDefaultCodable("Settings.danmuSize", defaultValue: .size_36)
    static var danmuSize: DanmuSize

    @UserDefaultCodable("Settings.danmuAILevel", defaultValue: 1)
    static var danmuAILevel: Int32

    @UserDefaultCodable("Settings.danmuDuration", defaultValue: 8)
    static var danmuDuration: Double

    /// 有杜比全景声 / Hi-Res 无损流时（需大会员）设为默认音轨；拿不到时自动用普通音轨
    @UserDefault("Settings.losslessAudio", defaultValue: true)
    static var losslessAudio: Bool

    @UserDefault("Settings.preferAvc", defaultValue: false)
    static var preferAvc: Bool

    /// 分段拆块后从多个 CDN 节点并发下载；高码率（4K/HDR）时提升明显，异常时自动回退直连
    @UserDefault("Settings.multiCDNEnabled", defaultValue: true)
    static var multiCDNEnabled: Bool

    @UserDefault("Settings.danmuMask", defaultValue: true)
    static var danmuMask: Bool

    @UserDefault("Settings.vnMask", defaultValue: false)
    static var vnMask: Bool

    @UserDefault("Settings.loadHighestVideoOnly", defaultValue: false)
    static var loadHighestVideoOnly: Bool

    @UserDefault("Settings.contentMatch", defaultValue: true)
    static var contentMatch: Bool

    @UserDefault("Settings.contentMatchOnlyInHDR", defaultValue: true)
    static var contentMatchOnlyInHDR: Bool

    @UserDefault("Settings.continuePlay", defaultValue: true)
    static var continuePlay: Bool

    @UserDefault("DLNA.uuid", defaultValue: "")
    static var uuid: String

    @UserDefault("DLNA.enable", defaultValue: true)
    static var enableDLNA: Bool

    @UserDefault("Settings.continouslyPlay", defaultValue: true)
    static var continouslyPlay: Bool

    @UserDefault("Settings.loopPlay", defaultValue: false)
    static var loopPlay: Bool

    @UserDefault("Settings.play.autoSkip", defaultValue: true)
    static var autoSkip: Bool

    @UserDefault("Settings.showRelatedVideoInCurrentVC", defaultValue: true)
    static var showRelatedVideoInCurrentVC: Bool

    @UserDefault("Settings.requestHotWithoutCookie", defaultValue: false)
    static var requestHotWithoutCookie: Bool

    @UserDefault("Settings.arealimit.unlock", defaultValue: false)
    static var areaLimitUnlock: Bool

    @UserDefault("Settings.arealimit.customServer", defaultValue: "")
    static var areaLimitCustomServer: String

    @UserDefault("Settings.ui.sideMenuAutoSelectChange", defaultValue: false)
    static var sideMenuAutoSelectChange: Bool

    @UserDefaultCodable("Settings.featuredDurationLimit", defaultValue: .minutes10)
    static var featuredDurationLimit: FeaturedDurationLimit

    @UserDefault("Settings.recommendFeedFlowEnabled", defaultValue: false)
    static var recommendFeedFlowEnabled: Bool

    @UserDefault("Settings.featuredContentSafetyFilterEnabled", defaultValue: true)
    static var featuredContentSafetyFilterEnabled: Bool

    @UserDefault("Settings.followsFeedFlowEnabled", defaultValue: false)
    static var followsFeedFlowEnabled: Bool

    /// 登录了两个及以上账号时，冷启动先显示账号选择页
    @UserDefault("Settings.chooseAccountOnLaunch", defaultValue: true)
    static var chooseAccountOnLaunch: Bool

    @UserDefaultCodable("Settings.SponsorBlockType", defaultValue: SponsorBlockType.none)
    static var enableSponsorBlock: SponsorBlockType

    @UserDefault("Settings.danmuFilter", defaultValue: false)
    static var enableDanmuFilter: Bool

    @UserDefault("Settings.danmuRemoveDup", defaultValue: false)
    static var enableDanmuRemoveDup: Bool

    @UserDefaultCodable("Settings.danmuAlpha", defaultValue: .alpha_10)
    static var danmuAlpha: DanmuAlpha

    @UserDefaultCodable("Settings.danmuStrokeWidth", defaultValue: .width_20)
    static var danmuStrokeWidth: DanmuStrokeWidth

    @UserDefaultCodable("Settings.danmuStrokeAlpha", defaultValue: .alpha_08)
    static var danmuStrokeAlpha: DanmuStrokeAlpha

    @UserDefaultCodable("Search.histories", defaultValue: [])
    static var searchHistories: [String]
}

extension Settings {
    static func addHistory(_ query: String, limitSize: Int = 6) {
        if query.isEmpty {
            return
        }

        var histories = Settings.searchHistories
        if histories.first == query {
            return
        }

        if let i = histories.firstIndex(of: query) {
            histories.remove(at: i)
        }

        histories.insert(query, at: 0)
        if histories.count > limitSize {
            histories.removeLast()
        }
        Settings.searchHistories = histories
    }

    static func clearHistory() {
        Settings.searchHistories = []
    }
}

struct MediaQuality {
    var qn: Int
    var fnval: Int
}

enum SponsorBlockType: String, Codable, CaseIterable {
    case none
    case jump
    case tip

    var title: String {
        switch self {
        case .none:
            return "关"
        case .jump:
            return "自动跳过"
        case .tip:
            return "手动跳过"
        }
    }
}

enum DanmuArea: Codable, CaseIterable {
    case style_75
    case style_50
    case style_25
    case style_0
}

enum DanmuSize: String, Codable, CaseIterable {
    case size_25
    case size_31
    case size_36
    case size_42
    case size_48
    case size_57

    var title: String {
        return "\(Int(size)) pt"
    }

    var size: CGFloat {
        switch self {
        case .size_25:
            return 25
        case .size_31:
            return 31
        case .size_36:
            return 36
        case .size_42:
            return 42
        case .size_48:
            return 48
        case .size_57:
            return 57
        }
    }
}

enum DanmuAlpha: Double, Codable, CaseIterable {
    case alpha_03 = 0.3
    case alpha_04 = 0.4
    case alpha_05 = 0.5
    case alpha_06 = 0.6
    case alpha_07 = 0.7
    case alpha_08 = 0.8
    case alpha_09 = 0.9
    case alpha_10 = 1.0

    var title: String {
        return String(format: "%.1f", rawValue)
    }
}

enum DanmuStrokeWidth: Double, Codable, CaseIterable {
    case width_0 = 0.0
    case width_05 = 0.5
    case width_10 = 1.0
    case width_15 = 1.5
    case width_20 = 2.0

    var title: String {
        return String(format: "%.1f", rawValue)
    }
}

enum DanmuStrokeAlpha: Double, Codable, CaseIterable {
    case alpha_00 = 0.0
    case alpha_01 = 0.1
    case alpha_02 = 0.2
    case alpha_03 = 0.3
    case alpha_04 = 0.4
    case alpha_05 = 0.5
    case alpha_06 = 0.6
    case alpha_07 = 0.7
    case alpha_08 = 0.8
    case alpha_09 = 0.9
    case alpha_10 = 1.0

    var title: String {
        return String(format: "%.1f", rawValue)
    }
}

extension DanmuArea {
    var title: String {
        switch self {
        case .style_75:
            return "3/4屏"
        case .style_50:
            return "半屏"
        case .style_25:
            return "1/4屏"
        case .style_0:
            return "不限制"
        }
    }

    var percent: CGFloat {
        switch self {
        case .style_75:
            return 0.75
        case .style_50:
            return 0.5
        case .style_25:
            return 0.25
        case .style_0:
            return 1
        }
    }
}

enum FeaturedDurationLimit: Codable, CaseIterable, Equatable {
    case minutes3
    case minutes5
    case minutes10
    case minutes15
    case unlimited
}

extension FeaturedDurationLimit {
    var title: String {
        switch self {
        case .minutes3:
            return "3 分钟"
        case .minutes5:
            return "5 分钟"
        case .minutes10:
            return "10 分钟"
        case .minutes15:
            return "15 分钟"
        case .unlimited:
            return "不限"
        }
    }

    var maxDuration: Int? {
        switch self {
        case .minutes3:
            return 3 * 60
        case .minutes5:
            return 5 * 60
        case .minutes10:
            return 10 * 60
        case .minutes15:
            return 15 * 60
        case .unlimited:
            return nil
        }
    }
}

enum MediaQualityEnum: Codable, CaseIterable {
    case auto
    case quality_1080p
    case quality_2160p
    case quality_hdr_dolby
}

extension MediaQualityEnum {
    var desp: String {
        switch self {
        case .auto:
            return "自动"
        case .quality_1080p:
            return "1080p"
        case .quality_2160p:
            return "4K"
        case .quality_hdr_dolby:
            return "杜比视界"
        }
    }

    /// 档位本身的上限；「自动」按当前账号与设备解析，见 `resolvedQn`
    var qn: Int {
        switch self {
        case .auto:
            return Self.autoLimit.qn
        case .quality_1080p:
            return 116
        case .quality_2160p:
            return 120
        case .quality_hdr_dolby:
            return 126
        }
    }

    var fnval: Int {
        switch self {
        case .auto:
            return MediaQualityEnum.quality_hdr_dolby.fnval
        case .quality_1080p:
            return 16
        case .quality_2160p:
            return 144
        case .quality_hdr_dolby:
            return 976
        }
    }
}

extension MediaQualityEnum {
    /// HDR10 档位的 qn（B 站 125）
    static let hdr10Qn = 125

    /// 「自动」实际对应的上限，按电视实际支持的 HDR 格式区分：
    /// 大会员 + 支持杜比视界 → 126；大会员 + 只支持 HDR10 → 125（不放开杜比视界）；
    /// 大会员 + 不支持 HDR → 4K（120）；非大会员 → 1080p
    static var autoLimit: (qn: Int, desp: String) {
        guard AccountManager.shared.isActiveAccountVip else {
            return (quality_1080p.qn, quality_1080p.desp)
        }
        let modes = AVPlayer.availableHDRModes
        if modes.contains(.dolbyVision) {
            return (quality_hdr_dolby.qn, quality_hdr_dolby.desp)
        }
        if modes.contains(.hdr10) {
            return (hdr10Qn, "HDR")
        }
        return (quality_2160p.qn, quality_2160p.desp)
    }

    /// 播放时真正生效的画质上限（qn）
    var resolvedQn: Int {
        self == .auto ? Self.autoLimit.qn : qn
    }

    /// 设置页右侧显示的当前值，「自动」带上解析结果
    var currentDescription: String {
        self == .auto ? "自动 · \(Self.autoLimit.desp)" : desp
    }
}
