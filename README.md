# AchordTV for BL

一个第三方的 Apple TV（tvOS）哔哩哔哩客户端，基于 [yichengchen/ATV-Bilibili-demo](https://github.com/yichengchen/ATV-Bilibili-demo) 修改并独立维护。

> 本项目与哔哩哔哩（上海宽娱数码科技有限公司）没有任何关系，不是官方客户端。
>
> 本项目免费、开源，**从未在 App Store、TestFlight 或任何平台上架或收费**。如果你在任何地方看到收费提供本项目或其安装包，那都是未经授权的行为，可能存在安全风险，请注意辨别。

## 致谢

本项目源自 **[yichengchen](https://github.com/yichengchen)** 创建的 [ATV-Bilibili-demo](https://github.com/yichengchen/ATV-Bilibili-demo)。播放器、DASH 播放、弹幕、直播、投屏等核心能力都来自原项目，感谢原作者以及[全体贡献者](https://github.com/yichengchen/ATV-Bilibili-demo/graphs/contributors)多年来的工作。

原项目的提交历史完整保留在本仓库中。

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
