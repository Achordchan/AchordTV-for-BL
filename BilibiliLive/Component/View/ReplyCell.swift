//
// Created by Yam on 2024/6/9.
//

import Kingfisher
import SnapKit
import UIKit

class ReplyCell: UICollectionViewCell {
    class var identifier: String {
        return String(describing: Self.self)
    }

    @IBOutlet var avatarImageView: UIImageView!
    @IBOutlet var userNameLabel: UILabel!
    @IBOutlet var contenLabel: UILabel!

    func config(replay: Replys.Reply) {
        avatarImageView.kf.setImage(
            with: URL(string: replay.member.avatar),
            options: [
                .processor(DownsamplingImageProcessor(size: CGSize(width: 80, height: 80))),
                .processor(RoundCornerImageProcessor(radius: .widthFraction(0.5))),
                .cacheSerializer(FormatIndicatedCacheSerializer.png),
            ]
        )
        userNameLabel.text = replay.member.uname
        if let attr = replay.createAttributedString(displayView: contenLabel) {
            contenLabel.attributedText = attr
        } else {
            contenLabel.text = replay.content.message
        }
    }
}

/// 详情页「热门评论」卡片：一行一条，头像 + 昵称、正文（最多 3 行）、点赞时间；高度由 height(for:width:) 算出；玻璃底，聚焦白底
final class ReplyCardCell: BLMotionCollectionViewCell {
    static let reuseID = "ReplyCardCell"

    private let glassView = BLGlass.makeView(cornerRadius: 20)
    private let focusFillView = UIView()
    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let contentLabel = UILabel()
    private let likeIconView = UIImageView(image: UIImage(systemName: "hand.thumbsup"))
    private let metaLabel = UILabel()

    override func setup() {
        super.setup()
        scaleFactor = 1.02

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
        avatarView.layer.cornerRadius = 18
        nameLabel.font = BLFont.groupLabel
        nameLabel.lineBreakMode = .byTruncatingTail

        let header = UIStackView(arrangedSubviews: [avatarView, nameLabel])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12
        avatarView.snp.makeConstraints { make in
            make.width.height.equalTo(36)
        }

        contentLabel.font = Self.contentFont
        contentLabel.numberOfLines = Self.maxLines
        contentLabel.lineBreakMode = .byTruncatingTail
        contentLabel.textAlignment = .natural

        likeIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        likeIconView.contentMode = .scaleAspectFit
        metaLabel.font = BLFont.caption
        let footer = UIStackView(arrangedSubviews: [likeIconView, metaLabel])
        footer.axis = .horizontal
        footer.alignment = .center
        footer.spacing = 8

        glassView.contentView.addSubview(header)
        glassView.contentView.addSubview(contentLabel)
        glassView.contentView.addSubview(footer)
        footer.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.trailing.lessThanOrEqualToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(20)
        }
        header.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(24)
            make.trailing.lessThanOrEqualToSuperview().inset(24)
        }
        contentLabel.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.lessThanOrEqualTo(footer.snp.top).offset(-16)
        }
        updateAppearance()
    }

    private static let contentFont = UIFont.systemFont(ofSize: 26)
    private static let maxLines = 3

    /// 按正文实际行数算出卡片高度（与 setup 里的约束一一对应），避免依赖自适应布局
    static func height(for reply: Replys.Reply, width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - 48)
        let rect = (reply.content.message as NSString).boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                                                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                                    attributes: [.font: contentFont],
                                                                    context: nil)
        let lineHeight = ceil(contentFont.lineHeight)
        let lines = min(maxLines, max(1, Int(ceil(rect.height / contentFont.lineHeight - 0.01))))
        // 带表情时每行按表情图高度（36）留空间
        let hasEmote = !(reply.content.emote?.isEmpty ?? true)
        let perLine = hasEmote ? max(lineHeight, 40) : lineHeight
        let header: CGFloat = 24 + 36 + 16
        let footer: CGFloat = 16 + 24 + 20
        return ceil(header + CGFloat(lines) * perLine + footer)
    }

    func config(reply: Replys.Reply) {
        avatarView.kf.setImage(with: URL(string: reply.member.avatar),
                               options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 72, height: 72))), .cacheOriginalImage])
        nameLabel.text = reply.member.uname
        metaLabel.text = reply.likeAndTimeText
        contentLabel.font = Self.contentFont
        if let attr = reply.createAttributedString(displayView: contentLabel) {
            contentLabel.attributedText = attr
        } else {
            contentLabel.text = reply.content.message
        }
        updateAppearance()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarView.kf.cancelDownloadTask()
        avatarView.image = nil
        contentLabel.attributedText = nil
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.updateAppearance()
        }
    }

    private func updateAppearance() {
        focusFillView.isHidden = !isFocused
        nameLabel.textColor = isFocused ? UIColor(white: 0, alpha: 0.55) : BLGlass.Color.secondaryText
        contentLabel.textColor = isFocused ? BLGlass.Color.focusedText : BLGlass.Color.text
        let metaColor = isFocused ? UIColor(white: 0, alpha: 0.5) : BLGlass.Color.secondaryText
        metaLabel.textColor = metaColor
        likeIconView.tintColor = metaColor
    }
}

extension Replys.Reply {
    /// 「136  ·  5天前」；没有点赞时显示「赞」
    var likeAndTimeText: String {
        let likeText = (like ?? 0) > 0 ? like!.numberString() : "赞"
        return [likeText, DateFormatter.relativeTimeStringFor(timestamp: ctime)]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
    }
}

extension ReplyCardCell {
    /// 一行一条的评论列表：卡片高度由 height(for:width:) 逐条算出，列表本身不滚动，交给外层页面滚动
    static func makeListLayout(spacing: CGFloat,
                               insets: NSDirectionalEdgeInsets,
                               replies: @escaping () -> [Replys.Reply]) -> UICollectionViewLayout
    {
        UICollectionViewCompositionalLayout { _, environment in
            let width = environment.container.effectiveContentSize.width - insets.leading - insets.trailing
            var heights = replies().map { height(for: $0, width: width) }
            if heights.isEmpty { heights = [1] }
            let items = heights.map {
                NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                                          heightDimension: .absolute($0)))
            }
            let total = heights.reduce(0, +) + CGFloat(heights.count - 1) * spacing
            let group = NSCollectionLayoutGroup.vertical(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                                                            heightDimension: .absolute(total)),
                                                         subitems: items)
            group.interItemSpacing = .fixed(spacing)
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = insets
            return section
        }
    }

    /// 与 makeListLayout 对应的列表总高度（width 为 collection view 宽度）
    static func listHeight(for replies: [Replys.Reply], width: CGFloat, spacing: CGFloat, insets: NSDirectionalEdgeInsets) -> CGFloat {
        guard !replies.isEmpty else { return 0 }
        let cardWidth = width - insets.leading - insets.trailing
        let heights = replies.map { height(for: $0, width: cardWidth) }
        return heights.reduce(0, +) + CGFloat(heights.count - 1) * spacing + insets.top + insets.bottom
    }

    /// 配置为嵌在页面里的评论列表：不自身滚动、不自动加安全区内边距
    static func configureEmbedded(_ collectionView: UICollectionView) {
        collectionView.register(ReplyCardCell.self, forCellWithReuseIdentifier: reuseID)
        collectionView.clipsToBounds = false
        collectionView.isScrollEnabled = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.backgroundColor = .clear
    }
}
