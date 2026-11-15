//
//  ApiRequest.swift
//  BilibiliLive
//
//  Created by yicheng on 2021/4/25.
//

import Alamofire
import CryptoKit
import Foundation
import SwiftyJSON

struct LoginToken: Codable, Equatable {
    let mid: Int
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    var expireDate: Date?
}

enum ApiRequest {
    static let appkey = "5ae412b53418aac5"
    static let appsec = "5b9cf6c9786efd204dcf0c1ce2d08436"

    enum EndPoint {
        static let loginQR = "https://passport.bilibili.com/x/passport-tv-login/qrcode/auth_code"
        static let verifyQR = "https://passport.bilibili.com/x/passport-tv-login/qrcode/poll"
        static let refresh = "https://passport.bilibili.com/api/v2/oauth2/refresh_token"
        static let ssoCookie = "https://passport.bilibili.com/api/login/sso"
        static let feed = "https://app.bilibili.com/x/v2/feed/index"
        static let season = "https://api.bilibili.com/pgc/view/v2/app/season"
    }

    enum LoginState {
        case success(token: LoginToken, cookies: [HTTPCookie])
        case fail
        case expire
        case waiting
        /// 已扫码，等待手机端确认（86090）
        case scanned
    }

    static func getToken() -> LoginToken? {
        return AccountManager.shared.activeAccount?.token
    }

    static func isLogin() -> Bool {
        return AccountManager.shared.isLoggedIn
    }

    static func sign(for param: [String: Any]) -> [String: Any] {
        var newParam = param
        newParam["appkey"] = appkey
        newParam["ts"] = "\(Int(Date().timeIntervalSince1970))"
        newParam["local_id"] = "0"
        newParam["mobi_app"] = "iphone"
        newParam["device"] = "pad"
        newParam["device_name"] = "iPad"
        var rawParam = newParam
            .sorted(by: { $0.0 < $1.0 })
            .map({ "\($0.key)=\($0.value)" })
            .joined(separator: "&")
        rawParam.append(appsec)

        let md5 = Insecure.MD5
            .hash(data: rawParam.data(using: .utf8)!)
            .map { String(format: "%02hhx", $0) }
            .joined()
        newParam["sign"] = md5
        return newParam
    }

    static func logout(complete: ((Bool) -> Void)? = nil) {
        var hasAccount = false
        if let account = AccountManager.shared.activeAccount {
            hasAccount = AccountManager.shared.removeAccount(account)
        }
        complete?(hasAccount)
    }

    static func requestJSON(_ url: URLConvertible,
                            method: HTTPMethod = .get,
                            parameters: Parameters = [:],
                            auth: Bool = true,
                            encoding: ParameterEncoding = URLEncoding.default,
                            complete: ((Result<JSON, RequestError>) -> Void)? = nil)
    {
        var parameters = parameters
        if auth {
            parameters["access_key"] = getToken()?.accessToken
        }
        parameters = sign(for: parameters)
        AF.request(url, method: method, parameters: parameters, encoding: encoding).responseData { response in
            switch response.result {
            case let .success(data):
                let json = JSON(data)
                print(json)
                let errorCode = json["code"].intValue
                if errorCode != 0 {
                    if errorCode == -101 {
                        AccountManager.shared.handleAuthenticationFailure()
                        if !AccountManager.shared.isLoggedIn {
                            AppDelegate.shared.showLogin()
                        }
                    }
                    let message = json["message"].stringValue
                    print(errorCode, message)
                    complete?(.failure(.statusFail(code: errorCode, message: message)))
                    return
                }
                complete?(.success(json))
            case let .failure(err):
                print(err)
                complete?(.failure(.networkFail))
            }
        }
    }

    static func request<T: Decodable>(_ url: URLConvertible,
                                      method: HTTPMethod = .get,
                                      parameters: Parameters = [:],
                                      auth: Bool = true,
                                      encoding: ParameterEncoding = URLEncoding.default,
                                      decoder: JSONDecoder = JSONDecoder(),
                                      complete: ((Result<T, RequestError>) -> Void)?)
    {
        requestJSON(url, method: method, parameters: parameters, auth: auth, encoding: encoding) { result in
            switch result {
            case let .success(data):
                do {
                    let data = try data["data"].rawData()
                    let object = try decoder.decode(T.self, from: data)
                    complete?(.success(object))
                } catch let err {
                    print(err)
                    complete?(.failure(.decodeFail(message: err.localizedDescription + String(describing: err))))
                }
            case let .failure(err):
                complete?(.failure(err))
            }
        }
    }

    static func request<T: Decodable>(_ url: URLConvertible,
                                      method: HTTPMethod = .get,
                                      parameters: Parameters = [:],
                                      auth: Bool = true,
                                      encoding: ParameterEncoding = URLEncoding.default,
                                      decoder: JSONDecoder = JSONDecoder()) async throws -> T
    {
        try await withCheckedThrowingContinuation { configure in
            request(url, method: method, parameters: parameters, auth: auth, encoding: encoding, decoder: decoder) { resp in
                configure.resume(with: resp)
            }
        }
    }

    static func requestLoginQR(handler: ((String, String) -> Void)? = nil, onError: (() -> Void)? = nil) {
        class Resp: Codable {
            let authCode: String
            let url: String
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        request(EndPoint.loginQR, method: .post, auth: false, decoder: decoder) {
            (result: Result<Resp, RequestError>) in
            switch result {
            case let .success(res):
                handler?(res.authCode, res.url)
            case let .failure(error):
                print(error)
                onError?()
            }
        }
    }

    struct LoginResp: Codable {
        struct CookieInfo: Codable {
            let domains: [String]
            let cookies: [Cookie]
            func toCookies() -> [HTTPCookie] {
                domains.map { domain in
                    cookies.compactMap { $0.toCookie(domain: domain) }
                }.reduce([], +)
            }
        }

        struct Cookie: Codable {
            let name: String
            let value: String
            let httpOnly: Int
            let expires: Int

            func toCookie(domain: String) -> HTTPCookie? {
                HTTPCookie(properties: [.domain: domain,
                                        .name: name,
                                        .value: value,
                                        .expires: Date(timeIntervalSince1970: TimeInterval(expires)),
                                        HTTPCookiePropertyKey("HttpOnly"): httpOnly,
                                        .path: ""])
            }
        }

        var tokenInfo: LoginToken
        let cookieInfo: CookieInfo
    }

    static func verifyLoginQR(code: String, handler: ((LoginState) -> Void)? = nil) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        request(EndPoint.verifyQR,
                method: .post, parameters: ["auth_code": code], auth: false, decoder: decoder)
        {
            (result: Result<LoginResp, RequestError>) in
            switch result {
            case var .success(res):
                res.tokenInfo.expireDate = Date().addingTimeInterval(TimeInterval(res.tokenInfo.expiresIn))
                // 不在这里写入 cookie：调用方确认要采用这次登录后再写，避免被丢弃的响应覆盖当前会话
                let cookies = res.cookieInfo.toCookies()
                handler?(.success(token: res.tokenInfo, cookies: cookies))
            case let .failure(error):
                switch error {
                case let .statusFail(code, _):
                    switch code {
                    case 86038: handler?(.expire)
                    case 86039: handler?(.waiting)
                    case 86090: handler?(.scanned)
                    default:
                        break
                    }
                default:
                    break
                }
            }
        }
    }

    static func refreshToken() {
        AF.cancelAllRequests()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        request(EndPoint.refresh, method: .post, parameters: ["refresh_token": getToken()?.refreshToken ?? ""], decoder: decoder) {
            (result: Result<LoginResp, RequestError>) in
            switch result {
            case var .success(res):
                res.tokenInfo.expireDate = Date().addingTimeInterval(TimeInterval(res.tokenInfo.expiresIn))
                let cookies = res.cookieInfo.toCookies()
                CookieHandler.shared.saveCookie(list: cookies)
                AccountManager.shared.updateActiveAccount(token: res.tokenInfo, cookies: cookies)
            case let .failure(err):
                print(err)
            }
        }
    }

    struct FeedResp: Codable {
        let items: [Items]

        struct Items: DisplayData, Codable {
            let can_play: Int?
            let title: String
            let param: String
            let args: Args
            let avatar_info: Avatar
            let player_args: PlayerArgs?
            let idx: Int
            let cover: String
            let goto: String
            let top_rcmd_reason: String?
            let bottom_rcmd_reason: String?
            let desc: String?
            let cover_left_text_1: String?
            let cover_left_text_2: String?
            let cover_left_text_3: String?
            let cover_right_text: String?

            enum CodingKeys: String, CodingKey {
                case can_play, title, param, args, idx, cover, goto, top_rcmd_reason, bottom_rcmd_reason, desc, player_args
                case cover_left_text_1, cover_left_text_2, cover_left_text_3, cover_right_text
                case avatar_info = "avatar"
            }

            var ownerName: String {
                return args.up_name ?? ""
            }

            var pic: URL? {
                return URL(string: cover)
            }

            /// 卡片第二行只放「作者 · 发布时间」；推荐理由（已关注、xx点赞等）不再顶替发布时间
            var date: String? {
                if let desc, desc.contains("·") {
                    return desc.components(separatedBy: "·").last?.trimmingCharacters(in: .whitespaces)
                }
                return nil
            }

            /// 推荐理由里的点赞数（如「5万点赞」），用来替换封面右下角的弹幕数
            private var likeText: String? {
                [top_rcmd_reason, bottom_rcmd_reason]
                    .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                    .first { $0.contains("点赞") }
            }

            var avatar: URL? { URL(string: avatar_info.cover ?? "") }
            var overlay: DisplayOverlay? {
                var leftItems = [DisplayOverlay.DisplayOverlayItem]()
                var rightItems = [DisplayOverlay.DisplayOverlayItem]()
                if let text = Self.validCoverText(cover_left_text_1) {
                    leftItems.append(DisplayOverlay.DisplayOverlayItem(icon: "play.rectangle", text: text))
                }
                if let text = Self.validCoverText(cover_left_text_2) {
                    leftItems.append(DisplayOverlay.DisplayOverlayItem(icon: "list.bullet.rectangle", text: text))
                }
                if let text = likeText ?? Self.validCoverText(cover_right_text) ?? Self.validCoverText(cover_left_text_3) {
                    rightItems.append(DisplayOverlay.DisplayOverlayItem(icon: nil, text: text))
                }
                return DisplayOverlay(leftItems: leftItems, rightItems: rightItems)
            }

            /// 接口在数据缺失或被隐藏时会返回「-弹幕」「-观看」之类的占位文字，这类不显示
            private static func validCoverText(_ text: String?) -> String? {
                guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty, !text.hasPrefix("-") else { return nil }
                return text
            }
        }

        struct Args: Codable, Hashable {
            let up_name: String?
//            let aid: Int?
        }

        struct Avatar: Codable, Hashable {
            let cover: String?
        }

        struct PlayerArgs: Codable, Hashable {
            let aid: Int?
            let cid: Int?
            let duration: Int?
            let type: String?

            enum CodingKeys: String, CodingKey {
                case aid, cid, duration, type
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let intVal = try? container.decodeIfPresent(Int.self, forKey: .aid) {
                    aid = intVal
                } else if let stringVal = try? container.decodeIfPresent(String.self, forKey: .aid) {
                    aid = Int(stringVal)
                } else {
                    aid = nil
                }

                if let intVal = try? container.decodeIfPresent(Int.self, forKey: .cid) {
                    cid = intVal
                } else if let stringVal = try? container.decodeIfPresent(String.self, forKey: .cid) {
                    cid = Int(stringVal)
                } else {
                    cid = nil
                }

                if let intVal = try? container.decodeIfPresent(Int.self, forKey: .duration) {
                    duration = intVal
                } else if let stringVal = try? container.decodeIfPresent(String.self, forKey: .duration) {
                    duration = Int(stringVal)
                } else {
                    duration = nil
                }

                type = try? container.decodeIfPresent(String.self, forKey: .type)
            }
        }
    }

    static func getFeeds(lastIdx: Int = 0) async throws -> [FeedResp.Items] {
        let idx = "\(lastIdx)"
        let resp: FeedResp = try await request(EndPoint.feed, parameters: ["idx": idx, "flush": "0", "column": "4", "device": "pad", "pull": idx == "0" ? "1" : "0"])
        return resp.items.filter({ $0.goto == "av" })
    }

    static func requestDislike(aid: Int, dislike: Bool) {
        requestJSON("https://app.biliapi.net/x/v2/view/dislike", method: .post, parameters: ["aid": aid, "dislike": dislike ? 0 : 1])
    }

    struct BangumiInfo: Codable, Hashable {
        struct Stat: Codable, Hashable {
            let coins, danmakus, favorite, favorites: Int
            let likes, reply, share, views: Int
        }

        struct Rights: Codable, Hashable {
            let area_limit: Int
            let ban_area_show: Int
        }

        struct UserStatus: Codable, Hashable {
            let follow: Int
            let follow_status: Int
        }

        let title: String
        let cover: String
        let evaluate: String?
        let season_id: Int
        let season_title: String
        let user_status: UserStatus
        let stat: Stat
        let rights: Rights
    }

    static func requestBangumiInfo(epid: Int) async throws -> BangumiInfo {
        let info: BangumiInfo = try await request(EndPoint.season, parameters: ["ep_id": "\(epid)"])
        return info
    }

    static func requestBangumiInfo(seasonID: Int) async throws -> BangumiInfo {
        let info: BangumiInfo = try await request(EndPoint.season, parameters: ["season_id": "\(seasonID)"])
        return info
    }

    struct UpSpaceListData: Codable, Hashable, DisplayData, PlayableData {
        let title: String
        let author: String
        let param: String
        let cover: URL?
        let play: Int
        let danmaku: Int
        let duration: Int
        let ctime: Int

        enum CodingKeys: String, CodingKey {
            case title, author, param, cover, play, danmaku, duration, ctime
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            // 联合投稿等条目可能没有 author 字段
            author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
            param = try container.decode(String.self, forKey: .param)
            cover = try? container.decodeIfPresent(URL.self, forKey: .cover)
            play = (try? container.decodeIfPresent(Int.self, forKey: .play)) ?? 0
            danmaku = (try? container.decodeIfPresent(Int.self, forKey: .danmaku)) ?? 0
            duration = (try? container.decodeIfPresent(Int.self, forKey: .duration)) ?? 0
            ctime = (try? container.decodeIfPresent(Int.self, forKey: .ctime)) ?? 0
        }

        // PlayableData
        var aid: Int { return Int(param) ?? 0 }
        var cid: Int { return 0 }

        // DisplayData
        var ownerName: String {
            return author
        }

        var pic: URL? { return cover }
        var date: String? { DateFormatter.stringFor(timestamp: ctime) }
        var overlay: DisplayOverlay? {
            var leftItems = [DisplayOverlay.DisplayOverlayItem]()
            var rightItems = [DisplayOverlay.DisplayOverlayItem]()
            if play > 0 {
                leftItems.append(DisplayOverlay.DisplayOverlayItem(icon: "play.rectangle", text: play.numberString()))
            }
            if danmaku > 0 {
                leftItems.append(DisplayOverlay.DisplayOverlayItem(icon: "list.bullet.rectangle", text: danmaku.numberString()))
            }
            rightItems.append(DisplayOverlay.DisplayOverlayItem(icon: nil, text: TimeInterval(duration).timeString()))
            return DisplayOverlay(leftItems: leftItems, rightItems: rightItems)
        }
    }

    /// UP 主投稿的一段结果。`videos` 只含能解析的条目，翻页信息按原始条目计算，
    /// 不会因为跳过了个别条目而误判已经到底。
    struct UpSpacePage {
        let videos: [UpSpaceListData]
        /// 下一页游标：原始最后一条的 aid（即使那条解析失败被跳过）
        let nextAid: Int?
        let hasMore: Bool
    }

    /// 只取单页（不翻页的场景用，如播放页里的「UP 主其他视频」）
    static func requestUpSpaceVideo(mid: Int, lastAid: Int?, pageSize: Int = 20, order: String = "pubdate") async throws -> [UpSpaceListData] {
        try await requestUpSpaceVideoPage(mid: mid, lastAid: lastAid, pageSize: pageSize, order: order).videos
    }

    /// 翻页列表用：连续拉取，直到凑够 `minCount` 条可用视频或已经没有更多。
    /// 列表靠返回条数判断是否到底，跳过的条目不能让一页「变短」。最多连拉 `maxPages` 页。
    static func requestUpSpaceVideos(mid: Int, lastAid: Int?, minCount: Int = 20, order: String = "pubdate", maxPages: Int = 5) async throws -> UpSpacePage {
        var videos = [UpSpaceListData]()
        var cursor = lastAid
        var hasMore = true
        for _ in 0..<maxPages {
            try Task.checkCancellation()
            let page = try await requestUpSpaceVideoPage(mid: mid, lastAid: cursor, order: order)
            videos.append(contentsOf: page.videos)
            cursor = page.nextAid
            hasMore = page.hasMore
            if videos.count >= minCount || !hasMore { break }
        }
        return UpSpacePage(videos: videos, nextAid: cursor, hasMore: hasMore)
    }

    static func requestUpSpaceVideoPage(mid: Int, lastAid: Int?, pageSize: Int = 20, order: String = "pubdate") async throws -> UpSpacePage {
        /// 单条解析失败（非普通投稿等）时跳过该条，不让整页失败；但仍记下它的 aid 作为翻页游标
        struct LossyItem: Decodable {
            let value: UpSpaceListData?
            let param: String?
            enum CodingKeys: String, CodingKey { case param }
            init(from decoder: Decoder) throws {
                value = try? UpSpaceListData(from: decoder)
                param = try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .param)
            }
        }
        struct Resp: Decodable {
            let item: [LossyItem]
            let has_next: Bool?
        }

        var param: Parameters = ["vmid": mid, "ps": pageSize, "actionKey": "appkey", "disable_rcmd": 0, "fnval": 976, "fnver": 0, "force_host": 0, "fourk": 1, "order": order, "player_net": 1, "qn": 120]
        if let lastAid {
            param["aid"] = lastAid
        }
        let resp: Resp = try await request("https://app.bilibili.com/x/v2/space/archive/cursor", parameters: param)
        let nextAid = resp.item.last?.param.flatMap { Int($0) }
        // 接口有 has_next 就以它为准，没有时按原始条数是否满一页判断
        let hasMore = (resp.has_next ?? (resp.item.count >= pageSize)) && nextAid != nil
        return UpSpacePage(videos: resp.item.compactMap(\.value), nextAid: nextAid, hasMore: hasMore)
    }
}
