//
//  Settings+TabBar.swift
//  BilibiliLive
//
//  Created by yicheng on 2026/3/5.
//

import Foundation

extension Settings {
    enum TabBarPageSection: String, Codable, CaseIterable {
        case tabBar
        case personal

        var title: String {
            switch self {
            case .tabBar:
                return "导航栏"
            case .personal:
                return "我的页面"
            }
        }
    }

    struct TabBarPagePlacement: Codable, Hashable {
        var page: TabBarPage
        var section: TabBarPageSection
    }

    @UserDefaultCodable("Settings.tabBarPagePlacements", defaultValue: [])
    static var tabBarPagePlacements: [TabBarPagePlacement]

    // 导航栏
    static var tabBarPages: [TabBarPage] {
        normalizedPlacements.filter { $0.section == .tabBar }.map(\.page)
    }

    // 个人中心
    static var personalPages: [TabBarPage] {
        normalizedPlacements.filter { $0.section == .personal }.map(\.page)
    }

    // 初始化
    static func bootstrapTabBarPlacementModelIfNeeded() {
        if tabBarPagePlacements.isEmpty {
            tabBarPagePlacements = defaultPlacements
        } else {
            tabBarPagePlacements = normalize(tabBarPagePlacements)
        }
    }

    static func setPlacements(_ placements: [TabBarPagePlacement]) {
        tabBarPagePlacements = normalize(placements)
        NotificationCenter.default.post(name: .tabBarPagesDidChange, object: nil)
    }

    static var currentPlacements: [TabBarPagePlacement] {
        normalizedPlacements
    }

    static var defaultPlacements: [TabBarPagePlacement] {
        TabBarPage.allConfigurablePages.map { page in
            let section: TabBarPageSection = TabBarPage.defaultTabBarPages.contains(page) ? .tabBar : .personal
            return .init(page: page, section: page.isFixedInTabBar ? .tabBar : section)
        }
    }

    // MARK: - Private

    private static var normalizedPlacements: [TabBarPagePlacement] {
        let source = tabBarPagePlacements.isEmpty ? defaultPlacements : tabBarPagePlacements
        let normalized = normalize(source)
        if normalized != source {
            tabBarPagePlacements = normalized
        }
        return normalized
    }

    /// 导航栏至少保留的页面数（与 Tab 自定义页的限制一致）
    static let minimumTabBarPageCount = 3

    /// 迁移已合并的旧页面：「关注UP」并入「关注」。
    /// 合并后的「关注」取两者中更「显眼」的位置：只要有一个在导航栏，就放在导航栏里靠前的那个位置
    /// （保留原来的启动页），否则放在靠前的那个位置。
    private static func migrateLegacyPages(_ placements: [TabBarPagePlacement]) -> [TabBarPagePlacement] {
        // 刷视频模式下「关注UP」仍是独立页面，不迁移
        guard !TabBarPage.allConfigurablePages.contains(.followUps),
              placements.contains(where: { $0.page == .followUps }) else { return placements }
        let merged: Set<TabBarPage> = [.follows, .followUps]
        let candidates = placements.indices.filter { merged.contains(placements[$0].page) }
        guard let keep = candidates.first(where: { placements[$0].section == .tabBar }) ?? candidates.first else {
            return placements
        }
        return placements.indices.compactMap { index in
            let placement = placements[index]
            guard merged.contains(placement.page) else { return placement }
            return index == keep ? .init(page: .follows, section: placement.section) : nil
        }
    }

    // 标准化
    private static func normalize(_ placements: [TabBarPagePlacement]) -> [TabBarPagePlacement] {
        var result = [TabBarPagePlacement]()
        var used = Set<TabBarPage>()

        for placement in migrateLegacyPages(placements) {
            guard TabBarPage.allConfigurablePages.contains(placement.page), !used.contains(placement.page) else { continue }
            let section: TabBarPageSection = placement.page.isFixedInTabBar ? .tabBar : placement.section
            result.append(.init(page: placement.page, section: section))
            used.insert(placement.page)
        }

        for page in TabBarPage.allConfigurablePages where !used.contains(page) {
            let section: TabBarPageSection = TabBarPage.defaultTabBarPages.contains(page) ? .tabBar : .personal
            result.append(.init(page: page, section: page.isFixedInTabBar ? .tabBar : section))
        }

        if !result.contains(where: { $0.page == .personal && $0.section == .tabBar }) {
            result.removeAll { $0.page == .personal }
            result.append(.init(page: .personal, section: .tabBar))
        }

        // 迁移合并页面后导航栏可能少于下限：按顺序把「我的页面」里的页面补回导航栏
        var tabBarCount = result.filter { $0.section == .tabBar }.count
        for index in result.indices where tabBarCount < minimumTabBarPageCount && result[index].section == .personal {
            result[index].section = .tabBar
            tabBarCount += 1
        }

        return result
    }
}
