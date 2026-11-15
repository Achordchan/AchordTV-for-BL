//
//  BLSettingLineCollectionViewCell.swift
//  BilibiliLive
//
//  Created by yicheng on 2022/10/29.
//

import UIKit

/// 侧边栏菜单行：玻璃底板；当前选中项提亮并加粗，聚焦时为系统白底。
/// 可选左侧 SF Symbol 图标；`isDestructive` 用于登出这类危险操作。
class BLSettingLineCollectionViewCell: BLMotionCollectionViewCell {
    let effectView = BLGlass.makeView(cornerRadius: 16)
    let selectedWhiteView = UIView()
    let titleLabel = UILabel()
    private let iconView = UIImageView()
    private let stackView = UIStackView()

    var isDestructive = false {
        didSet { updateView() }
    }

    override var isSelected: Bool {
        didSet {
            updateView()
        }
    }

    override func setup() {
        super.setup()
        scaleFactor = 1.05
        contentView.addSubview(effectView)
        effectView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        selectedWhiteView.isHidden = true
        effectView.contentView.addSubview(selectedWhiteView)
        selectedWhiteView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)
        iconView.isHidden = true
        iconView.snp.makeConstraints { make in
            make.width.equalTo(36)
        }

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 18
        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(titleLabel)
        effectView.contentView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(28)
            make.trailing.lessThanOrEqualToSuperview().offset(-20)
            make.top.bottom.equalToSuperview().inset(8)
        }
        titleLabel.textAlignment = .left
        updateView()
    }

    /// 设置标题与可选图标（SF Symbol 名称）
    func configure(title: String, icon: String? = nil, destructive: Bool = false) {
        titleLabel.text = title
        iconView.image = icon.flatMap { UIImage(systemName: $0) }
        iconView.isHidden = icon == nil
        isDestructive = destructive
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configure(title: "")
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.updateView()
        }
    }

    func updateView() {
        let textColor: UIColor
        if isFocused {
            selectedWhiteView.isHidden = false
            selectedWhiteView.backgroundColor = BLGlass.Color.focusedFill
            textColor = isDestructive ? BLGlass.Color.destructiveOnLight : BLGlass.Color.focusedText
            titleLabel.font = BLFont.listItemEmphasized
        } else if isSelected {
            selectedWhiteView.isHidden = false
            selectedWhiteView.backgroundColor = BLGlass.Color.selectedFill
            textColor = BLGlass.Color.text
            titleLabel.font = BLFont.listItemEmphasized
        } else {
            selectedWhiteView.isHidden = true
            textColor = isDestructive ? BLGlass.Color.destructive : BLGlass.Color.secondaryText
            titleLabel.font = BLFont.listItem
        }
        titleLabel.textColor = textColor
        iconView.tintColor = textColor
    }

    static func makeLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.9),
                                              heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .absolute(70))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize,
                                                       subitems: [item])
        group.edgeSpacing = .init(leading: nil, top: .fixed(10), trailing: nil, bottom: nil)
        let section = NSCollectionLayoutSection(group: group)
        let layout = UICollectionViewCompositionalLayout(section: section)
        return layout
    }
}
