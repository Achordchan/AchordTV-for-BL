//
//  FollowUpsBarHeaderView.swift
//  BilibiliLive
//
//  关注页视频上方的 UP 主横排：第一个是「全部」，后面是关注的 UP 主，向右滚动时继续加载。
//  选中某个 UP 主后，下方只显示该 UP 主的视频。
//

import Kingfisher
import SnapKit
import UIKit

final class FollowUpsBarHeaderView: UICollectionReusableView {
    /// 选中某个 UP 主（nil 表示「全部」）
    var onSelect: ((Int?) -> Void)?
    /// 横排滚到末尾，需要加载更多关注
    var onReachEnd: (() -> Void)?

    var leadingInset: CGFloat = 30 {
        didSet {
            guard leadingInset != oldValue else { return }
            layout.sectionInset = UIEdgeInsets(top: 0, left: leadingInset, bottom: 0, right: leadingInset)
        }
    }

    private var users = [WebRequest.FollowingUser]()
    private var selectedMid: Int?

    private let layout = UICollectionViewFlowLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

    override init(frame: CGRect) {
        super.init(frame: frame)
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 130, height: 150)
        layout.minimumLineSpacing = 20
        layout.sectionInset = UIEdgeInsets(top: 0, left: leadingInset, bottom: 0, right: leadingInset)

        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.register(FollowUpChipCell.self, forCellWithReuseIdentifier: FollowUpChipCell.reuseID)
        collectionView.dataSource = self
        collectionView.delegate = self
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(150)
            make.bottom.equalToSuperview().inset(30)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 更新 UP 主列表与当前选中项；追加数据时只插入新增项，避免打断正在横排里的焦点
    func update(users newUsers: [WebRequest.FollowingUser], selectedMid newSelectedMid: Int?) {
        let oldCount = users.count
        let shownCount = collectionView.numberOfItems(inSection: 0)
        let selectionChanged = selectedMid != newSelectedMid
        users = newUsers
        selectedMid = newSelectedMid

        if newUsers.count > oldCount, shownCount == oldCount + 1 {
            let added = (oldCount..<newUsers.count).map { IndexPath(item: $0 + 1, section: 0) }
            collectionView.insertItems(at: added)
        } else if newUsers.count != oldCount || shownCount != newUsers.count + 1 {
            collectionView.reloadData()
        }

        if selectionChanged {
            for case let cell as FollowUpChipCell in collectionView.visibleCells {
                guard let indexPath = collectionView.indexPath(for: cell) else { continue }
                cell.isCurrent = mid(at: indexPath) == selectedMid
            }
        }
    }

    private func mid(at indexPath: IndexPath) -> Int? {
        indexPath.item == 0 ? nil : users[indexPath.item - 1].mid
    }
}

extension FollowUpsBarHeaderView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        users.count + 1
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FollowUpChipCell.reuseID, for: indexPath) as! FollowUpChipCell
        if indexPath.item == 0 {
            cell.configureAll()
        } else {
            let user = users[indexPath.item - 1]
            cell.configure(name: user.uname, avatar: user.face)
        }
        cell.isCurrent = mid(at: indexPath) == selectedMid
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(mid(at: indexPath))
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if indexPath.item >= users.count - 4 {
            onReachEnd?()
        }
    }
}

/// UP 主横排里的一项：圆形头像 + 名字；当前选中的头像外加一圈白环
final class FollowUpChipCell: BLMotionCollectionViewCell {
    static let reuseID = "FollowUpChipCell"

    private static let avatarSize: CGFloat = 88

    private let ringView = UIView()
    private let avatarView = UIImageView()
    private let allIconView = UIImageView(image: UIImage(systemName: "square.grid.2x2.fill"))
    private let allBackground = BLGlass.makeView(cornerRadius: avatarSize / 2, border: false)
    private let nameLabel = UILabel()

    var isCurrent = false {
        didSet { updateAppearance() }
    }

    override func setup() {
        super.setup()
        scaleFactor = 1.12

        ringView.layer.cornerRadius = (Self.avatarSize + 12) / 2
        ringView.layer.borderWidth = 3
        ringView.layer.borderColor = UIColor.white.cgColor
        contentView.addSubview(ringView)
        ringView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.width.height.equalTo(Self.avatarSize + 12)
        }

        contentView.addSubview(allBackground)
        allBackground.snp.makeConstraints { make in
            make.center.equalTo(ringView)
            make.width.height.equalTo(Self.avatarSize)
        }
        allIconView.tintColor = .white
        allIconView.contentMode = .scaleAspectFit
        allIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        allBackground.contentView.addSubview(allIconView)
        allIconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = Self.avatarSize / 2
        contentView.addSubview(avatarView)
        avatarView.snp.makeConstraints { make in
            make.center.equalTo(ringView)
            make.width.height.equalTo(Self.avatarSize)
        }

        nameLabel.font = BLFont.subtitle
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.top.equalTo(ringView.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview()
        }
        updateAppearance()
    }

    func configureAll() {
        avatarView.kf.cancelDownloadTask()
        avatarView.image = nil
        avatarView.isHidden = true
        allBackground.isHidden = false
        nameLabel.text = "全部"
    }

    func configure(name: String, avatar: URL) {
        avatarView.isHidden = false
        allBackground.isHidden = true
        nameLabel.text = name
        avatarView.kf.setImage(with: avatar,
                               options: [.processor(DownsamplingImageProcessor(size: CGSize(width: Self.avatarSize * 2, height: Self.avatarSize * 2))),
                                         .cacheOriginalImage])
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
        ringView.isHidden = !isCurrent
        let highlighted = isCurrent || isFocused
        nameLabel.textColor = highlighted ? BLGlass.Color.text : BLGlass.Color.secondaryText
        nameLabel.font = isCurrent ? UIFont.systemFont(ofSize: 22, weight: .semibold) : BLFont.subtitle
    }
}
