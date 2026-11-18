//
//  PlayerOverlayPreviewViewController.swift
//  BilibiliLive
//
//  仅 DEBUG：模拟器无法登录播放时，用纯白 / 纯黑 / 亮色渐变三种「画面」直接渲染播放页浮层，
//  方便截图检查可读性。启动时设置环境变量 PLAYER_OVERLAY_PREVIEW=1 进入。
//

#if DEBUG
    import SnapKit
    import UIKit

    final class PlayerOverlayPreviewViewController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            let panels: [UIView] = [
                makeSolidPanel(.white),
                makeSolidPanel(.black),
                makeGradientPanel(),
            ]
            let row = UIStackView(arrangedSubviews: panels)
            row.distribution = .fillEqually
            view.addSubview(row)
            row.snp.makeConstraints { $0.edges.equalToSuperview() }

            for panel in panels {
                fill(panel)
            }
        }

        /// 每个画面里自上而下：修改前的胶囊 / 加载提示（原 BLGlass.makeView 材质）、修改后的同一组视图、两张连播卡片
        private func fill(_ panel: UIView) {
            let column = UIStackView()
            column.axis = .vertical
            column.alignment = .center
            column.spacing = 18
            panel.addSubview(column)
            column.snp.makeConstraints { make in
                make.top.equalToSuperview().inset(40)
                make.leading.trailing.equalToSuperview().inset(20)
            }

            column.addArrangedSubview(makeTag("修改前"))
            let oldChip = PlaybackStatusChipView(background: BLGlass.makeView(cornerRadius: 32))
            oldChip.update(icon: "bolt.fill", mode: "多 CDN 加速 · 3 个节点", speed: "12.4 MB/s  ·  已缓冲 38 秒")
            column.addArrangedSubview(oldChip)
            let oldLoading = PlaybackLoadingView(background: BLGlass.makeView(cornerRadius: 20, border: false))
            oldLoading.text = "正在加载  ·  3.2 MB/s"
            column.addArrangedSubview(oldLoading)

            column.setCustomSpacing(34, after: oldLoading)
            column.addArrangedSubview(makeTag("修改后"))
            let chip = PlaybackStatusChipView()
            chip.update(icon: "bolt.fill", mode: "多 CDN 加速 · 3 个节点", speed: "12.4 MB/s  ·  已缓冲 38 秒")
            column.addArrangedSubview(chip)
            let directChip = PlaybackStatusChipView()
            directChip.update(icon: "network", mode: "直连", speed: "860 KB/s")
            column.addArrangedSubview(directChip)
            let loading = PlaybackLoadingView()
            loading.text = "正在加载  ·  3.2 MB/s"
            column.addArrangedSubview(loading)

            column.setCustomSpacing(30, after: loading)
            let episode = AutoplayTransitionCardView()
            episode.configure(AutoplayTransition(kind: .nextEpisode,
                                                 title: "第4话 夏日祭与烟火大会",
                                                 subtitle: "某番剧 第二季",
                                                 coverURL: Self.previewCoverURL(hue: 0.95)))
            episode.setPhase(.upcoming)
            column.addArrangedSubview(episode)
            episode.snp.makeConstraints { $0.width.equalTo(600) }

            let related = AutoplayTransitionCardView()
            related.configure(AutoplayTransition(kind: .recommended,
                                                 title: "用一台 Apple TV 搭建家庭影院：从布线到调色的完整流程分享",
                                                 subtitle: "某 UP 主",
                                                 coverURL: Self.previewCoverURL(hue: 0.55)))
            related.setPhase(.playing)
            column.addArrangedSubview(related)
            related.snp.makeConstraints { $0.width.equalTo(600) }
        }

        private func makeTag(_ text: String) -> UIView {
            let label = UILabel()
            label.text = "  \(text)  "
            label.font = UIFont.systemFont(ofSize: 18, weight: .bold)
            label.textColor = .white
            label.backgroundColor = UIColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1)
            label.layer.cornerRadius = 6
            label.clipsToBounds = true
            return label
        }

        /// 生成一张本地渐变图当封面（预览不走网络）
        private static func previewCoverURL(hue: CGFloat) -> URL? {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("overlay-preview-\(Int(hue * 100)).png")
            let size = CGSize(width: 448, height: 252)
            let image = UIGraphicsImageRenderer(size: size).image { ctx in
                let colors = [UIColor(hue: hue, saturation: 0.6, brightness: 0.95, alpha: 1).cgColor,
                              UIColor(hue: hue + 0.08, saturation: 0.8, brightness: 0.45, alpha: 1).cgColor]
                let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 1])!
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            guard let data = image.pngData(), (try? data.write(to: url)) != nil else { return nil }
            return url
        }

        private func makeSolidPanel(_ color: UIColor) -> UIView {
            let view = UIView()
            view.backgroundColor = color
            return view
        }

        /// 亮色、多色的「画面」：天空蓝 → 白 → 暖黄，模拟明亮的实拍画面
        private func makeGradientPanel() -> UIView {
            let view = GradientView()
            view.gradient.colors = [
                UIColor(red: 0.55, green: 0.80, blue: 1.0, alpha: 1).cgColor,
                UIColor(white: 0.97, alpha: 1).cgColor,
                UIColor(red: 1.0, green: 0.85, blue: 0.45, alpha: 1).cgColor,
            ]
            view.gradient.startPoint = CGPoint(x: 0.5, y: 0)
            view.gradient.endPoint = CGPoint(x: 0.5, y: 1)
            return view
        }

        private final class GradientView: UIView {
            override class var layerClass: AnyClass { CAGradientLayer.self }
            var gradient: CAGradientLayer { layer as! CAGradientLayer }
        }
    }
#endif
