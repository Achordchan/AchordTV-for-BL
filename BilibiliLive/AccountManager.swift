import Foundation
import SwiftyJSON

final class AccountManager {
    struct Profile: Codable, Equatable {
        let mid: Int
        var username: String
        var avatar: String
        /// 大会员信息；旧版本存储里没有这个字段，必须保持可选才能正常解码
        var vip: VipInfo? = nil
    }

    /// 来自 /x/web-interface/nav 的大会员信息
    struct VipInfo: Codable, Equatable {
        /// 0 无，1 月度大会员，2 年度及以上
        var type: Int
        /// 1 有效
        var status: Int
        var dueDate: Date?
        /// 服务端给的标签文案，如「年度大会员」
        var label: String

        var isActive: Bool {
            guard status == 1, type > 0 else { return false }
            if let dueDate { return dueDate > Date() }
            return true
        }

        var displayName: String {
            if !label.isEmpty { return label }
            return type == 2 ? "年度大会员" : "大会员"
        }

        /// nav 新旧两套字段都试：`vip.{status,type,due_date,label.text}` 与顶层 `vipStatus/vipType/vipDueDate/vip_label`
        static func parse(nav json: JSON) -> VipInfo {
            let vip = json["vip"]
            let status = vip["status"].int ?? json["vipStatus"].intValue
            let type = vip["type"].int ?? json["vipType"].intValue
            let dueMs = vip["due_date"].int64 ?? json["vipDueDate"].int64Value
            let label = vip["label"]["text"].string ?? json["vip_label"]["text"].stringValue
            let dueDate = dueMs > 0 ? Date(timeIntervalSince1970: TimeInterval(dueMs) / 1000) : nil
            return VipInfo(type: type, status: status, dueDate: dueDate, label: label)
        }
    }

    struct Account: Codable, Equatable {
        var token: LoginToken
        var profile: Profile
        var cookies: [StoredCookie]
        var lastActiveAt: Date
    }

    static let shared = AccountManager()
    static let didUpdateNotification = Notification.Name("AccountManagerDidUpdate")

    private let accountsKey = "app.multiple.accounts"
    private let activeKey = "app.multiple.accounts.active"
    private let storage = UserDefaults.standard

    private var storedAccounts: [Account] = []
    private var activeMID: Int?

    private init() {
        loadFromStorage()
    }

    // MARK: - Public

    var accounts: [Account] {
        storedAccounts.sorted(by: { $0.lastActiveAt > $1.lastActiveAt })
    }

    var activeAccount: Account? {
        guard let activeMID else { return nil }
        return storedAccounts.first(where: { $0.profile.mid == activeMID })
    }

    var isLoggedIn: Bool { activeAccount != nil }

    /// 当前账号是否为有效大会员；播放时决定「自动」画质的上限
    var isActiveAccountVip: Bool {
        activeAccount?.profile.vip?.isActive ?? false
    }

    func bootstrap() {
        if activeAccount == nil, let first = storedAccounts.sorted(by: { $0.lastActiveAt > $1.lastActiveAt }).first {
            activeMID = first.profile.mid
            persistActiveMID()
        }
        applyActiveAccountCookies()
        // 冷启动就刷新一次资料，大会员状态不依赖是否打开过「我的」页
        if activeAccount != nil {
            refreshActiveAccountProfile()
        }
    }

    func registerAccount(token: LoginToken, cookies: [HTTPCookie], completion: @escaping (Account) -> Void) {
        let storedCookies = cookies.map(StoredCookie.init)
        fetchProfile(using: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                let profile: Profile
                switch result {
                case let .success(json):
                    Self.logVip(json)
                    profile = Profile(mid: json["mid"].intValue,
                                      username: json["uname"].stringValue,
                                      avatar: json["face"].stringValue,
                                      vip: VipInfo.parse(nav: json))
                case .failure:
                    profile = Profile(mid: token.mid,
                                      username: "UID \(token.mid)",
                                      avatar: "")
                }
                var newAccount = Account(token: token,
                                         profile: profile,
                                         cookies: storedCookies,
                                         lastActiveAt: Date())
                self.upsert(account: newAccount)
                self.setActiveAccount(mid: newAccount.profile.mid, applyingCookies: false, notify: false)
                self.updateAccount(mid: newAccount.profile.mid) { account in
                    account.cookies = storedCookies
                    account.lastActiveAt = Date()
                    newAccount = account
                }
                self.applyActiveAccountCookies()
                self.persistAll()
                self.notifyChange()
                completion(newAccount)
                if let vip = newAccount.profile.vip, vip.isActive {
                    VipQualityAdvisor.promptIfNeeded(mid: newAccount.profile.mid, vip: vip)
                }
            }
        }
    }

    func setActiveAccount(_ account: Account) {
        setActiveAccount(mid: account.profile.mid)
    }

    func setActiveAccount(mid: Int, applyingCookies: Bool = true, notify: Bool = true) {
        guard storedAccounts.contains(where: { $0.profile.mid == mid }) else { return }
        activeMID = mid
        persistActiveMID()
        updateAccount(mid: mid) { account in
            account.lastActiveAt = Date()
        }
        if applyingCookies {
            applyActiveAccountCookies()
            // 切到别的账号后重新拉资料（含大会员状态）
            refreshActiveAccountProfile()
        }
        persistAll()
        if notify {
            notifyChange()
        }
    }

    func updateActiveAccount(token: LoginToken, cookies: [HTTPCookie]? = nil) {
        guard let mid = activeAccount?.profile.mid else { return }
        updateAccount(mid: mid) { account in
            account.token = token
            account.lastActiveAt = Date()
            if let cookies {
                account.cookies = cookies.map(StoredCookie.init)
            }
        }
        persistAll()
        notifyChange()
    }

    func refreshActiveAccountProfile() {
        guard let requestedMID = activeMID else { return }
        fetchProfile { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case let .success(json):
                    // 请求期间切换了账号时，旧响应不能写到新账号上
                    let mid = json["mid"].int ?? requestedMID
                    guard mid == requestedMID, mid == self.activeMID else { return }
                    Self.logVip(json)
                    let vip = VipInfo.parse(nav: json)
                    let previous = self.activeAccount?.profile
                    self.updateAccount(mid: mid) { account in
                        account.profile.username = json["uname"].stringValue
                        account.profile.avatar = json["face"].stringValue
                        account.profile.vip = vip
                    }
                    self.persistAll()
                    if previous != self.activeAccount?.profile {
                        self.notifyChange()
                    }
                    if vip.isActive {
                        VipQualityAdvisor.promptIfNeeded(mid: mid, vip: vip)
                    }
                case .failure:
                    break
                }
            }
        }
    }

    func syncActiveAccountCookies() {
        guard let mid = activeAccount?.profile.mid else { return }
        let cookies = CookieHandler.shared.currentStoredCookies()
        updateAccount(mid: mid) { account in
            account.cookies = cookies
        }
        persistAll()
    }

    @discardableResult
    func removeAccount(_ account: Account) -> Bool {
        storedAccounts.removeAll(where: { $0.profile.mid == account.profile.mid })
        persistAccounts()
        let removedActive = activeMID == account.profile.mid
        if removedActive {
            activeMID = nil
            persistActiveMID()
            if let next = storedAccounts.sorted(by: { $0.lastActiveAt > $1.lastActiveAt }).first {
                setActiveAccount(mid: next.profile.mid)
            } else {
                CookieHandler.shared.removeCookie()
                notifyChange()
            }
        } else {
            notifyChange()
        }
        return !storedAccounts.isEmpty
    }

    func removeAllAccounts() {
        storedAccounts.removeAll()
        persistAccounts()
        activeMID = nil
        persistActiveMID()
        CookieHandler.shared.removeCookie()
        notifyChange()
    }

    func handleAuthenticationFailure() {
        guard let account = activeAccount else { return }
        _ = removeAccount(account)
    }

    // MARK: - Private helpers

    private static var loggedVipMIDs = Set<Int>()

    /// 每个账号把 nav 里的会员节点原样打一次日志，便于核对字段
    private static func logVip(_ json: JSON) {
        let mid = json["mid"].intValue
        guard !loggedVipMIDs.contains(mid) else { return }
        loggedVipMIDs.insert(mid)
        Logger.info("[vip] mid=\(mid) vipStatus=\(json["vipStatus"]) vipType=\(json["vipType"]) vip=\(json["vip"].rawString(options: []) ?? "nil")")
    }

    private func fetchProfile(using token: LoginToken? = nil, completion: @escaping (Result<JSON, RequestError>) -> Void) {
        WebRequest.requestLoginInfo(accessKey: token?.accessToken, complete: completion)
    }

    private func applyActiveAccountCookies() {
        guard let cookies = activeAccount?.cookies else { return }
        CookieHandler.shared.replaceCookies(with: cookies)
    }

    private func loadFromStorage() {
        if let data = storage.data(forKey: accountsKey) {
            do {
                storedAccounts = try JSONDecoder().decode([Account].self, from: data)
            } catch {
                storedAccounts = []
            }
        }
        if storage.object(forKey: activeKey) != nil {
            let mid = storage.integer(forKey: activeKey)
            activeMID = storedAccounts.contains(where: { $0.profile.mid == mid }) ? mid : nil
        }
    }

    private func persistAll() {
        persistAccounts()
        persistActiveMID()
    }

    private func persistAccounts() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(storedAccounts) {
            storage.set(data, forKey: accountsKey)
        } else {
            storage.removeObject(forKey: accountsKey)
        }
    }

    private func persistActiveMID() {
        if let activeMID {
            storage.set(activeMID, forKey: activeKey)
        } else {
            storage.removeObject(forKey: activeKey)
        }
    }

    private func upsert(account: Account) {
        if let index = storedAccounts.firstIndex(where: { $0.profile.mid == account.profile.mid }) {
            storedAccounts[index] = account
        } else {
            storedAccounts.append(account)
        }
    }

    private func updateAccount(mid: Int, update: (inout Account) -> Void) {
        guard let index = storedAccounts.firstIndex(where: { $0.profile.mid == mid }) else { return }
        update(&storedAccounts[index])
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: AccountManager.didUpdateNotification, object: self)
    }
}
