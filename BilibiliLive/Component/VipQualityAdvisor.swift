//
//  VipQualityAdvisor.swift
//  BilibiliLive
//
//  检测到大会员、但最高画质被手动设成 1080p 时，提示一次是否改为「自动」。
//  每个账号只提示一次；没手动设过画质的用户默认就是「自动」，不打扰。
//

import UIKit

enum VipQualityAdvisor {
    private static let promptedKey = "VipQualityAdvisor.promptedMIDs"
    /// 弹窗进行中时不重复弹
    private static var isPresenting = false

    private static var promptedMIDs: Set<Int> {
        get { Set(UserDefaults.standard.array(forKey: promptedKey) as? [Int] ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: promptedKey) }
    }

    static func promptIfNeeded(mid: Int, vip: AccountManager.VipInfo) {
        guard vip.isActive,
              Settings.mediaQuality == .quality_1080p,
              !isPresenting,
              !promptedMIDs.contains(mid)
        else { return }
        // 冷启动时根控制器可能还没挂到窗口上，这时 UIKit 会拒绝弹窗；等下次刷新资料再试
        guard let window = AppDelegate.shared.window, let root = window.rootViewController else { return }
        let top = root.topMostViewController()
        guard top.viewIfLoaded?.window != nil,
              !top.isBeingPresented,
              !top.isBeingDismissed,
              !(top is UIAlertController)
        else { return }

        let target = MediaQualityEnum.autoLimit.desp
        let alert = UIAlertController(title: "已识别为\(vip.displayName)",
                                      message: "当前最高画质手动限制在 1080p。改为「自动」后，会按大会员权益和电视能力播放（当前可到 \(target)）。之后也可以在 设置 → 音视频 → 最高画质 中修改。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "改为自动", style: .default) { _ in
            Settings.mediaQuality = .auto
            isPresenting = false
        })
        alert.addAction(UIAlertAction(title: "保持 1080p", style: .cancel) { _ in
            isPresenting = false
        })
        isPresenting = true
        top.present(alert, animated: true) {
            // 只有真正弹出来了才记为已提示；弹出失败时不会走到这里，下次刷新还会再试
            promptedMIDs.insert(mid)
        }
        // UIKit 接受了弹窗时会立即建立 presenting 关系；没建立说明被拒绝，放开以便之后重试
        if alert.presentingViewController == nil {
            isPresenting = false
        }
    }
}
