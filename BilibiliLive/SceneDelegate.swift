//
//  SceneDelegate.swift
//  BilibiliLive
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window

        #if DEBUG
            // 调试：tvOS 模拟器无法用命令切换外观，设置 FORCE_LIGHT=1 强制浅色以检查浅色外观
            if ProcessInfo.processInfo.environment["FORCE_LIGHT"] == "1" {
                window.overrideUserInterfaceStyle = .light
            }
            // 调试：设置环境变量 LOGIN_PREVIEW_PHASE 时直接展示登录页对应状态，不影响已登录账号
            if ProcessInfo.processInfo.environment["LOGIN_PREVIEW_PHASE"] != nil {
                window.rootViewController = LoginViewController.create()
                window.makeKeyAndVisible()
                return
            }
            // 调试：设置 PLAYER_OVERLAY_PREVIEW=1 时直接展示播放页浮层预览（白 / 黑 / 亮色画面）
            if ProcessInfo.processInfo.environment["PLAYER_OVERLAY_PREVIEW"] == "1" {
                window.rootViewController = PlayerOverlayPreviewViewController()
                window.makeKeyAndVisible()
                return
            }
        #endif

        if ApiRequest.isLogin() {
            if Settings.chooseAccountOnLaunch, AccountManager.shared.accounts.count >= 2 {
                // 多账号冷启动：先选账号，选定后再刷新该账号的 token 并进入首页
                let picker = LaunchAccountPickerViewController()
                picker.onAccountChosen = { [weak self] in
                    Self.refreshTokenIfNeeded()
                    self?.replaceRootViewController(with: BLTabBarViewController(), animated: true)
                }
                window.rootViewController = picker
            } else {
                Self.refreshTokenIfNeeded()
                window.rootViewController = BLTabBarViewController()
            }
        } else {
            window.rootViewController = LoginViewController.create()
        }
        window.makeKeyAndVisible()
    }

    /// 当前账号的 token 30 小时内过期（或没有过期时间）时刷新
    private static func refreshTokenIfNeeded() {
        if let expireDate = ApiRequest.getToken()?.expireDate {
            if expireDate.timeIntervalSince(Date()) < 60 * 60 * 30 {
                ApiRequest.refreshToken()
            }
        } else {
            ApiRequest.refreshToken()
        }
    }

    func showLogin() {
        replaceRootViewController(with: LoginViewController.create(), animated: false)
    }

    func showTabBar() {
        replaceRootViewController(with: BLTabBarViewController(), animated: false)
    }

    func resetTabBar() {
        replaceRootViewController(with: BLTabBarViewController(), animated: true)
    }

    private func replaceRootViewController(with viewController: UIViewController, animated: Bool) {
        guard let window else { return }
        if animated, let snapshot = window.snapshotView(afterScreenUpdates: false) {
            window.rootViewController = viewController
            window.makeKeyAndVisible()
            viewController.view.addSubview(snapshot)
            UIView.animate(withDuration: 0.25, animations: {
                snapshot.alpha = 0
            }, completion: { _ in
                snapshot.removeFromSuperview()
            })
        } else {
            window.rootViewController = viewController
            window.makeKeyAndVisible()
        }
    }
}
