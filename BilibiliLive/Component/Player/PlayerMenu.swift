//
//  PlayerMenu.swift
//  BilibiliLive
//
//  播放页底栏自定义按钮的统一组织。各插件只往约定的分组里放菜单项，
//  最终由 CommonPlayerViewController.updateMenus() 按固定顺序排列：
//  弹幕 → 画质 / 线路 → 倍速 → 其他 → 更多（系统自带的字幕、音频始终在最右侧）。
//

import UIKit

enum PlayerMenu {
    static let danmu = UIMenu.Identifier("player.danmu")
    static let quality = UIMenu.Identifier("quality")
    static let line = UIMenu.Identifier("player.line")
    static let speed = UIMenu.Identifier("player.speed")
    static let more = UIMenu.Identifier("setting")
    static let diagnostics = UIMenu.Identifier("player.more.diagnostics")

    /// 底栏从左到右的顺序；未列出的放在「倍速」与「更多」之间
    private static let order: [UIMenu.Identifier] = [danmu, quality, line, speed]

    /// 把菜单项放进「更多」；section 不为空时放进「更多」里的一个内联分组（如「诊断」）
    static func appendToMore(_ elements: [UIMenuElement],
                             section: (identifier: UIMenu.Identifier, title: String)? = nil,
                             current: inout [UIMenuElement])
    {
        guard !elements.isEmpty else { return }
        var moreMenu = takeMenu(Self.more, from: &current)
            ?? UIMenu(title: "更多", image: UIImage(systemName: "ellipsis.circle"), identifier: Self.more, children: [])
        var children = moreMenu.children
        if let section {
            if let index = children.firstIndex(where: { ($0 as? UIMenu)?.identifier == section.identifier }),
               let existing = children[index] as? UIMenu
            {
                children[index] = existing.replacingChildren(existing.children + elements)
            } else {
                children.append(UIMenu(title: section.title, identifier: section.identifier, options: .displayInline, children: elements))
            }
        } else {
            children.append(contentsOf: elements)
        }
        moreMenu = moreMenu.replacingChildren(children)
        current.append(moreMenu)
    }

    /// 把菜单项追加进已有的某个分组菜单（如把直播「弹幕历史」并入「弹幕」）；该分组不存在时返回 false
    @discardableResult
    static func append(_ elements: [UIMenuElement], to identifier: UIMenu.Identifier, current: inout [UIMenuElement]) -> Bool {
        guard let index = current.firstIndex(where: { ($0 as? UIMenu)?.identifier == identifier }),
              let menu = current[index] as? UIMenu
        else { return false }
        current[index] = menu.replacingChildren(menu.children + elements)
        return true
    }

    /// 最终整理：去掉空菜单，「更多」里的内联分组排在普通项之后，按固定顺序排列底栏按钮
    static func arrange(_ elements: [UIMenuElement]) -> [UIMenuElement] {
        let cleaned: [UIMenuElement] = elements.compactMap { element in
            guard let menu = element as? UIMenu else { return element }
            guard !menu.children.isEmpty else { return nil }
            if menu.identifier == more {
                let plain = menu.children.filter { !(($0 as? UIMenu)?.options.contains(.displayInline) ?? false) }
                let sections = menu.children.filter { ($0 as? UIMenu)?.options.contains(.displayInline) ?? false }
                return menu.replacingChildren(plain + sections)
            }
            return menu
        }
        func rank(_ element: UIMenuElement) -> Int {
            guard let identifier = (element as? UIMenu)?.identifier else { return order.count }
            if identifier == more { return order.count + 1 }
            return order.firstIndex(of: identifier) ?? order.count
        }
        // 稳定排序：同一档内保持插件添加顺序
        return cleaned.enumerated()
            .sorted { lhs, rhs in
                let l = rank(lhs.element), r = rank(rhs.element)
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }

    private static func takeMenu(_ identifier: UIMenu.Identifier, from current: inout [UIMenuElement]) -> UIMenu? {
        guard let index = current.firstIndex(where: { ($0 as? UIMenu)?.identifier == identifier }) else { return nil }
        return current.remove(at: index) as? UIMenu
    }
}
