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

    static func promptIfNeeded(mid: Int, vip: AccountManager.VipInfo) {
        guard vip.isActive, Settings.mediaQuality == .quality_1080p else { return }
        var prompted = Set(UserDefaults.standard.array(forKey: promptedKey) as? [Int] ?? [])
        guard !prompted.contains(mid) else { return }
        // 冷启动时窗口可能还没准备好，下次刷新资料再提示
        guard let window = AppDelegate.shared.window, let root = window.rootViewController else { return }
        let top = root.topMostViewController()
        guard !(top is UIAlertController) else { return }

        prompted.insert(mid)
        UserDefaults.standard.set(Array(prompted), forKey: promptedKey)

        let target = MediaQualityEnum.autoResolved.desp
        let alert = UIAlertController(title: "已识别为\(vip.displayName)",
                                      message: "当前最高画质手动限制在 1080p。改为「自动」后，会按大会员权益和电视能力播放（当前可到 \(target)）。之后也可以在 设置 → 音视频 → 最高画质 中修改。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "改为自动", style: .default) { _ in
            Settings.mediaQuality = .auto
        })
        alert.addAction(UIAlertAction(title: "保持 1080p", style: .cancel))
        top.present(alert, animated: true)
    }
}
