# iPlayer935

[English](README.md) · [Español](README.es.md) · [简体中文](README.zh-CN.md)

专为 **运行 iOS 9.3.5 的 iPod touch 5** 打造的原生音乐播放器。从自己的 SMB 服务器播放音乐，保存歌曲以便离线收听，体验受 iPod 经典“音乐”应用启发的界面。

![正在播放、音乐库与交叉淡化](docs/media/iplayer935-playback.png)

![播放列表、离线收听与 SMB 服务器](docs/media/iplayer935-library-offline.png)

*宣传合成图基于真实 iPod 截图制作。服务器隐私信息已模糊处理。*

## 功能

- 通过 SMB2/SMB3 访问自己的音乐服务器，支持多个配置，密码保存在 Keychain 中。
- 通过 iOS 播放 MP3、AAC/M4A、ALAC、WAV/AIFF/CAF；通过 FFmpeg 解码 FLAC、Ogg Vorbis 和 Opus。
- 持久缓存元数据和封面，提供进度查看、暂停与继续功能。
- 支持搜索，以及按标题、艺术家、专辑、流派、曲目编号或文件修改日期排序。
- 常驻迷你播放器、完整的“正在播放”视图、收藏和歌曲批量操作。
- 支持播放列表、M3U/M3U8 导入、随机播放，并恢复上次的歌曲、播放位置和队列。
- 可调节交叉淡化，提供等功率和线性曲线，可分别设置手动切歌与自动切歌，并支持本次会话的临时开关。
- 手动下载，以及有空间上限的自动缓存，可预先下载队列中的后续歌曲。
- 支持英语、西班牙语和简体中文，可在应用内选择语言或跟随系统语言。

## 下载与安装

从[最新发布版本](https://github.com/neura-neura/iplayer935/releases/latest)下载 **iPlayer935.ipa**。该页面提供英文版本说明，以及对应的源码和重新链接所需文件包。

支持的设备是 **已越狱的 iPod touch 5（iPod5,1），运行 iOS 9.3.5，使用 ARMv7**，且已安装 **AppSync Unified**。其他设备和 iOS 版本尚未验证。

如需在 Mac 上通过 USB 安装，请克隆本仓库，将下载的 IPA 放到 `deliverables/iPlayer935.ipa`，连接并解锁 iPod；如有提示，请信任电脑：

```sh
brew install libimobiledevice ideviceinstaller
./scripts/install.sh
```

使用相同应用标识符安装更新会保留应用数据。如需保留音乐库、设置和下载内容，请勿先卸载应用。

## 连接音乐服务器

1. 打开**服务器**。全新安装仅显示 **Example Music Server**，这是一个不会自动连接的虚构示例。点按它可填写自己的服务器信息，也可使用 **+** 新增配置。每个字段都有填写说明。
2. 输入服务器 IP 或主机名（不含 `smb://`）、SMB 共享名称、相对于该共享的可选子文件夹，以及 SMB 登录信息。例如：主机 `music-server.local`、共享 `Music`、文件夹 `Albums/Rock`。请使用有权访问 SMB 的账户；SSH 账户的权限可能不同。
3. 保存后使用 **ⓘ → 测试连接**。打开服务器即可浏览音乐库。应用只读取音乐共享，不会修改服务器文件。
4. 使用 **⋯ → 刷新音乐库和 M3U** 强制扫描。进入服务器及音乐库保持可见时会进行自动检查，两次检查之间至少间隔 15 分钟。这些操作是后台扫描，不是服务器的即时通知。
5. 元数据和封面会缓存在本地。可在 **⋯ → 标签缓存状态** 中查看或暂停进度。已检查且未发生变化的文件不会在每次打开应用时重复处理。

## 播放与离线收听

点按歌曲即可播放，无需离开列表。点按迷你播放器可打开“正在播放”；使用**返回**按钮或从左侧边缘向右滑动即可返回。播放器提供随机播放和交叉淡化控制，交叉淡化设置位于 **⋯** 菜单。如果启用了相应的会话控制，长按随机播放按钮即可临时暂停或恢复交叉淡化。

在歌曲列表中使用选择图标，选中歌曲后打开 **⋯** 执行批量操作。通过**播放列表 → +** 创建列表。歌曲信息菜单提供收藏、播放列表和下载操作。

在**下载**中管理手动下载的歌曲。打开**下载 → ⋯ → 自动缓存**可调整后续歌曲预缓存，并查看可用歌曲。只有完整下载的文件才能离线播放；自动缓存可能会移除旧条目以遵守空间上限。要播放尚未缓存的远程歌曲，iPod 必须能够访问 SMB 服务器，例如处于同一网络或通过已配置的 VPN 连接。

## 性能与兼容性

音乐库使用 SQLite 索引、分页列表和后台处理来管理大型音乐收藏。首次扫描和标签缓存仍需要时间，尤其是在服务器连接较慢时；准备过程中仍可浏览和播放。

文件扩展名并不保证编解码器兼容性。不支持 WMA。FLAC 播放、进度跳转和离线播放已在实体 iPod 上验证；真实 Ogg/Opus 文件的播放仍需更广泛的设备测试。已验证的行为与限制详见[验证记录](docs/VALIDATION.md)。

## 构建与开发

应用使用 Objective-C/UIKit 编写，面向 ARMv7。构建脚本使用 LLVM、ldid 和固定版本的旧版 iOS SDK；这不是现代 Xcode 工程。

```sh
brew install llvm ldid libimobiledevice ideviceinstaller
./scripts/build.sh
```

输出文件为 `deliverables/iPlayer935.ipa`。请参阅[构建说明](docs/BUILD.md)、[架构](docs/ARCHITECTURE.md)、[SMB 集成](docs/SMB.md)及[本地化说明](docs/LOCALIZATION.md)。测试脚本位于 `Tests/`；部分测试需要先通过 `scripts/codec-build.sh` 构建编解码器库。

## 致谢与依赖

作者：[neura-neura](https://github.com/neura-neura)。

应用包含 [libsmb2](https://github.com/sahlberg/libsmb2) 和 [FFmpeg](https://ffmpeg.org/)，对应 LGPL 声明位于 `Vendor/libsmb2` 和 `deliverables/licences`。发布版本包含对应源码和可重新链接的目标文件；依赖的重新构建方法详见[构建说明](docs/BUILD.md)。截图中的专辑封面及歌曲名称归各自权利人所有。本项目独立开发，与 Apple 或 Spotify 无关联。
