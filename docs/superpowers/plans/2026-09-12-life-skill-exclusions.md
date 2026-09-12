# 生活加值排除运动与体操 Implementation Plan

**Goal:** 按用户确认，仅从生活熟练项加值中排除运动、体操，保留其余16项及现有武器防具独立开关。
**Architecture:** 原地修改20个状态和20个配套被动的 Boosts，不改Story、配置值、原生熟练或独立固定检定+30。
**Tech Stack:** BG3 Stats、XML、本地PowerShell构建。

- [ ] 在 story-src/verify-life-skill-exclusions.ps1 检查两类各20项，Boosts精确等于16个获批技能的 Skill(name,value) 列表；旧源码必须失败。
- [ ] 在 Passive.txt 和 Status_BOOST.txt 的上述40条定义移除 Skill(Athletics,n);Skill(Acrobatics,n);，其余字段不动。
- [ ] 修改四语共享菜单说明 h74000011g0011g4011g8011g000000000011，明确不包含两项、0关闭、默认5。
- [ ] 更新 verify.ps1 的既有期望列表，接入新增检查。运行 verify-life-skill-exclusions.ps1 和 build.ps1，发布1.0.1.97。
- [ ] 校验PAK唯一条目、导出哈希，备份到既有GitHub分支。此轮不自动安装。
