//
//  LiveViewController.swift
//  BilibiliLive
//
//  Created by Etan Chen on 2021/3/28.
//

import Alamofire
import SwiftyJSON
import UIKit

class LiveViewController: CategoryViewController {
    override func viewDidLoad() {
        categories = [
            CategoryDisplayModel(title: "关注", contentVC: MyLiveViewController()),
            CategoryDisplayModel(title: "推荐", contentVC: AreaLiveViewController(areaID: -1)),
            CategoryDisplayModel(title: "人气", contentVC: AreaLiveViewController(areaID: 0)),
            CategoryDisplayModel(title: "娱乐", contentVC: AreaLiveViewController(areaID: 1)),
            CategoryDisplayModel(title: "虚拟主播", contentVC: AreaLiveViewController(areaID: 9)),
            CategoryDisplayModel(title: "网游", contentVC: AreaLiveViewController(areaID: 2)),
            CategoryDisplayModel(title: "手游", contentVC: AreaLiveViewController(areaID: 3)),
            CategoryDisplayModel(title: "单机", contentVC: AreaLiveViewController(areaID: 6)),
            CategoryDisplayModel(title: "生活", contentVC: AreaLiveViewController(areaID: 10)),
            CategoryDisplayModel(title: "电台", contentVC: AreaLiveViewController(areaID: 5)),
            CategoryDisplayModel(title: "知识", contentVC: AreaLiveViewController(areaID: 11)),
            CategoryDisplayModel(title: "赛事", contentVC: AreaLiveViewController(areaID: 13)),
        ]
        super.viewDidLoad()
    }
}

class MyLiveViewController: StandardVideoCollectionViewController<LiveRoom> {
    override func setupCollectionView() {
        super.setupCollectionView()
        collectionVC.styleOverride = .sideBar
        collectionVC.pageSize = 10
        reloadInterval = 15 * 60
    }

    override func request(page: Int) async throws -> [LiveRoom] {
        try await WebRequest.requestLiveRoom(page: page)
    }

    override func goDetail(with record: LiveRoom) {
        let playerVC = LivePlayerViewController()
        playerVC.room = record
        present(playerVC, animated: true, completion: nil)
    }
}

class AreaLiveViewController: StandardVideoCollectionViewController<AreaLiveRoom> {
    let areaID: Int
    init(areaID: Int) {
        self.areaID = areaID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setupCollectionView() {
        super.setupCollectionView()
        collectionVC.styleOverride = .sideBar
        collectionVC.pageSize = 10
        reloadInterval = 15 * 60
    }

    override func request(page: Int) async throws -> [AreaLiveRoom] {
        if areaID == 0 {
            return try await WebRequest.requestHotLiveRoom(page: page)
        } else if areaID == -1 {
            return try await WebRequest.requestRecommandLiveRoom(page: page)
        }
        return try await WebRequest.requestAreaLiveRoom(area: areaID, page: page)
    }

    override func goDetail(with record: AreaLiveRoom) {
        let playerVC = LivePlayerViewController()
        playerVC.room = record.toLiveRoom()
        present(playerVC, animated: true, completion: nil)
    }
}

struct LiveRoom: DisplayData, Codable {
    let title: String
    let room_id: Int
    let uname: String
    let area_v2_name: String
    let keyframe: String?
    let face: URL?
    let cover_from_user: URL?

    var ownerName: String { uname }
    var pic: URL? {
        if let keyframe {
            return URL(string: keyframe)
        }
        return nil
    }

    var avatar: URL? { face }

    var overlay: DisplayOverlay? {
        var leftItems = [DisplayOverlay.DisplayOverlayItem]()
        leftItems.append(DisplayOverlay.DisplayOverlayItem(icon: nil, text: area_v2_name))
        return DisplayOverlay(leftItems: leftItems)
    }
}

extension LiveRoom: PlayableData {
    var cid: Int { 0 }
    var aid: Int { 0 }
}

extension WebRequest.EndPoint {
    static let liveRoom = "https://api.live.bilibili.com/xlive/web-ucenter/v1/xfetter/GetWebList"
    // 新版 xlive/web-interface/v1/second/* 接口已被风控（返回 -352），改用不需要额外校验的旧版接口
    static let areaRoomList = "https://api.live.bilibili.com/room/v3/area/getRoomList"
    static let recommandLive = "https://api.live.bilibili.com/room/v1/room/get_user_recommend"
}

extension WebRequest {
    static func requestLiveRoom(page: Int) async throws -> [LiveRoom] {
        struct Resp: Codable {
            let rooms: [LiveRoom]
        }
        let resp: Resp = try await request(url: EndPoint.liveRoom, parameters: ["page_size": 10, "page": page])
        return resp.rooms
    }

    static func requestAreaLiveRoom(area: Int, page: Int) async throws -> [AreaLiveRoom] {
        struct Resp: Codable {
            let list: [AreaLiveRoom]
        }

        let resp: Resp = try await request(url: EndPoint.areaRoomList, parameters: ["parent_area_id": area, "area_id": 0, "sort_type": "online", "page": page, "page_size": 30])
        return resp.list
    }

    static func requestHotLiveRoom(page: Int) async throws -> [AreaLiveRoom] {
        // parent_area_id 为 0 时返回全站按人气排序的直播间
        try await requestAreaLiveRoom(area: 0, page: page)
    }

    static func requestRecommandLiveRoom(page: Int) async throws -> [AreaLiveRoom] {
        try await request(url: EndPoint.recommandLive, parameters: ["page": page, "page_size": 30])
    }
}

struct AreaLiveRoom: DisplayData, Codable, PlayableData {
    let title: String
    let roomid: Int
    let uname: String
    let system_cover: String
    let face: URL?
    let user_cover: URL?
    let parent_name: String?
    let area_name: String?
    let area_v2_name: String?
    var ownerName: String { uname }
    var pic: URL? {
        // 部分直播间没有关键帧截图，退回主播自己设置的封面
        if !system_cover.isEmpty, let url = URL(string: system_cover) { return url }
        return user_cover
    }

    var avatar: URL? { face }
    var cid: Int { 0 }
    var aid: Int { 0 }

    var overlay: DisplayOverlay? {
        var leftItems = [DisplayOverlay.DisplayOverlayItem]()
        if let area = area_v2_name ?? area_name, !area.isEmpty {
            leftItems.append(DisplayOverlay.DisplayOverlayItem(icon: nil, text: area))
        }
        return DisplayOverlay(leftItems: leftItems)
    }

    func toLiveRoom() -> LiveRoom {
        return LiveRoom(title: title, room_id: roomid, uname: uname, area_v2_name: area_v2_name ?? area_name ?? "", keyframe: system_cover.isEmpty ? nil : system_cover, face: face, cover_from_user: user_cover)
    }
}
