//
//  FeedCollectionViewCell.swift
//  BilibiliLive
//
//  Created by yicheng on 2022/10/20.
//

import Kingfisher
import MarqueeLabel
import SnapKit
import TVUIKit
import UIKit

class FeedCollectionViewCell: BLMotionCollectionViewCell {
    var onLongPress: (() -> Void)?
    var styleOverride: FeedDisplayStyle? { didSet { if oldValue != styleOverride { updateStyle() } }}

    private let titleLabel = MarqueeLabel()
    private let upLabel = UILabel()
    private let imageView = UIImageView()
    private let infoView = UIView()
    private let avatarView = UIImageView()
    private let overlayView = BLOverlayView()
    private var avatarSizeConstraint: Constraint?

    override func setup() {
        super.setup()
        let longpress = UILongPressGestureRecognizer(target: self, action: #selector(actionLongPress(sender:)))
        addGestureRecognizer(longpress)

        contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.trailing.equalToSuperview()
            make.top.equalToSuperview()
            make.height.equalTo(imageView.snp.width).multipliedBy(9.0 / 16)
        }
        imageView.layer.cornerRadius = 12
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill

        contentView.addSubview(overlayView)
        overlayView.snp.makeConstraints { make in
            make.leading.equalTo(imageView.snp.leading)
            make.trailing.equalTo(imageView.snp.trailing)
            make.bottom.equalTo(imageView.snp.bottom)
            make.top.equalTo(imageView.snp.top)
        }
        overlayView.layer.cornerRadius = imageView.layer.cornerRadius
        overlayView.clipsToBounds = true

        // 信息区：封面下留 16pt 呼吸距离；标题独占一行，头像缩小后与 UP 主、日期并排放在第二行
        contentView.addSubview(infoView)
        infoView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(imageView.snp.bottom).offset(16)
        }

        infoView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        titleLabel.holdScrolling = true
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleLabel.fadeLength = 60

        let metaStack = UIStackView(arrangedSubviews: [avatarView, upLabel])
        metaStack.axis = .horizontal
        metaStack.alignment = .center
        metaStack.spacing = 10
        infoView.addSubview(metaStack)
        metaStack.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.equalToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
            // 信息区高度由内容决定，行高随之收紧
            make.bottom.equalToSuperview().priority(.high)
        }

        avatarView.backgroundColor = .clear
        avatarView.contentMode = .scaleAspectFill
        avatarView.snp.makeConstraints { make in
            avatarSizeConstraint = make.width.height.equalTo(28).constraint
        }
        avatarView.setContentHuggingPriority(.required, for: .horizontal)
        avatarView.setContentCompressionResistancePriority(.required, for: .horizontal)

        upLabel.setContentHuggingPriority(.required, for: .vertical)
        upLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        upLabel.textColor = UIColor(named: "titleColor")?.withAlphaComponent(0.7)
        upLabel.lineBreakMode = .byTruncatingTail
    }

    func setup(data: any DisplayData) {
        titleLabel.text = data.title
        if let overlay = data.overlay {
            overlayView.isHidden = false
            overlayView.configure(overlay)
        } else {
            overlayView.isHidden = true
        }
        upLabel.text = [data.ownerName, data.date].compactMap({ $0 }).joined(separator: " · ")
        if var pic = data.pic {
            if pic.scheme == nil {
                pic = URL(string: "http:\(pic.absoluteString)")!
            }
            imageView.kf.setImage(with: pic, options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 360, height: 202))), .cacheOriginalImage])
        }
        if let avatar = data.avatar(size: 240) {
            avatarView.isHidden = false
            avatarView.kf.setImage(with: avatar, options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 80, height: 80))), .processor(RoundCornerImageProcessor(radius: .widthFraction(0.5))), .cacheSerializer(FormatIndicatedCacheSerializer.png)])
        } else {
            avatarView.isHidden = true
        }
        updateStyle()
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        if isFocused {
            startScroll()
        } else {
            stopScroll()
        }
    }

    private func startScroll() {
        titleLabel.restartLabel()
        titleLabel.holdScrolling = false
    }

    private func stopScroll() {
        titleLabel.shutdownLabel()
        titleLabel.holdScrolling = true
    }

    private func updateStyle() {
        let style = styleOverride ?? Settings.displayStyle
        titleLabel.font = style.titleFont
        upLabel.font = style.upFont
        avatarSizeConstraint?.update(offset: style.avatarSize)
    }

    @objc private func actionLongPress(sender: UILongPressGestureRecognizer) {
        guard sender.state == .began else { return }
        onLongPress?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onLongPress = nil
        avatarView.image = nil
        stopScroll()
    }
}

extension FeedDisplayStyle {
    var fractionalWidth: CGFloat {
        switch self {
        case .large, .sideBar:
            return 0.33
        case .normal:
            return 0.25
        }
    }

    var fractionalHeight: CGFloat {
        switch self {
        case .large:
            return fractionalWidth / 1.5
        case .normal:
            return fractionalWidth / 1.5
        case .sideBar:
            return fractionalWidth / 1.15
        }
    }

    var heightEstimated: CGFloat {
        switch self {
        case .large:
            return 516
        case .normal, .sideBar:
            return 380
        }
    }

    var titleFont: UIFont {
        switch self {
        case .large:
            return BLFont.cardTitleLarge
        case .normal:
            return BLFont.cardTitle
        case .sideBar:
            return BLFont.cardTitleCompact
        }
    }

    var upFont: UIFont {
        switch self {
        case .large:
            return BLFont.subtitle
        case .normal:
            return BLFont.caption
        case .sideBar:
            return UIFont.systemFont(ofSize: 18)
        }
    }

    /// 第二行小头像尺寸，与 UP 主那行文字等高
    var avatarSize: CGFloat {
        switch self {
        case .large:
            return 30
        case .normal:
            return 28
        case .sideBar:
            return 24
        }
    }
}
