//
//  LaunchAccountPickerViewController.swift
//  BilibiliLive
//
//  冷启动且登录了两个及以上账号时的「谁在观看」：一排头像，焦点默认停在上次使用的账号，
//  按确认即以该账号进入首页；末尾是「添加账号」。可在设置「启动时选择账号」中关闭。
//

import Kingfisher
import SnapKit
import UIKit

final class LaunchAccountPickerViewController: UIViewController {
    /// 选定账号（已设为当前账号）后回调，由外部负责进入首页
    var onAccountChosen: (() -> Void)?

    private let accounts: [AccountManager.Account]
    private let activeMID: Int?

    private let backdropView: UIImageView = {
        let view = UIImageView(image: UIImage(named: "LoginBackdrop"))
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }()

    private let shadeLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        let base = UIColor(red: 10 / 255, green: 14 / 255, blue: 24 / 255, alpha: 1)
        layer.colors = [base.withAlphaComponent(0.45).cgColor, base.withAlphaComponent(0.8).cgColor]
        return layer
    }()

    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let layout = UICollectionViewFlowLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private var hasChosen = false

    init() {
        accounts = AccountManager.shared.accounts
        activeMID = AccountManager.shared.activeAccount?.profile.mid
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark

        view.addSubview(backdropView)
        backdropView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        view.layer.addSublayer(shadeLayer)

        titleLabel.text = "谁在观看？"
        titleLabel.font = UIFont.systemFont(ofSize: 64, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(view.snp.centerY).offset(-190)
        }

        layout.scrollDirection = .horizontal
        layout.itemSize = LaunchAccountCell.size
        layout.minimumLineSpacing = 60
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(LaunchAccountCell.self, forCellWithReuseIdentifier: LaunchAccountCell.reuseID)
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.centerY.equalToSuperview().offset(30)
            make.height.equalTo(LaunchAccountCell.size.height)
        }

        hintLabel.text = "可在「设置 › 启动时选择账号」中关闭"
        hintLabel.font = BLFont.subtitle
        hintLabel.textColor = BLGlass.Color.secondaryText
        hintLabel.textAlignment = .center
        view.addSubview(hintLabel)
        hintLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().inset(90)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        shadeLayer.frame = view.bounds
        // 账号少时整排居中，多了则从左侧留白开始横向滚动
        let count = CGFloat(accounts.count + 1)
        let contentWidth = count * layout.itemSize.width + (count - 1) * layout.minimumLineSpacing
        let side = max(120, (view.bounds.width - contentWidth) / 2)
        if layout.sectionInset.left != side {
            layout.sectionInset = UIEdgeInsets(top: 0, left: side, bottom: 0, right: side)
            layout.invalidateLayout()
        }
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [collectionView]
    }

    private func choose(_ account: AccountManager.Account) {
        guard !hasChosen else { return }
        hasChosen = true
        if account.profile.mid != activeMID {
            AccountManager.shared.setActiveAccount(account)
        }
        onAccountChosen?()
    }
}

extension LaunchAccountPickerViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    private func isAddItem(_ indexPath: IndexPath) -> Bool {
        indexPath.item >= accounts.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        accounts.count + 1
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: LaunchAccountCell.reuseID, for: indexPath) as! LaunchAccountCell
        if isAddItem(indexPath) {
            cell.configureAdd()
        } else {
            cell.configure(with: accounts[indexPath.item])
        }
        return cell
    }

    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        // 默认停在上次使用的账号
        let index = accounts.firstIndex { $0.profile.mid == activeMID } ?? 0
        return IndexPath(item: index, section: 0)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if isAddItem(indexPath) {
            AppDelegate.shared.showLogin()
        } else {
            choose(accounts[indexPath.item])
        }
    }
}

/// 启动选择页的一项：大圆形头像 + 名字；聚焦时放大，名字变亮
private final class LaunchAccountCell: BLMotionCollectionViewCell {
    static let reuseID = "LaunchAccountCell"
    static let avatarSize: CGFloat = 200
    static let size = CGSize(width: 240, height: 290)

    private let avatarView = UIImageView()
    private let addBackground = BLGlass.makeView(cornerRadius: avatarSize / 2)
    private let addIconView = UIImageView(image: UIImage(systemName: "plus"))
    private let nameLabel = UILabel()
    private let vipBadge = VipBadgeView(fontSize: 20)

    override func setup() {
        super.setup()
        scaleFactor = 1.12

        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = Self.avatarSize / 2
        avatarView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        contentView.addSubview(avatarView)
        avatarView.snp.makeConstraints { make in
            make.top.centerX.equalToSuperview()
            make.width.height.equalTo(Self.avatarSize)
        }

        contentView.addSubview(addBackground)
        addBackground.snp.makeConstraints { make in
            make.edges.equalTo(avatarView)
        }
        addIconView.tintColor = .white
        addIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 64, weight: .semibold)
        addBackground.contentView.addSubview(addIconView)
        addIconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        // 大会员标识压在头像底边上，不占额外高度
        contentView.addSubview(vipBadge)
        vipBadge.snp.makeConstraints { make in
            make.centerX.equalTo(avatarView)
            make.centerY.equalTo(avatarView.snp.bottom).offset(-6)
            make.width.lessThanOrEqualTo(avatarView)
        }

        nameLabel.font = BLFont.listItem
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.top.equalTo(avatarView.snp.bottom).offset(28)
            make.leading.trailing.equalToSuperview()
        }
        updateAppearance()
    }

    func configure(with account: AccountManager.Account) {
        addBackground.isHidden = true
        avatarView.isHidden = false
        nameLabel.text = account.profile.username
        vipBadge.configure(with: account.profile.vip)
        if let url = URL(string: account.profile.avatar), !account.profile.avatar.isEmpty {
            avatarView.contentMode = .scaleAspectFill
            avatarView.kf.setImage(with: url,
                                   options: [.processor(DownsamplingImageProcessor(size: CGSize(width: Self.avatarSize * 2, height: Self.avatarSize * 2))),
                                             .cacheOriginalImage])
        } else {
            avatarView.contentMode = .center
            avatarView.tintColor = UIColor.white.withAlphaComponent(0.8)
            avatarView.image = UIImage(systemName: "person.fill",
                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 80, weight: .regular))
        }
    }

    func configureAdd() {
        avatarView.kf.cancelDownloadTask()
        avatarView.image = nil
        avatarView.isHidden = true
        vipBadge.configure(with: nil)
        addBackground.isHidden = false
        nameLabel.text = "添加账号"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.kf.cancelDownloadTask()
        avatarView.image = nil
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.updateAppearance()
        }
    }

    private func updateAppearance() {
        nameLabel.textColor = isFocused ? .white : BLGlass.Color.secondaryText
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = isFocused ? 0.35 : 0
        layer.shadowRadius = 24
        layer.shadowOffset = CGSize(width: 0, height: 16)
    }
}
