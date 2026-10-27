# 绿碳存折：协作入口

OpenHarmony / ArkTS / ArkUI / 本地RDB的离线低碳记录应用。当前协作候选1.1.3，schema2。
现役事实先读README.md和docs/team/项目说明.md；验收看docs/team/验收记录.md。

## 运行和验证

- `npm ci --ignore-scripts`，`npm test`：59项隔离服务回归，不是原生UI验收。
- macOS：`bash scripts/setup-sdk.sh`，`./build.sh prod`；自定义路径见README。
- Windows/其他平台：按docs/team/试用指南.md配置DevEco与API24 SDK。
- `./build.sh`是debug/测试因子模式；release必须DEV_FACTOR_MODE=false。
- 构建默认产物会被覆盖；交付前另存并核对bundle、版本和哈希。

## 源码

`entry/src/main/ets/pages`及`components`为界面；`services`为业务、RDB和快照；`data`为方法、任务与文章。
源码路径以克隆目录为准，不依赖维护者机器上的绝对路径。

## 必须保留的边界

- 正式核算排除TEST/未核验因子；不虚构来源、人类签核、试用或获奖证据。
- CO₂与CO₂e分开；不得扩大因子限定场景。传统光盘覆盖仍待确认。
- 数量是用户申报，估算不是经核证碳资产；参与任务不计kg。
- 写入和一致性读取共用LedgerOperations，队列内部不再调用已入队入口。
- 修订保留历史，撤销写冲正；schema修改必须迁移、验证旧数据恢复。
- 测试用独立QA包，不清空或迁移维护者主库/开发库。负责人原开发库6条记录、21分不得破坏。
- 正式库lvtancunzhe-production.db与开发库lvtancunzhe.db及备份隔离。
- 保留呼吸风格、可关闭动效及大字体支持。
- SDK、密钥、数据库、测试备份及本机验收中间文件不纳入Git。

## 交接和提交

业务改动同步docs/team当前事实和证据；保留回退现场，不自动删除旧本机备份。
真人试用、物理真机和最终参赛材料同步尚未完成时必须明确写待完成。
本次用户已授权创建GitHub仓库并推送供团队协作；邀请成员、外部代发、报名/赛事提交需分别获得授权。
