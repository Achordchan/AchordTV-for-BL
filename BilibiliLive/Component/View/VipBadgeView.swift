//
//  VipBadgeView.swift
//  BilibiliLive
//
//  大会员标识 Chip：粉色圆角底 + 白字（如「年度大会员」）。非大会员时隐藏。
//

import UIKit

final class VipBadgeView: UIView {
    static let pink = UIColor(red: 0.98, green: 0.45, blue: 0.60, alpha: 1)

    private let label = UILabel()

    init(fontSize: CGFloat = 22) {
        super.init(frame: .zero)
        backgroundColor = Self.pink
        layer.cornerCurve = .continuous
        clipsToBounds = true
        label.font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        let vertical = fontSize * 0.3
        let horizontal = fontSize * 0.6
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: vertical),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vertical),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontal),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontal),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    /// 传入账号资料；有效大会员时显示服务端标签文案，否则隐藏
    func configure(with vip: AccountManager.VipInfo?) {
        if let vip, vip.isActive {
            label.text = vip.displayName
            isHidden = false
        } else {
            label.text = nil
            isHidden = true
        }
    }
}
