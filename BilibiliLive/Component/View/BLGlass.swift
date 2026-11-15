//
//  BLGlass.swift
//  BilibiliLive
//
//  全局统一的毛玻璃材质：tvOS 26 起使用系统 Liquid Glass，更早的系统退回深色模糊。
//

import UIKit

enum BLGlass {
    /// 平台默认的玻璃材质
    static func effect() -> UIVisualEffect {
        if #available(tvOS 26.0, *) {
            return UIGlassEffect(style: .regular)
        }
        return UIBlurEffect(style: .dark)
    }

    /// 生成一块圆角玻璃底板。内容加到返回视图的 `contentView` 上。
    static func makeView(cornerRadius: CGFloat, border: Bool = true) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: effect())
        apply(to: view, cornerRadius: cornerRadius, border: border)
        return view
    }

    /// 把已有的 effect view 改成统一的玻璃样式（例如来自 storyboard 的视图）
    static func apply(to view: UIVisualEffectView, cornerRadius: CGFloat, border: Bool = true) {
        view.effect = effect()
        // 玻璃上统一使用浅色文字，固定深色外观，避免浅色模式下玻璃变亮导致文字看不清
        view.overrideUserInterfaceStyle = .dark
        view.layer.cornerRadius = cornerRadius
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        if border {
            view.layer.borderWidth = 1.5
            view.layer.borderColor = UIColor(white: 1, alpha: 0.1).cgColor
        }
    }

    enum Color {
        /// 玻璃上的主文字
        static let text = UIColor.white
        /// 玻璃上的次要文字
        static let secondaryText = UIColor(white: 1, alpha: 0.65)
        /// 当前选中但未聚焦时叠在玻璃上的提亮层
        static let selectedFill = UIColor(white: 1, alpha: 0.16)
        /// 聚焦时的系统白色底
        static let focusedFill = UIColor.white
        static let focusedText = UIColor.black
        /// 危险操作文字（如登出）：玻璃上 / 聚焦白底上
        static let destructive = UIColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1)
        static let destructiveOnLight = UIColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1)
    }
}
