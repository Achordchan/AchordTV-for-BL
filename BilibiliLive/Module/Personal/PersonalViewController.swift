//
//  PersonalViewController.swift
//  BilibiliLive
//
//  Created by yicheng on 2022/8/20.
//

import Kingfisher
import SnapKit
import UIKit

/// 「我的」页：左侧依次是账号卡、我的内容、通用设置和登出，右侧显示选中的内容页。
class PersonalViewController: UIViewController, BLTabBarContentVCProtocol {
    struct CellModel {
        let title: String
        var icon: String? = nil
        var isDestructive = false
        /// 获得焦点时是否自动切换右侧内容（只对内容页生效）
        var autoSelect: Bool? = true
        var contentVC: UIViewController? = nil
        var action: (() -> Void)? = nil
    }

    private struct SectionModel {
        enum Kind {
            case profile
            case list
        }

        let kind: Kind
        let title: String?
        var items: [CellModel]
    }

    private enum Layout {
        static let sidebarWidth: CGFloat = 480
        static let sidebarLeading: CGFloat = 60
        static let rowHeight: CGFloat = 62
        static let profileHeight: CGFloat = 120
    }

    static func create() -> PersonalViewController {
        return PersonalViewController()
    }

    private let contentView = UIView()

    private lazy var leftCollectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.register(BLSettingLineCollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.register(PersonalProfileCell.self, forCellWithReuseIdentifier: PersonalProfileCell.reuseID)
        collectionView.register(PersonalSectionHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: PersonalSectionHeaderView.reuseID)
        collectionView.delegate = self
        collectionView.dataSource = self
        return collectionView
    }()

    weak var currentViewController: UIViewController?
    private var sections = [SectionModel]()
    /// 当前右侧展示的内容页所在位置；动作行（切换账号、登出等）不会改变它
    private var contentIndexPath: IndexPath?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupData()
        leftCollectionView.reloadData()
        selectDefaultContent()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAccountUpdate),
                                               name: AccountManager.didUpdateNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleTabBarPagesDidChange),
                                               name: .tabBarPagesDidChange,
                                               object: nil)
        AccountManager.shared.refreshActiveAccountProfile()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Data

    func setupData() {
        sections.removeAll()

        let profile = CellModel(title: "切换账号", autoSelect: false, action: { [weak self] in
            self?.presentAccountSwitcher()
        })
        sections.append(SectionModel(kind: .profile, title: nil, items: [profile]))

        let contentItems = Settings.personalPages.compactMap { makeCellModel(for: $0) }
        if !contentItems.isEmpty {
            sections.append(SectionModel(kind: .list, title: "我的内容", items: contentItems))
        }

        let setting = CellModel(title: "设置", icon: "gearshape", contentVC: SettingsViewController())
        let logout = CellModel(title: "登出", icon: "rectangle.portrait.and.arrow.right", isDestructive: true, autoSelect: false) { [weak self] in
            self?.actionLogout()
        }
        sections.append(SectionModel(kind: .list, title: "通用", items: [setting, logout]))
    }

    private func makeCellModel(for page: TabBarPage) -> CellModel? {
        let vc = TabBarPageVCFactory.createVC(for: page)
        if page.requirePresentInPersonalPage {
            // 需要全屏打开的页面不随焦点自动打开
            return CellModel(title: page.title, icon: page.iconName, autoSelect: false) { [weak self] in
                self?.present(vc, animated: true)
            }
        }
        return CellModel(title: page.title, icon: page.iconName, contentVC: vc)
    }

    private func model(at indexPath: IndexPath) -> CellModel {
        sections[indexPath.section].items[indexPath.item]
    }

    /// 默认打开第一个内容页；没有内容页时打开设置
    private func selectDefaultContent() {
        for (s, section) in sections.enumerated() {
            for (i, item) in section.items.enumerated() where item.contentVC != nil {
                showContent(at: IndexPath(item: i, section: s))
                return
            }
        }
    }

    private func showContent(at indexPath: IndexPath) {
        guard let vc = model(at: indexPath).contentVC else { return }
        contentIndexPath = indexPath
        leftCollectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        if currentViewController !== vc {
            setViewController(vc: vc)
        }
    }

    func setViewController(vc: UIViewController) {
        currentViewController?.willMove(toParent: nil)
        currentViewController?.view.removeFromSuperview()
        currentViewController?.removeFromParent()

        currentViewController = vc
        addChild(vc)
        contentView.addSubview(vc.view)
        vc.view.makeConstraintsToBindToSuperview()
        vc.didMove(toParent: self)
    }

    func reloadData() {
        (currentViewController as? BLTabBarContentVCProtocol)?.reloadData()
    }

    // MARK: Actions

    private func presentAccountSwitcher() {
        let controller = AccountSwitcherViewController()
        controller.modalPresentationStyle = .overFullScreen
        present(controller, animated: true)
    }

    func actionLogout() {
        let alert = UIAlertController(title: "确定登出？", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "登出", style: .destructive) {
            _ in
            WebRequest.logout {
                ApiRequest.logout { hasRemainingAccount in
                    if hasRemainingAccount {
                        AccountManager.shared.refreshActiveAccountProfile()
                    } else {
                        AppDelegate.shared.showLogin()
                    }
                }
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func handleAccountUpdate() {
        guard let profileSection = sections.firstIndex(where: { $0.kind == .profile }) else { return }
        let indexPath = IndexPath(item: 0, section: profileSection)
        if let cell = leftCollectionView.cellForItem(at: indexPath) as? PersonalProfileCell {
            cell.configure(with: AccountManager.shared.activeAccount, accountCount: AccountManager.shared.accounts.count)
        }
    }

    @objc private func handleTabBarPagesDidChange() {
        setupData()
        leftCollectionView.reloadData()
        selectDefaultContent()
    }

    // MARK: Layout

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, _ in
            guard let self else { return nil }
            let kind = self.sections[sectionIndex].kind
            let height = kind == .profile ? Layout.profileHeight : Layout.rowHeight
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 10

            if self.sections[sectionIndex].title != nil {
                let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(56))
                let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize,
                                                                         elementKind: UICollectionView.elementKindSectionHeader,
                                                                         alignment: .top)
                section.boundarySupplementaryItems = [header]
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 28, trailing: 0)
            } else {
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0)
            }
            return section
        }
    }

    private func setupUI() {
        view.addSubview(leftCollectionView)
        view.addSubview(contentView)

        leftCollectionView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.sidebarLeading)
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(10)
            make.bottom.equalToSuperview()
            make.width.equalTo(Layout.sidebarWidth)
        }

        contentView.snp.makeConstraints { make in
            make.leading.equalTo(leftCollectionView.snp.trailing).offset(40)
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.trailing.bottom.equalToSuperview()
        }
    }
}

extension PersonalViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if sections[indexPath.section].kind == .profile {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PersonalProfileCell.reuseID, for: indexPath) as! PersonalProfileCell
            cell.configure(with: AccountManager.shared.activeAccount, accountCount: AccountManager.shared.accounts.count)
            return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! BLSettingLineCollectionViewCell
        let model = model(at: indexPath)
        cell.configure(title: model.title, icon: model.icon, destructive: model.isDestructive)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: PersonalSectionHeaderView.reuseID, for: indexPath) as! PersonalSectionHeaderView
        header.label.text = sections[indexPath.section].title
        return header
    }
}

extension PersonalViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let model = model(at: indexPath)
        if model.contentVC != nil {
            showContent(at: indexPath)
        } else if let contentIndexPath {
            // 动作行不保留选中态，恢复到当前内容页
            collectionView.selectItem(at: contentIndexPath, animated: false, scrollPosition: [])
        }
        model.action?()
    }

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        guard Settings.sideMenuAutoSelectChange,
              let next = context.nextFocusedIndexPath,
              model(at: next).autoSelect != false,
              model(at: next).contentVC != nil
        else { return }
        showContent(at: next)
    }
}

// MARK: - Profile cell

/// 账号卡：头像 + 昵称 + 「切换账号」提示，选中后打开账号切换
final class PersonalProfileCell: BLMotionCollectionViewCell {
    static let reuseID = "PersonalProfileCell"

    private let glassView = BLGlass.makeView(cornerRadius: 24)
    private let focusFillView = UIView()
    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let hintLabel = UILabel()
    private let chevronView = UIImageView(image: UIImage(systemName: "chevron.right"))

    override func setup() {
        super.setup()
        scaleFactor = 1.04

        contentView.addSubview(glassView)
        glassView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        focusFillView.backgroundColor = BLGlass.Color.focusedFill
        focusFillView.isHidden = true
        glassView.contentView.addSubview(focusFillView)
        focusFillView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 40
        avatarView.tintColor = BLGlass.Color.secondaryText
        glassView.contentView.addSubview(avatarView)
        avatarView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(24)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(80)
        }

        nameLabel.font = BLFont.sectionTitle
        nameLabel.lineBreakMode = .byTruncatingTail
        hintLabel.font = BLFont.subtitle

        let textStack = UIStackView(arrangedSubviews: [nameLabel, hintLabel])
        textStack.axis = .vertical
        textStack.spacing = 6
        glassView.contentView.addSubview(textStack)

        chevronView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        chevronView.contentMode = .scaleAspectFit
        glassView.contentView.addSubview(chevronView)
        chevronView.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-24)
            make.centerY.equalToSuperview()
        }

        textStack.snp.makeConstraints { make in
            make.leading.equalTo(avatarView.snp.trailing).offset(22)
            make.trailing.lessThanOrEqualTo(chevronView.snp.leading).offset(-16)
            make.centerY.equalToSuperview()
        }
        updateAppearance()
    }

    func configure(with account: AccountManager.Account?, accountCount: Int) {
        guard let account else {
            nameLabel.text = "未登录"
            hintLabel.text = "登录账号"
            avatarView.image = UIImage(systemName: "person.crop.circle.fill")
            return
        }
        nameLabel.text = account.profile.username
        hintLabel.text = accountCount > 1 ? "切换账号 · 共 \(accountCount) 个" : "切换或添加账号"
        if let url = URL(string: account.profile.avatar), !account.profile.avatar.isEmpty {
            avatarView.kf.setImage(with: url, options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 176, height: 176))), .cacheOriginalImage])
        } else {
            avatarView.image = UIImage(systemName: "person.crop.circle.fill")
        }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.updateAppearance()
        }
    }

    private func updateAppearance() {
        focusFillView.isHidden = !isFocused
        nameLabel.textColor = isFocused ? BLGlass.Color.focusedText : BLGlass.Color.text
        hintLabel.textColor = isFocused ? UIColor(white: 0, alpha: 0.55) : BLGlass.Color.secondaryText
        chevronView.tintColor = isFocused ? UIColor(white: 0, alpha: 0.45) : BLGlass.Color.secondaryText
    }
}

// MARK: - Section header

final class PersonalSectionHeaderView: UICollectionReusableView {
    static let reuseID = "PersonalSectionHeaderView"
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = BLFont.groupLabel
        label.textColor = BLGlass.Color.pageSecondaryText
        addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(8)
            make.bottom.equalToSuperview().offset(-14)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class EmptyViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let label = UILabel()
        label.text = "Nothing Here"
        view.addSubview(label)
        label.makeConstraintsBindToCenterOfSuperview()
    }
}

extension TabBarPage {
    /// 「我的」页与相关列表使用的 SF Symbol 图标
    var iconName: String {
        switch self {
        case .live: return "dot.radiowaves.left.and.right"
        case .feed: return "house"
        case .tvRecommend: return "sparkles.tv"
        case .hot: return "flame"
        case .ranking: return "chart.bar"
        case .follows: return "heart.text.square"
        case .favorite: return "star"
        case .personal: return "person.crop.circle"
        case .search: return "magnifyingglass"
        case .followBangumi: return "tv"
        case .followUps: return "person.2"
        case .toView: return "clock"
        case .history: return "clock.arrow.circlepath"
        case .weeklyWatch: return "calendar"
        }
    }
}
