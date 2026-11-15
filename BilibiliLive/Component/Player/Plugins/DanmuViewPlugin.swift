//
//  DanmuViewPlugin.swift
//  BilibiliLive
//
//  Created by yicheng on 2024/5/23.
//

import AVKit
import Combine
import UIKit

protocol DanmuProviderProtocol {
    var observerPlayerTime: Bool { get }
    var onSendTextModel: PassthroughSubject<DanmakuTextCellModel, Never> { get }
    func playerTimeChange(time: TimeInterval)
}

class DanmuViewPlugin: NSObject {
    let danMuView = DanmakuView()

    init(provider: DanmuProviderProtocol) {
        danmuProvider = provider
        super.init()
        provider.onSendTextModel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.shoot($0)
            }.store(in: &cancellable)

        Defaults.shared.$showDanmu
            .receive(on: DispatchQueue.main)
            .sink {
                [weak self] in
                self?.danMuView.isHidden = !$0
            }.store(in: &cancellable)
    }

    private let danmuProvider: DanmuProviderProtocol
    private var timeObserver: Any?
    private weak var currentPlayer: AVPlayer? // 保存当前 player 的弱引用
    private weak var playerVC: AVPlayerViewController?
    private var cancellable = Set<AnyCancellable>()

    private func shoot(_ model: DanmakuCellModel) {
        // 当显示区域小于1时,将底部弹幕转为浮动弹幕
        if danMuView.displayArea < 1, model.type == .bottom {
            if let shootModel = model as? DanmakuTextCellModel {
                shootModel.type = .floating
                danMuView.shoot(danmaku: shootModel)
                return
            }
        }

        danMuView.shoot(danmaku: model)
    }
}

extension DanmuViewPlugin: CommonPlayerPlugin {
    func playerDidChange(player: AVPlayer) {
        // 清理旧的 observer（必须用旧的 player 来移除）
        if let timeObserver, let currentPlayer {
            currentPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        // 保存新的 player 引用
        currentPlayer = player

        // 清空当前显示的弹幕，准备重新同步
        danMuView.clean()
    }

    func playerWillStart(player: AVPlayer) {
        guard danmuProvider.observerPlayerTime else {
            return
        }

        // 清理旧的 observer（如果有）
        if let timeObserver, let currentPlayer {
            currentPlayer.removeTimeObserver(timeObserver)
        }

        // 保存新的 player 引用
        currentPlayer = player

        // 添加新的 observer 并保存引用
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1),
                                                      queue: DispatchQueue.global())
        { [weak self] time in
            guard let self else { return }
            if !Defaults.shared.showDanmu { return }
            let seconds = time.seconds
            danmuProvider.playerTimeChange(time: seconds)
        }
    }

    func playerDidCleanUp(player: AVPlayer) {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        currentPlayer = nil
    }

    func addViewToPlayerOverlay(container: UIView) {
        container.addSubview(danMuView)
        danMuView.makeConstraintsToBindToSuperview()
        danMuView.setNeedsLayout()
        danMuView.layoutIfNeeded()
        danMuView.paddingTop = 5
        danMuView.trackHeight = 50
        danMuView.displayArea = Settings.danmuArea.percent
        danMuView.recaculateTracks()
    }

    func playerDidStart(player: AVPlayer) {
        danMuView.play()
    }

    func playerDidPause(player: AVPlayer) {
        danMuView.pause()
    }

    func playerDidLoad(playerVC: AVPlayerViewController) {
        self.playerVC = playerVC
    }

    /// 底栏「弹幕」按钮：显示开关、展示时长、屏蔽等级合在一处；图标随开关状态变化
    func addMenuItems(current: inout [UIMenuElement]) -> [UIMenuElement] {
        let isShowing = Defaults.shared.showDanmu
        // 刷新底栏，让按钮图标和标题反映最新状态
        let refreshMenus: () -> Void = { [weak self] in
            DispatchQueue.main.async {
                (self?.playerVC?.parent as? CommonPlayerViewController)?.updateMenus()
            }
        }
        let toggleAction = UIAction(title: "显示弹幕",
                                    image: UIImage(systemName: isShowing ? "eye" : "eye.slash"),
                                    state: isShowing ? .on : .off)
        { action in
            Defaults.shared.showDanmu.toggle()
            // 菜单选中后不会自动收起，已展示的菜单项不会因重建而刷新，
            // 所以直接改这个 action 自身的勾选状态和图标
            let showing = Defaults.shared.showDanmu
            action.state = showing ? .on : .off
            action.image = UIImage(systemName: showing ? "eye" : "eye.slash")
            refreshMenus()
        }
        let durationMenu = UIMenu(title: "展示时长", options: [.displayInline, .singleSelection], children: [4, 6, 8].map { dur in
            UIAction(title: "\(dur) 秒", state: dur == Settings.danmuDuration ? .on : .off) { _ in Settings.danmuDuration = dur }
        })
        let levelMenu = UIMenu(title: "智能屏蔽等级（当前 \(Settings.danmuAILevel)）",
                               image: UIImage(systemName: "shield.lefthalf.filled"),
                               options: .singleSelection,
                               children: [Int32](1...10).map { level in
                                   UIAction(title: "\(level)", state: level == Settings.danmuAILevel ? .on : .off) { _ in
                                       Settings.danmuAILevel = level
                                       refreshMenus()
                                   }
                               })
        let menu = UIMenu(title: "弹幕",
                          image: UIImage(systemName: isShowing ? "list.bullet.rectangle.fill" : "list.bullet.rectangle"),
                          identifier: PlayerMenu.danmu,
                          children: [toggleAction, durationMenu, levelMenu])
        return [menu]
    }
}
