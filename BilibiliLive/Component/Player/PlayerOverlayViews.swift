//
//  PlayerOverlayViews.swift
//  BilibiliLive
//
//  直接叠在视频画面上的提示视图：右下角状态胶囊、中心「正在加载」提示。
//  画面内容不可控（可能是纯白），这些视图的底板必须在亮、暗画面上都能托住白字。
//

import SnapKit
import UIKit

/// 右下角状态胶囊：传输方式（直连 / 多 CDN 加速）+ 实时速度 / 已缓冲
final class PlaybackStatusChipView: UIView {
    private let backgroundView: UIVisualEffectView
    private let modeIconView = UIImageView()
    private let modeLabel = UILabel()
    private let separatorView = UIView()
    private let speedIconView = UIImageView(image: UIImage(systemName: "arrow.down"))
    private let speedLabel = UILabel()

    /// `background` 仅供 DEBUG 预览对比旧材质使用，正常使用默认值
    init(background: UIVisualEffectView = BLGlass.makeVideoOverlayView(cornerRadius: 32)) {
        backgroundView = background
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(backgroundView)
        backgroundView.snp.makeConstraints { $0.edges.equalToSuperview() }

        let secondary = BLGlass.Color.secondaryText
        modeIconView.tintColor = .white
        modeIconView.contentMode = .scaleAspectFit
        modeIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        modeLabel.font = UIFont.systemFont(ofSize: 21, weight: .medium)
        modeLabel.textColor = .white

        separatorView.backgroundColor = UIColor(white: 1, alpha: 0.25)
        separatorView.snp.makeConstraints { make in
            make.width.equalTo(1.5)
            make.height.equalTo(20)
        }

        speedIconView.tintColor = secondary
        speedIconView.contentMode = .scaleAspectFit
        speedIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        speedLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 21, weight: .regular)
        speedLabel.textColor = secondary
        // 文字下垫一层很淡的阴影，亮画面边缘处再多一点对比
        for label in [modeLabel, speedLabel] {
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.25
            label.layer.shadowRadius = 2
            label.layer.shadowOffset = .zero
        }

        let modeStack = UIStackView(arrangedSubviews: [modeIconView, modeLabel])
        modeStack.spacing = 8
        modeStack.alignment = .center
        let speedStack = UIStackView(arrangedSubviews: [speedIconView, speedLabel])
        speedStack.spacing = 6
        speedStack.alignment = .center
        let stack = UIStackView(arrangedSubviews: [modeStack, separatorView, speedStack])
        stack.spacing = 14
        stack.alignment = .center
        backgroundView.contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(26)
            make.centerY.equalToSuperview()
        }
        snp.makeConstraints { $0.height.equalTo(64) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(icon: String?, mode: String?, speed: String) {
        modeIconView.image = icon.flatMap { UIImage(systemName: $0) }
        modeIconView.isHidden = icon == nil
        modeLabel.text = mode
        modeLabel.isHidden = mode == nil
        separatorView.isHidden = mode == nil
        speedLabel.text = speed
    }
}

/// 画面中心、系统转圈下方的「正在加载 · 速度」提示
final class PlaybackLoadingView: UIView {
    private let backgroundView: UIVisualEffectView
    private let label = UILabel()

    /// `background` 仅供 DEBUG 预览对比旧材质使用，正常使用默认值
    init(background: UIVisualEffectView = BLGlass.makeVideoOverlayView(cornerRadius: 20)) {
        backgroundView = background
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(backgroundView)
        backgroundView.snp.makeConstraints { $0.edges.equalToSuperview() }
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .medium)
        label.textColor = .white
        backgroundView.contentView.addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(18)
            make.centerY.equalToSuperview()
        }
        snp.makeConstraints { $0.height.equalTo(40) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var text: String? {
        get { label.text }
        set { label.text = newValue }
    }
}
