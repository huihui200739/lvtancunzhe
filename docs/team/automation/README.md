# 可选自动检查

当前云端CI**尚未启用**。2026-10-27推送时，GitHub因当前登录缺少`workflow`权限拒绝包含`.github/workflows`的提交。源码和试用资料的推送不需要额外申请该权限，因此先提供模板供管理员决定何时启用。

`service-checks.yml.example`使用固定SHA的GitHub官方checkout/setup-node动作、Node.js22、`npm ci`、59项服务回归和`npm run check:publish`；不替代原生构建及界面验收。

有适当权限的仓库管理员可将模板复制为`.github/workflows/service-checks.yml`并提交，再以Actions实际运行结果为准。若通过CLI操作，需要自身凭据有相应workflow权限；不要把令牌写进仓库或交给其他成员。

本轮本地和干净克隆已完成59项回归与release构建，见[验收记录](../验收记录.md)。
