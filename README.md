# 绿碳存折

面向校园日常的 OpenHarmony 离线低碳记录应用。当前协作候选 **1.1.3 / schema 2**。

两个主要亮点是**可追溯的减排凭证**和**可解释的七日行动计划**。数量由使用者申报，结果是限定边界下的相对估算，不是经核证碳资产。

| 你要做什么 | 从这里开始 |
|---|---|
| 拉取项目、安装和运行 | [成员上手与试用](docs/team/试用指南.md) |
| 制作 PPT、找图和统一口径 | [PPT 交接](docs/team/PPT交接.md) |
| 看功能、架构、限制和已知问题 | [项目说明](docs/team/项目说明.md) |
| 看验收结果及复现证据 | [验收记录](docs/team/验收记录.md) |
| 查看因子依据与实际适用范围 | [来源与边界](docs/team/来源与边界.md) |
| 协作修改、反馈问题 | [CONTRIBUTING](CONTRIBUTING.md) |

## 环境

- DevEco Studio；工程使用 OpenHarmony SDK **API 24** 编译，兼容配置 API 12。**实际原生验收环境是 API 24 手机模拟器**，并不代表所有 API 12+ 设备都已验证。
- 手机模拟器是已验证的运行方式。物理设备需要相应 SDK、调试与签名配置。
- 纯业务回归用 Node.js 18+；预留的CI模板使用 Node.js 22。
- 克隆到英文路径，例如 `D:\Projects\lvtancunzhe` 或 `~/Projects/lvtancunzhe`，避免构建工具对非 ASCII 工程路径的限制。

## 先运行 App

在 DevEco Studio 中打开仓库根目录，配置匹配 SDK，启动手机模拟器，构建 **release**。普通 debug 构建启用测试因子，会显示开发横幅，不能用于参赛截图和演示。

macOS 默认安装路径可使用：

```sh
bash scripts/setup-sdk.sh
./build.sh prod
```

自定义安装目录：

```sh
export DEVECO_HOME="/path/to/DevEco-Studio/Contents"
export OPENHARMONY_SDK_HOME="$HOME/Library/OpenHarmony/Sdk"
bash scripts/setup-sdk.sh
./build.sh prod
```

Windows 请按[成员指南](docs/team/试用指南.md)使用 DevEco 终端。不要复制其他人的 `local.properties` 或签名配置。

构建产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`。这是 **HAP，不是 Android APK**。是否能够安装未签名包取决于调试环境；本项目只验证过指定模拟器。常规设备需自行按 DevEco 配置签名。

## 运行 59 项业务回归

```sh
npm ci --ignore-scripts
npm test
```

安装 DevEco 的机器优先使用 SDK 随附的 ArkTS TypeScript；未安装 SDK 的 CI 使用锁定的 npm TypeScript，执行同一组服务逻辑回归。也可用 `ARKTS_TYPESCRIPT_PATH` 指定编译器目录。

**这不替代 ArkTS release 编译和原生 UI 验收**，不访问用户数据库。云端CI尚未启用；仓库管理员可按[自动检查说明](docs/team/automation/README.md)启用模板。

## 当前边界

- CO₂ 与 CO₂e 分开查看，不合并质量冒充一个减排总量。
- 正式模式开放电力、汽油燃烧替代步行/普通骑行、实际再生利用废纸和限定苹果采购场景；各有适用条件。
- 传统“光盘”赛题覆盖及方法本地适用性仍需团队确认；苹果采购估算不能解释成“吃完一顿饭就减排”。
- 3—5 名真人试用尚待成员实际执行；不要在 PPT 中写成已完成。
- 原有参赛文档/视频冻结于 1.1.1。本仓库是 1.1.3 协作候选，应据此重新截图和更新材料。

历史本机测试库、备份、签名文件、SDK、依赖缓存及中间录屏不纳入仓库。选取的界面截图仅展示 QA 演示数据。
