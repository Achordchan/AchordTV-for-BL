//
//  BLFont.swift
//  BilibiliLive
//
//  全局字号规则（单位 pt，Apple TV 逻辑分辨率 1920×1080，观看距离约 3 米）。
//  新界面一律从这里取字号，不再直接写 systemFont(ofSize:)。
//
//  层级          字号   字重        用途
//  pageTitle     52     bold       页面大标题：视频详情标题、弹窗标题、「导航栏排序」等
//  sectionTitle  34     semibold   分区标题：Feed 分组标题、设置分组、个人页区块标题
//  listItem      30     regular    列表与菜单行：侧边栏、设置行、按钮文字
//  body          28     regular    正文：简介、评论、说明文字
//  cardTitle     24     semibold   视频卡片标题（4 列）；3 列大卡 26，侧边栏窄卡 22
//  groupLabel    24     semibold   分组小标题：设置分组名、排序页分栏名（配次要色）
//  subtitle      22     regular    次要信息：UP 主、日期、播放量
//  caption       20     regular    封面角标、卡片 UP 主行等最小文字，不再往下用
//

import UIKit

enum BLFont {
    static let pageTitle = UIFont.systemFont(ofSize: 52, weight: .bold)
    static let sectionTitle = UIFont.systemFont(ofSize: 34, weight: .semibold)
    static let listItem = UIFont.systemFont(ofSize: 30, weight: .regular)
    static let listItemEmphasized = UIFont.systemFont(ofSize: 30, weight: .semibold)
    static let body = UIFont.systemFont(ofSize: 28, weight: .regular)
    static let cardTitle = UIFont.systemFont(ofSize: 24, weight: .semibold)
    static let cardTitleLarge = UIFont.systemFont(ofSize: 26, weight: .semibold)
    static let cardTitleCompact = UIFont.systemFont(ofSize: 22, weight: .semibold)
    static let groupLabel = UIFont.systemFont(ofSize: 24, weight: .semibold)
    static let subtitle = UIFont.systemFont(ofSize: 22, weight: .regular)
    static let caption = UIFont.systemFont(ofSize: 20, weight: .regular)
}
