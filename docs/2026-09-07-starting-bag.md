# 创建混沌角色时赠送冒险家的袋子

用户确认：创建角色时仅赠送一次，不给旧存档补发，已有豪华版则不赠送。

- 原版依据：Gustav.pak 中 GLO_DLC_Gustav.txt 的 DB_DLC_OneTimeRewards。
- 豪华版 DLC：43962845-7d10-4bf0-ac1f-f13984e430b3。
- 原版袋子模板：0ae83daa-1096-4b38-9b8c-fc610a9306aa。
- CharacterCreationFinished 只记录创建完成，不立即依赖角色列表或被动；进入游戏地图后再为混沌角色消费资格。
- 角色或主机拥有豪华版，或会话已启用豪华版时，跳过并完成本次处理。
- 非豪华版创建一个原版袋子并放入角色背包；不修改模板或 DLC 权限。
- 不通过读档、升级、洗点或取得控制权产生资格。处理记录不会因卖出或丢弃袋子而清空。

验证：专项静态测试先确认缺失功能失败；完整编译与游戏测试分别记录。
游戏验收需新建非豪华版混沌角色、豪华版角色各一次，并测试旧档载入及丢弃后重载。

## 1.0.1.88 时序修正

用户的1.0.1.87新存档中，StartingBagPending与StartingBagHandled均为0条；DLC_Installed中没有豪华版。
因此确认流程未写入资格，而不是已处理后跳过。原版Z_Shared_CharacterCreation在CharacterCreationFinished事件后调用PROC_PlayersSelected("Initial")完成玩家初始化。
修正为事件先记录创建完成，LevelGameplayStarted再检查DB_Avatars与混沌标记。新增回归检查禁止在创建完成事件的资格记录中提前依赖这些条件。
该旧测试档没有新增的创建完成记录，不补发；仍需新建角色进行游戏验收。未改动用户存档。
