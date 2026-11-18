# AchordTV for BL

一个第三方的 Apple TV（tvOS）哔哩哔哩客户端，基于 [yichengchen/ATV-Bilibili-demo](https://github.com/yichengchen/ATV-Bilibili-demo) 修改并独立维护。

> 本项目与哔哩哔哩（上海宽娱数码科技有限公司）没有任何关系，不是官方客户端。
>
> 本项目免费、开源，**从未在 App Store、TestFlight 或任何平台上架或收费**。如果你在任何地方看到收费提供本项目或其安装包，那都是未经授权的行为，可能存在安全风险，请注意辨别。

## 致谢

本项目源自 **[yichengchen](https://github.com/yichengchen)** 创建的 [ATV-Bilibili-demo](https://github.com/yichengchen/ATV-Bilibili-demo)。播放器、DASH 播放、弹幕、直播、投屏等核心能力都来自原项目，感谢原作者以及[全体贡献者](https://github.com/yichengchen/ATV-Bilibili-demo/graphs/contributors)多年来的工作。

原项目的提交历史完整保留在本仓库中。

## 与原项目相比的主要改动

**界面**
- 统一的玻璃质感界面与字号规范，重新设计登录页
- 视频详情页：UP 主头像与名字合为一体；推荐视频改用与首页一致的卡片（播放、弹幕、时长、作者、日期）；没有简介时给出明确提示
- 热门评论改为一行一条的卡片，带点赞数和时间；评论详情页同样改用新卡片
- 首页推荐卡片第二行固定为「作者 · 发布时间」，点赞数移到封面角标；接口的占位数据（如「-弹幕」）不再显示

**关注与账号**
- 关注页顶部新增关注 UP 主横排，点选后只看该 UP 主的投稿（网格模式下原「我的 › 关注UP」入口并入此处；刷视频模式仍保留该入口）
- 登录两个及以上账号时，冷启动先显示「谁在观看？」账号选择页（可在设置中关闭）
- 账号管理页的排列与细节调整

**播放**
- 可选的多 CDN 并发加速（默认关闭，在「设置 → 音视频」开启）：分段拆块后从多个 CDN 节点并发下载，单节点限速时可能更快，异常时自动回退直连
- 连续播放：分 P、合集、番剧播完自动播下一集；没有下一集时按相关推荐继续播放（「设置 → 进度控制」可分别关闭）
- 无损音频与杜比全景声默认开启（需大会员，拿不到时自动使用普通音轨）
- 播放页底栏按钮重新分组：弹幕 / 画质 / 倍速 / 更多（诊断信息收进「更多」）
- 呼出进度条时右下角显示传输状态、实时加载速度与已缓冲时长；画面加载时显示加载速度
- 直播页新增清晰度选择（原画 / 蓝光 / 超清…），线路切换不再展示封装格式、编码等技术信息

## 功能

- 二维码登录、多账号切换
- 推荐 Feed、热门、排行榜、搜索
- 关注动态、关注 UP 主、历史记录、稍后再看、收藏
- 系统播放器播放视频，支持 HDR、杜比视界、字幕
- 视频弹幕、弹幕防挡、热门评论
- 直播与直播弹幕
- 云视听小电视投屏协议

## 截图

![](imgs/1.jpg)
![](imgs/2.jpg)
![](imgs/3.png)

## 安装

### 用侧载工具安装（推荐）

1. 在侧载工具中选择「来源 › GitHub」，填入 `Achordchan/AchordTV-for-BL`，点「获取」。
2. 选择最新版本安装。发布的都是正式版，不需要勾选「包含预发布版本」。
3. 打开「自动安装更新」：main 分支每合并一次改动，GitHub Actions 会自动构建并发布新版本（版本号 `1.0.N` 递增），侧载工具会自动安装更新并续签。

### 手动安装

从 [Releases](https://github.com/Achordchan/AchordTV-for-BL/releases) 下载未签名的 `AchordTV.ipa`，用你自己的签名工具安装到 Apple TV。

### 自行编译

```bash
fastlane build_unsign_ipa
```

## 反馈

问题与建议请在本仓库的 [Issues](https://github.com/Achordchan/AchordTV-for-BL/issues) 中提出。请不要把本项目的问题反馈给原项目作者。

## 许可证

本项目沿用原项目的 [GNU General Public License v2.0](LICENSE.md)。基于本项目的修改与再发布，同样需要以 GPL-2.0 开源。

## 第三方致谢

- App 图标：[【22娘×33娘】亲爱的UP主，你怎么还在咕咕咕？](https://www.bilibili.com/video/BV1AB4y1k7em)
- [thmatuza/MPEGDASHAVPlayerDemo](https://github.com/thmatuza/MPEGDASHAVPlayerDemo)
- [dreamCodeMan/B-webmask](https://github.com/dreamCodeMan/B-webmask)
- [分析 Bilibili 客户端的“哔哩必连”协议](https://xfangfang.github.io/028)
