//
//  SettingsViewController.swift
//  BilibiliLive
//
//  Created by whw on 2022/10/19.
//

import UIKit

class SettingsViewController: UIViewController {
    class SectionModel: Hashable, Equatable {
        let title: String
        let items: [CellModel]

        init(title: String, @ArrayBuilder<CellModel> items: () -> [CellModel]) {
            self.title = title
            self.items = items()
        }

        static func == (lhs: SectionModel, rhs: SectionModel) -> Bool {
            lhs.title == rhs.title && lhs.items == rhs.items
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(title)
            hasher.combine(items)
        }
    }

    class CellModel: Hashable, Equatable {
        let title: String
        let desp: () -> String
        let action: ((@escaping () -> Void) -> Void)?

        var updateAction: (() -> Void)?

        func hash(into hasher: inout Hasher) {
            hasher.combine(title)
        }

        static func == (lhs: CellModel, rhs: CellModel) -> Bool {
            lhs.title == rhs.title
        }

        init(title: String, desp: @autoclosure @escaping () -> String, action: ((@escaping () -> Void) -> Void)?) {
            self.title = title
            self.desp = desp
            self.action = action
        }
    }

    let collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { sectionIndex, environment -> NSCollectionLayoutSection? in
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(68))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(68))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
            group.interItemSpacing = .fixed(10)

            let section = NSCollectionLayoutSection(group: group)
            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(44)
            )

            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: "header",
                alignment: .top
            )
            header.pinToVisibleBounds = false
            section.boundarySupplementaryItems = [header]
            section.interGroupSpacing = 10
            return section
        }
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()

    var dataSource: UICollectionViewDiffableDataSource<SectionModel, CellModel>!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(collectionView)
        collectionView.remembersLastFocusedIndexPath = false
        collectionView.snp.makeConstraints { make in
            make.top.right.bottom.equalToSuperview()
            make.left.equalToSuperview().offset(20)
        }

        collectionView.delegate = self
        collectionView.register(SettingsSwitchCell.self, forCellWithReuseIdentifier: String(describing: SettingsSwitchCell.self))
        collectionView.register(SettingsHeaderView.self, forSupplementaryViewOfKind: "header", withReuseIdentifier: "HeaderView")

        configureDataSource()
        setupData()
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<SectionModel, CellModel>(collectionView: collectionView) { collectionView, indexPath, cellModel -> UICollectionViewCell? in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: SettingsSwitchCell.self), for: indexPath) as! SettingsSwitchCell
            cell.set(with: cellModel)
            return cell
        }
        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "HeaderView", for: indexPath) as! SettingsHeaderView
            let title = self?.dataSource.snapshot().sectionIdentifiers[indexPath.section].title ?? UUID().uuidString

            header.label.text = title
            return header
        }
    }

    private func setupData() {
        createSnapshot {
            SectionModel(title: "通用") {
                Toggle(title: "启用投屏", setting: Settings.enableDLNA, onChange: Settings.enableDLNA.toggle()) {
                    _ in
                    BiliBiliUpnpDMR.shared.start()
                }

                Toggle(title: "热门个性化推荐", setting: Settings.requestHotWithoutCookie, onChange: Settings.requestHotWithoutCookie.toggle())

                Toggle(title: "启动时选择账号",
                       setting: Settings.chooseAccountOnLaunch,
                       onChange: Settings.chooseAccountOnLaunch.toggle())
            }

            SectionModel(title: "界面") {
                Navigation(title: "导航栏排序", desp: "") { [weak self] in
                    let controller = TabBarCustomizationViewController()
                    controller.modalPresentationStyle = .overFullScreen
                    self?.present(controller, animated: true)
                }

                Actions(title: "视频每行显示个数", message: "重启app生效",
                        current: Settings.displayStyle.desp,
                        options: FeedDisplayStyle.allCases.filter({ !$0.hideInSetting }),
                        optionString: FeedDisplayStyle.allCases.filter({ !$0.hideInSetting }).map({ $0.desp }))
                {
                    Settings.displayStyle = $0
                }
                Toggle(title: "侧边栏菜单自动切换", setting: Settings.sideMenuAutoSelectChange, onChange: Settings.sideMenuAutoSelectChange.toggle())

                Toggle(title: "不显示详情页直接进入视频",
                       setting: Settings.direatlyEnterVideo,
                       onChange: Settings.direatlyEnterVideo.toggle())

                Actions(title: "视频详情相关推荐加载模式", message: "4k以上需要大会员",
                        current: Settings.showRelatedVideoInCurrentVC ? "页面刷新" : "新页面中打开",
                        options: [true, false],
                        optionString: ["页面刷新", "新页面中打开"])
                {
                    Settings.showRelatedVideoInCurrentVC = $0
                }
            }

            SectionModel(title: "推荐") {
                Toggle(title: "使用沉浸式浏览模式",
                       setting: Settings.recommendFeedFlowEnabled,
                       onChange: Settings.recommendFeedFlowEnabled.toggle())
                Actions(title: "沉浸式视频时长上限", message: "用于筛选沉浸式推荐中的短视频",
                        current: Settings.featuredDurationLimit.title,
                        options: FeaturedDurationLimit.allCases,
                        optionString: FeaturedDurationLimit.allCases.map { $0.title })
                {
                    Settings.featuredDurationLimit = $0
                }
                Toggle(title: "沉浸式推荐内容安全过滤",
                       setting: Settings.featuredContentSafetyFilterEnabled,
                       onChange: Settings.featuredContentSafetyFilterEnabled.toggle())
            }

            SectionModel(title: "关注页面") {
                Toggle(title: "关注刷视频模式",
                       setting: Settings.followsFeedFlowEnabled,
                       onChange: Settings.followsFeedFlowEnabled.toggle())
                { _ in
                    NotificationCenter.default.post(name: .followsLayoutModeDidChange, object: nil)
                }
            }

            SectionModel(title: "音视频") {
                Actions(title: "最高画质", message: Self.mediaQualityMessage(),
                        current: Settings.mediaQuality.currentDescription,
                        options: MediaQualityEnum.allCases,
                        optionString: MediaQualityEnum.allCases.map({ $0.desp }))
                {
                    Settings.mediaQuality = $0
                }
                Actions(title: "默认播放速度", message: "默认设置为1.0",
                        current: Settings.mediaPlayerSpeed.name,
                        options: PlaySpeed.blDefaults,
                        optionString: PlaySpeed.blDefaults.map({ $0.name }))
                {
                    Settings.mediaPlayerSpeed = $0
                }
                Toggle(title: "Avc优先(卡顿尝试开启)", setting: Settings.preferAvc, onChange: Settings.preferAvc.toggle())
                Actions(title: "多 CDN 并发加速",
                        message: "关闭（默认）：起播前测速，固定用最快的 CDN 直连，适合大多数网络。\n开启：把视频拆成小块，经本地代理同时从多个 CDN 下载，单个节点限速时可能更快；但每块多一次请求、要按顺序拼接，网络好或节点少时反而更慢。出错会自动回退直连。只对之后新打开的视频生效。",
                        current: Settings.multiCDNEnabled ? "开" : "关",
                        options: [false, true],
                        optionString: ["关闭（直连最快节点）", "开启（多节点并发）"])
                {
                    Settings.multiCDNEnabled = $0
                }
                Toggle(title: "无损音频和杜比全景声", setting: Settings.losslessAudio, onChange: Settings.losslessAudio.toggle())
                Toggle(title: "匹配视频内容", setting: Settings.contentMatch, onChange: Settings.contentMatch.toggle())
                Toggle(title: "仅在HDR视频匹配视频内容", setting: Settings.contentMatchOnlyInHDR, onChange: Settings.contentMatchOnlyInHDR.toggle())
            }

            SectionModel(title: "进度控制") {
                Toggle(title: "从上次退出的位置继续播放", setting: Settings.continuePlay, onChange: Settings.continuePlay.toggle())
                Toggle(title: "自动跳过片头片尾", setting: Settings.autoSkip, onChange: Settings.autoSkip.toggle())
                Toggle(title: "连续播放（分P/合集/番剧下一集）", setting: Settings.continouslyPlay, onChange: Settings.continouslyPlay.toggle())
                Toggle(title: "没有下一集时播放相关推荐", setting: Settings.continouslyPlayRelated, onChange: Settings.continouslyPlayRelated.toggle())
                Actions(title: "空降助手广告屏蔽", message: "",
                        current: Settings.enableSponsorBlock.title,
                        options: SponsorBlockType.allCases,
                        optionString: SponsorBlockType.allCases.map({ $0.title }))
                {
                    Settings.enableSponsorBlock = $0
                }
            }

            SectionModel(title: "弹幕") {
                Toggle(title: "用户自定义弹幕屏蔽", setting: Settings.enableDanmuFilter, onChange: Settings.enableDanmuFilter.toggle()) {
                    enable in
                    if enable {
                        Task {
                            let toast = await VideoDanmuFilter.shared.update()
                            let alert = UIAlertController(title: "同步结果", message: toast, preferredStyle: .alert)
                            alert.addAction(.init(title: "Ok", style: .cancel))
                            self.present(alert, animated: true)
                        }
                    }
                }
                Toggle(title: "移除重复弹幕", setting: Settings.enableDanmuRemoveDup, onChange: Settings.enableDanmuRemoveDup.toggle())
                Actions(title: "弹幕大小", message: "默认为36", current: Settings.danmuSize.title, options: DanmuSize.allCases, optionString: DanmuSize.allCases.map({ $0.title })) {
                    Settings.danmuSize = $0
                }
                Actions(title: "弹幕显示区域", message: "设置弹幕显示区域",
                        current: Settings.danmuArea.title,
                        options: DanmuArea.allCases,
                        optionString: DanmuArea.allCases.map({ $0.title }))
                {
                    Settings.danmuArea = $0
                }
                Actions(title: "弹幕展示时长", message: "一条滚动弹幕从出现到消失的时间，越短越快",
                        current: "\(Int(Settings.danmuDuration)) 秒",
                        options: [4.0, 6.0, 8.0],
                        optionString: ["4 秒", "6 秒", "8 秒"])
                {
                    Settings.danmuDuration = $0
                }
                Actions(title: "智能屏蔽", message: "按 B 站给每条弹幕的权重屏蔽低质量弹幕：轻度去掉权重最低的一档，中度去掉两档，强力只保留权重最高的弹幕（部分视频会只剩很少弹幕）",
                        current: DanmuAIShield.current.title,
                        options: DanmuAIShield.allCases,
                        optionString: DanmuAIShield.allCases.map(\.title))
                {
                    Settings.danmuAILevel = $0.rawValue
                }
                Toggle(title: "智能防档弹幕", setting: Settings.danmuMask, onChange: Settings.danmuMask.toggle())
                Toggle(title: "按需本地运算智能防档弹幕(Exp)", setting: Settings.vnMask, onChange: Settings.vnMask.toggle())

                // 添加弹幕透明度设置
                Actions(title: "弹幕不透明度", message: "100% 为完全不透明",
                        current: Settings.danmuAlpha.title,
                        options: DanmuAlpha.allCases,
                        optionString: DanmuAlpha.allCases.map({ $0.title }))
                { value in
                    Settings.danmuAlpha = value
                }

                // 添加弹幕描边宽度设置
                Actions(title: "弹幕描边宽度", message: "调整弹幕描边的粗细",
                        current: Settings.danmuStrokeWidth.title,
                        options: DanmuStrokeWidth.allCases,
                        optionString: DanmuStrokeWidth.allCases.map({ $0.title }))
                { value in
                    Settings.danmuStrokeWidth = value
                }

                // 添加弹幕描边透明度设置
                Actions(title: "弹幕描边不透明度", message: "0% 为不显示描边",
                        current: Settings.danmuStrokeAlpha.title,
                        options: DanmuStrokeAlpha.allCases,
                        optionString: DanmuStrokeAlpha.allCases.map({ $0.title }))
                { value in
                    Settings.danmuStrokeAlpha = value
                }
            }

            SectionModel(title: "港澳台解锁") {
                Toggle(title: "解锁港澳台番剧限制", setting: Settings.areaLimitUnlock, onChange: Settings.areaLimitUnlock.toggle())
                TextField(title: "设置港澳台解析服务器", message: "为了安全考虑建议自建服务器，公共服务器可用性难保证，请多尝试几个。\n公共服务器请参考：http://985.so/mjq9u", current: Settings.areaLimitCustomServer, placeholder: "api.example.com") {
                    Settings.areaLimitCustomServer = $0 ?? ""
                }
            }
        }
    }
}

extension SettingsViewController {
    func Toggle(title: String, setting: @autoclosure @escaping () -> Bool,
                onChange: @autoclosure @escaping () -> Void,
                extraAction: ((Bool) -> Void)? = nil) -> CellModel
    {
        return CellModel(title: title, desp: setting() ? "开" : "关") {
            update in
            onChange()
            extraAction?(setting())
            update()
        }
    }

    /// 最高画质弹窗说明：带上当前账号的大会员状态
    static func mediaQualityMessage() -> String {
        let vip = AccountManager.shared.activeAccount?.profile.vip
        let status: String
        if let vip, vip.isActive {
            var text = "当前账号：\(vip.displayName)"
            if let due = vip.dueDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                text += "（\(formatter.string(from: due)) 到期）"
            }
            status = text + "，可播放 4K / HDR / 杜比视界"
        } else {
            status = "当前账号不是大会员，1080p 高帧率及以上画质需要大会员"
        }
        return status + "\n「自动」：大会员按电视能力放开到 4K / HDR / 杜比视界，否则 1080p"
    }

    func Actions<T>(title: String,
                    message: String?,
                    current: @autoclosure @escaping () -> String,
                    options: [T],
                    optionString: [String],
                    onSelect: ((T) -> Void)? = nil) -> CellModel
    {
        return CellModel(title: title, desp: current()) { [weak self] update in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)

            for (idx, string) in optionString.enumerated() {
                let action = UIAlertAction(title: string, style: .default) { _ in
                    onSelect?(options[idx])
                    update()
                }
                alert.addAction(action)
            }
            let cancelAction = UIAlertAction(title: nil, style: .cancel)
            alert.addAction(cancelAction)
            self?.present(alert, animated: true)
        }
    }

    func TextField(title: String,
                   message: String?,
                   current: String,
                   placeholder: String?,
                   isSecureTextEntry: Bool = false,
                   onSubmit: ((String?) -> Void)? = nil) -> CellModel
    {
        return CellModel(title: title, desp: current) { [weak self] update in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addTextField { textField in
                textField.text = current
                textField.keyboardType = .URL
                textField.placeholder = placeholder
                textField.isSecureTextEntry = isSecureTextEntry
            }

            let action = UIAlertAction(title: "确定", style: .default) { _ in
                onSubmit?(alert.textFields![0].text)
                update()
            }
            alert.addAction(action)

            let cancelAction = UIAlertAction(title: nil, style: .cancel)
            alert.addAction(cancelAction)
            self?.present(alert, animated: true)
        }
    }

    func Navigation(title: String,
                    desp: @autoclosure @escaping () -> String,
                    onSelect: (() -> Void)? = nil) -> CellModel
    {
        return CellModel(title: title, desp: desp()) { update in
            onSelect?()
            update()
        }
    }
}

extension SettingsViewController: UICollectionViewDelegate {
    private func createSnapshot(@ArrayBuilder<SectionModel> builder: () -> [SectionModel]) {
        var snapshot = NSDiffableDataSourceSnapshot<SectionModel, CellModel>()
        for section in builder() {
            snapshot.appendSections([section])
            snapshot.appendItems(section.items, toSection: section)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let cellModel = dataSource.itemIdentifier(for: indexPath)!
        cellModel.action?() { [weak cellModel] in
            cellModel?.updateAction?()
        }
    }
}

class SettingsSwitchCell: BLMotionCollectionViewCell {
    private let glassView = BLGlass.makeView(cornerRadius: 16)
    private let titleLabel = UILabel()
    private let descLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(with model: SettingsViewController.CellModel) {
        titleLabel.text = model.title
        descLabel.text = model.desp()
        model.updateAction = { [weak self] in
            self?.descLabel.text = model.desp()
        }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        updateColor()
    }

    func setupView() {
        contentView.addSubview(glassView)
        glassView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        contentView.addSubview(titleLabel)
        contentView.addSubview(descLabel)
        titleLabel.font = BLFont.listItem
        descLabel.font = BLFont.body
        contentView.layer.cornerRadius = 16
        contentView.layer.cornerCurve = .continuous

        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(descLabel.snp.leading).offset(-10)
        }

        descLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-20)
            make.centerY.equalToSuperview()
        }

        descLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        updateColor()
    }

    func updateColor() {
        // 未聚焦：玻璃底板 + 浅色文字；聚焦：系统白底 + 深色文字
        glassView.isHidden = isFocused
        contentView.backgroundColor = isFocused ? BLGlass.Color.focusedFill : .clear
        titleLabel.textColor = isFocused ? BLGlass.Color.focusedText : BLGlass.Color.text
        descLabel.textColor = isFocused ? UIColor(white: 0, alpha: 0.55) : UIColor(white: 1, alpha: 0.6)
    }
}

class SettingsHeaderView: UICollectionReusableView {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup() {
        addSubview(label)
        label.font = BLFont.groupLabel
        label.textColor = BLGlass.Color.pageSecondaryText
        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.top.equalToSuperview().offset(20)
            make.bottom.equalToSuperview().offset(-20)
        }
    }
}

extension FeedDisplayStyle {
    var desp: String {
        switch self {
        case .large:
            return "3个"
        case .normal:
            return "4个"
        case .sideBar:
            return "-"
        }
    }
}
