//
//  LiveStreamOptionsPlugin.swift
//  BilibiliLive
//
//  直播播放选项：底栏「清晰度」（原画 / 蓝光 / 超清…，按直播间实际可选项）；
//  线路切换收进「更多 › 切换线路」，只显示「线路 1（推荐）」这类名称，不暴露封装格式、编码等技术信息。
//

import AVKit
import UIKit

struct LiveQualityOption: Equatable {
    let qn: Int
    let name: String
}

final class LiveStreamOptionsPlugin: NSObject, CommonPlayerPlugin {
    /// 可选清晰度（由高到低）
    var qualities: () -> [LiveQualityOption] = { [] }
    /// 当前实际播放的清晰度 qn
    var currentQn: () -> Int? = { nil }
    /// 当前清晰度下的全部线路（第一条为推荐）
    var lines: () -> [LivePlayUrlInfo] = { [] }
    var onSelectQuality: ((Int) -> Void)?
    var onSelectLine: ((String) -> Void)?

    private weak var playerVC: AVPlayerViewController?

    func playerDidLoad(playerVC: AVPlayerViewController) {
        self.playerVC = playerVC
    }

    /// 清晰度或线路列表变化后刷新底栏
    func reloadMenus() {
        DispatchQueue.main.async { [weak self] in
            (self?.playerVC?.parent as? CommonPlayerViewController)?.updateMenus()
        }
    }

    func addMenuItems(current: inout [UIMenuElement]) -> [UIMenuElement] {
        var result = [UIMenuElement]()

        let qualities = qualities()
        let currentQn = currentQn()
        if !qualities.isEmpty {
            let actions = qualities.map { option in
                UIAction(title: option.name, state: option.qn == currentQn ? .on : .off) { [weak self] _ in
                    guard option.qn != currentQn else { return }
                    self?.onSelectQuality?(option.qn)
                }
            }
            result.append(UIMenu(title: "清晰度",
                                 image: UIImage(systemName: "sparkles.tv"),
                                 identifier: PlayerMenu.quality,
                                 options: .singleSelection,
                                 children: actions))
        }

        let lines = lines()
        if lines.count > 1 {
            let currentUrl = (playerVC?.player?.currentItem?.asset as? AVURLAsset)?.url.absoluteString
            let actions = lines.enumerated().map { index, info in
                let title = index == 0 ? "线路 1（推荐）" : "线路 \(index + 1)"
                return UIAction(title: title, state: info.url == currentUrl ? .on : .off) { [weak self] _ in
                    self?.onSelectLine?(info.url)
                    self?.reloadMenus()
                }
            }
            let lineMenu = UIMenu(title: "切换线路",
                                  image: UIImage(systemName: "point.3.connected.trianglepath.dotted"),
                                  identifier: PlayerMenu.line,
                                  options: .singleSelection,
                                  children: actions)
            PlayerMenu.appendToMore([lineMenu], current: &current)
        }
        return result
    }
}
