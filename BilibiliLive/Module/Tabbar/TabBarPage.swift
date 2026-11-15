//
//  TabBarPage.swift
//  BilibiliLive
//

import Foundation
import UIKit

enum TabBarPage: String, CaseIterable, Codable {
    case live
    case feed
    case hot
    case ranking
    case follows
    case favorite
    case personal
    case search
    case followBangumi
    case followUps
    case toView
    case history
    case weeklyWatch
    case tvRecommend

    var title: String {
        switch self {
        case .live:
            return "直播"
        case .feed:
            return "推荐"
        case .tvRecommend:
            return "TV推荐"
        case .hot:
            return "热门"
        case .ranking:
            return "排行榜"
        case .follows:
            return "关注"
        case .favorite:
            return "收藏"
        case .personal:
            return "我的"
        case .search:
            return "搜索"
        case .followBangumi:
            return "追番追剧"
        case .followUps:
            return "关注UP"
        case .toView:
            return "稍后再看"
        case .history:
            return "历史记录"
        case .weeklyWatch:
            return "每周必看"
        }
    }

    var isFixedInTabBar: Bool {
        self == .personal
    }

    var requirePresentInPersonalPage: Bool {
        switch self {
        case .favorite, .search, .followBangumi, .tvRecommend:
            return true
        default:
            return false
        }
    }

    static var defaultTabBarPages: [TabBarPage] {
        [.live, .feed, .hot, .ranking, .follows, .favorite, .personal, .search]
    }

    /// 「关注UP」已并入「关注」页顶部的 UP 主横排，不再单独作为页面出现；
    /// 枚举值保留，保证旧的页面排序配置仍能正常解码（解码后会被标准化逻辑移除）
    static var allConfigurablePages: [TabBarPage] {
        allCases.filter { $0 != .followUps }
    }
}
