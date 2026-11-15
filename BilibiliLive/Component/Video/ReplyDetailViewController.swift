//
// Created by Yam on 2024/6/9.
//

import Alamofire
import Kingfisher
import SnapKit
import UIKit

class ReplyDetailViewController: UIViewController {
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var replyLabel: UIButton!
    private var replyCollectionView: UICollectionView!
    private var replyCollectionHeight: Constraint?
    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let metaLabel = UILabel()
    private let repliesTitleLabel = UILabel()

    private static let listSpacing: CGFloat = 30
    private static let listInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 60, trailing: 0)
    private var imageStackView: UIStackView!
    private var buttonStackView: UIStackView!

    private let reply: Replys.Reply

    init(reply: Replys.Reply) {
        self.reply = reply
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setUpViews()
        avatarView.kf.setImage(with: URL(string: reply.member.avatar),
                               options: [.processor(DownsamplingImageProcessor(size: CGSize(width: 120, height: 120))), .cacheOriginalImage])
        nameLabel.text = reply.member.uname
        metaLabel.text = reply.likeAndTimeText
        let subReplyCount = reply.replies?.count ?? 0
        repliesTitleLabel.text = subReplyCount > 0 ? "回复（\(subReplyCount)）" : nil
        repliesTitleLabel.isHidden = subReplyCount == 0
        replyLabel.setTitle(reply.content.message, for: .normal)
        replyLabel.setTitleColor(UIColor.label, for: .normal)
        if let attr = reply.createAttributedString(displayView: replyLabel) {
            replyLabel.setAttributedTitle(attr, for: .normal)
        }

        reply.content.pictures?.compactMap { URL(string: $0.img_src) }.forEach { url in
            let imageView = UIImageView()
            imageView.kf.setImage(with: url)
            imageView.contentMode = .scaleAspectFit
            imageView.snp.makeConstraints { make in
                make.height.lessThanOrEqualTo(500)
            }
            imageStackView.addArrangedSubview(imageView)
        }

        reply.content.jump_url?.forEach { url, jump in
            Task {
                guard let bvId = await ReplyUrlBVParser.parser(url: url) else { return }
                let button = BLCustomTextButton()
                button.title = jump.title
                button.onPrimaryAction = { [weak self] _ in
                    self?.jumpLink(bvid: bvId)
                }
                buttonStackView.addArrangedSubview(button)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let height = ReplyCardCell.listHeight(for: reply.replies ?? [],
                                              width: replyCollectionView.bounds.width,
                                              spacing: Self.listSpacing,
                                              insets: Self.listInsets)
        replyCollectionHeight?.update(offset: height)
    }

    // MARK: - Private

    private func jumpLink(bvid: String) {
        let aid = BvidConvertor.bv2av(bvid: bvid)
        let detailVC = VideoDetailViewController.create(aid: Int(aid), cid: nil)
        detailVC.present(from: self)
    }

    private func setUpViews() {
        scrollView = {
            let scroll = UIScrollView()
            view.addSubview(scroll)
            scroll.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
            return scroll
        }()

        contentView = {
            let view = UIView()
            scrollView.addSubview(view)
            view.snp.makeConstraints { make in
                make.edges.equalToSuperview()
                make.width.equalToSuperview()
            }
            return view
        }()

        titleLabel = {
            let label = UILabel()
            contentView.addSubview(label)
            label.font = BLFont.pageTitle
            label.text = "评论"

            label.snp.makeConstraints { make in
                make.centerX.equalToSuperview()
                make.top.equalToSuperview().offset(20)
            }

            return label
        }()

        // 楼主：头像 + 昵称
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 30
        nameLabel.font = BLFont.listItemEmphasized
        nameLabel.textColor = BLGlass.Color.text
        let authorStack = UIStackView(arrangedSubviews: [avatarView, nameLabel])
        authorStack.axis = .horizontal
        authorStack.alignment = .center
        authorStack.spacing = 16
        contentView.addSubview(authorStack)
        avatarView.snp.makeConstraints { make in
            make.width.height.equalTo(60)
        }
        authorStack.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(50)
            make.leading.equalTo(contentView.snp.leadingMargin)
            make.trailing.lessThanOrEqualTo(contentView.snp.trailingMargin)
        }

        replyLabel = {
            let label = UIButton()
            contentView.addSubview(label)
            label.titleLabel?.numberOfLines = 0
            label.titleLabel?.textAlignment = .left
            label.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            label.contentHorizontalAlignment = .left
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            label.snp.makeConstraints { make in
                make.top.equalTo(authorStack.snp.bottom).offset(24)
                make.leading.equalTo(contentView.snp.leadingMargin)
                make.trailing.equalTo(contentView.snp.trailingMargin)
            }
            label.titleLabel?.snp.makeConstraints { make in
                make.top.bottom.equalToSuperview()
            }

            return label
        }()

        // 楼主：点赞数 · 时间
        let likeIcon = UIImageView(image: UIImage(systemName: "hand.thumbsup"))
        likeIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        likeIcon.tintColor = BLGlass.Color.secondaryText
        likeIcon.contentMode = .scaleAspectFit
        metaLabel.font = BLFont.subtitle
        metaLabel.textColor = BLGlass.Color.secondaryText
        let metaStack = UIStackView(arrangedSubviews: [likeIcon, metaLabel])
        metaStack.axis = .horizontal
        metaStack.alignment = .center
        metaStack.spacing = 10
        contentView.addSubview(metaStack)
        metaStack.snp.makeConstraints { make in
            make.top.equalTo(replyLabel.snp.bottom).offset(20)
            make.leading.equalTo(contentView.snp.leadingMargin)
            make.trailing.lessThanOrEqualTo(contentView.snp.trailingMargin)
        }

        imageStackView = {
            let stackView = UIStackView()
            stackView.axis = .horizontal
            stackView.distribution = .fillEqually
            stackView.spacing = 10
            contentView.addSubview(stackView)

            stackView.snp.makeConstraints { make in
                make.top.equalTo(metaStack.snp.bottom).offset(40)
                make.leading.equalTo(contentView.snp.leadingMargin)
                make.trailing.equalTo(contentView.snp.trailingMargin)
            }
            return stackView
        }()

        buttonStackView = {
            let stackView = UIStackView()
            stackView.axis = .horizontal
            stackView.alignment = .leading
            stackView.spacing = 10
            stackView.distribution = .equalSpacing
            contentView.addSubview(stackView)
            stackView.snp.makeConstraints { make in
                make.top.equalTo(self.imageStackView.snp.bottom).offset(60)
                make.leading.equalTo(contentView.snp.leadingMargin)
                make.trailing.lessThanOrEqualTo(contentView.snp.trailingMargin)
            }
            return stackView
        }()

        // 楼中楼：与详情页「热门评论」相同的卡片，一行一条
        repliesTitleLabel.font = BLFont.sectionTitle
        repliesTitleLabel.textColor = BLGlass.Color.text
        contentView.addSubview(repliesTitleLabel)
        repliesTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(buttonStackView.snp.bottom).offset(60)
            make.leading.equalTo(contentView.snp.leadingMargin)
        }

        replyCollectionView = {
            let replies = reply.replies ?? []
            let layout = ReplyCardCell.makeListLayout(spacing: Self.listSpacing, insets: Self.listInsets) { replies }
            let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
            contentView.addSubview(collectionView)
            collectionView.dataSource = self
            collectionView.delegate = self
            ReplyCardCell.configureEmbedded(collectionView)

            collectionView.snp.makeConstraints { make in
                make.leading.equalTo(contentView.snp.leadingMargin)
                make.trailing.equalTo(contentView.snp.trailingMargin)
                make.top.equalTo(repliesTitleLabel.snp.bottom).offset(24)
                replyCollectionHeight = make.height.equalTo(0).constraint
                make.bottom.equalToSuperview()
            }

            return collectionView
        }()
    }
}

extension ReplyDetailViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return reply.replies?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ReplyCardCell.reuseID, for: indexPath) as? ReplyCardCell else {
            fatalError("cell not found")
        }

        guard let reply = reply.replies?[indexPath.row] else {
            fatalError("reply not found")
        }

        cell.config(reply: reply)

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let reply = reply.replies?[indexPath.item] else { return }
        let detail = ReplyDetailViewController(reply: reply)
        present(detail, animated: true)
    }
}

enum ReplyUrlBVParser {
    static func parser(url: String) async -> String? {
        if url.hasPrefix("BV"), url.count == 12 {
            return url
        }

        if url.hasPrefix("https://www.bilibili.com/video/") {
            guard let urlComponents = URLComponents(string: url)
            else { return nil }
            let path = urlComponents.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let bvid = path.split(separator: "/").filter({ !$0.isEmpty }).last {
                return await parser(url: String(bvid))
            }
            return nil
        }

        // need to get 302 for real url
        if url.hasPrefix("https://b23.tv/") {
            if let realUrl = await AF.request(url, method: .head).serializingData().response.response?.url {
                return await parser(url: realUrl.absoluteString)
            }
        }

        return nil
    }
}
