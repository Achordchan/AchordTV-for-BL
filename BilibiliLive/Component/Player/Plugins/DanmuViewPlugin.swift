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
        danMuView.trackHeight = Self.trackHeight(for: Settings.danmuSize)
        danMuView.displayArea = Settings.danmuArea.percent
        danMuView.recaculateTracks()
    }

    /// 轨道高度跟随字号（36pt 对应 50，保持原来的默认观感），避免大字号时相邻轨道重叠、小字号时过于稀疏
    private static func trackHeight(for size: DanmuSize) -> CGFloat {
        (size.size * 50 / 36).rounded()
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

    /// 底栏「弹幕」按钮：显示开关和常用弹幕设置都在这里，改了立即生效并保存为默认值；图标随开关状态变化
    func addMenuItems(current: inout [UIMenuElement]) -> [UIMenuElement] {
        let isShowing = Defaults.shared.showDanmu
        // 刷新底栏，让按钮图标和下次打开时的勾选反映最新状态
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

        // 子菜单标题里不放当前值：已展示的上一级菜单不会刷新，写进标题会显示旧值，当前值只用勾选表示
        let durationMenu = Self.choiceMenu(title: "展示时长", image: "timer",
                                           options: [4.0, 6.0, 8.0], current: Settings.danmuDuration,
                                           label: { "\(Int($0)) 秒" })
        { duration in
            // 只影响之后发出的弹幕
            Settings.danmuDuration = duration
            refreshMenus()
        }
        let alphaMenu = Self.choiceMenu(title: "不透明度", image: "circle.lefthalf.filled",
                                        options: Array(DanmuAlpha.allCases.reversed()), current: Settings.danmuAlpha,
                                        label: \.title)
        { [weak self] alpha in
            Settings.danmuAlpha = alpha
            // 透明度在绘制时读取，让屏上已有的弹幕也重绘一次
            self?.danMuView.subviews.forEach { $0.layer.setNeedsDisplay() }
            refreshMenus()
        }
        let areaMenu = Self.choiceMenu(title: "显示区域", image: "rectangle.tophalf.filled",
                                       options: DanmuArea.allCases.sorted { $0.percent < $1.percent },
                                       current: Settings.danmuArea, label: \.title)
        { [weak self] area in
            Settings.danmuArea = area
            // displayArea 的 didSet 会重算轨道，超出新区域的弹幕随轨道一起移除
            self?.danMuView.displayArea = area.percent
            refreshMenus()
        }
        let sizeMenu = Self.choiceMenu(title: "字号", image: "textformat.size",
                                       options: DanmuSize.allCases, current: Settings.danmuSize,
                                       label: \.title)
        { [weak self] size in
            // 字号只影响之后发出的弹幕；轨道高度随之调整
            Settings.danmuSize = size
            guard let self else {
                refreshMenus()
                return
            }
            let height = Self.trackHeight(for: size)
            if height != danMuView.trackHeight {
                // 屏上弹幕保留旧字号，轨道间距变了会和相邻轨道重叠（暂停时会一直叠着），
                // 所以先清掉，之后发出的弹幕按新字号和新轨道显示
                danMuView.clean()
                danMuView.trackHeight = height
            }
            refreshMenus()
        }
        let levelMenu = Self.choiceMenu(title: "智能屏蔽", image: "shield.lefthalf.filled",
                                        options: DanmuAIShield.allCases, current: DanmuAIShield.current,
                                        label: \.title)
        { shield in
            // 过滤在发出弹幕时进行，对之后的弹幕立即生效
            Settings.danmuAILevel = shield.rawValue
            refreshMenus()
        }

        let menu = UIMenu(title: "弹幕",
                          image: UIImage(systemName: isShowing ? "list.bullet.rectangle.fill" : "list.bullet.rectangle"),
                          identifier: PlayerMenu.danmu,
                          children: [toggleAction, durationMenu, alphaMenu, areaMenu, sizeMenu, levelMenu])
        return [menu]
    }

    /// 单选子菜单。选中后同步改兄弟项的勾选，因为已展示的菜单不会因重建而刷新
    private static func choiceMenu<T: Equatable>(title: String,
                                                 image: String,
                                                 options: [T],
                                                 current: T,
                                                 label: (T) -> String,
                                                 onSelect: @escaping (T) -> Void) -> UIMenu
    {
        // 弱引用表，避免 action → handler → 表 → action 的循环引用
        let siblings = NSHashTable<UIAction>.weakObjects()
        let actions = options.map { option in
            UIAction(title: label(option), state: option == current ? .on : .off) { action in
                for sibling in siblings.allObjects {
                    sibling.state = .off
                }
                action.state = .on
                onSelect(option)
            }
        }
        actions.forEach { siblings.add($0) }
        return UIMenu(title: title,
                      image: UIImage(systemName: image),
                      options: .singleSelection,
                      children: actions)
    }
}
