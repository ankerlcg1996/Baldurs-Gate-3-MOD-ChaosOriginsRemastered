# 1.0.1.83：修正菜单勾选状态的比较键

## 已证实的缺陷

NMCM 集成文档说明 Name.Str 是已解析语言的被动显示名，而非 Stats ID：
https://github.com/Luiznunes12/bg3-nmcm/blob/main/docs/integration.md#3-the-slot-registry

正常的 COS_CFG_MECH_POWER 的 DisplayName 本地化内容就是 COS_CFG_MECH_POWER。
75 个授予选项以及 COS_CFG_VOLO_EYE 却复用了中文界面标题，如阿斯代伦、瓦罗魔法眼。
XAML 仍比较内部标识，因此存在被动也无法显示勾选。

## 修改

为这 76 个镜像被动分配独立显示键，四种语言均保留完全相同的内部标识。
玩家看到的菜单标题仍引用原来的翻译文本，不改变中文标题。
不改 Story 逻辑、权限、默认值或已经保存的选择；保留 .82 的诊断。

## 验证边界

新增 verify-menu-mirror-keys.ps1 遍历键鼠及手柄菜单中的 Name.Str 比较，
逐个校验四种语言中的实际显示名。旧版先失败于 COS_CFG_VOLO_EYE，新版通过。
接入完整 verify.ps1，调整本地化数量以及分离后的镜像句柄约束。

该修改修复了确定的状态显示缺陷，不能据此断言点击传递的问题已全部解决。
此前 .82 新角色存档中 Trace 为 0；较早角色的 VoloEyeSetting 曾为 0。
这些证据不足以证明所有点击从未到达，也不能证明当前点击到达。
仍需游戏内验证默认勾选、切换和关闭后重开菜单的状态一致性。
