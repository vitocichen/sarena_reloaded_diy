# sArena Reloaded DIY

基于 sArena Reloaded v2.0.6e 的二次开发版本（DIY 子版本：v1.1.1）。

**DIY: DK-姜世离(燃烧之刃)**

---

## DIY 功能列表

### 自身递减追踪 (SelfDR)
- 基于 C_LossOfControl API 实时监测玩家受到的控制效果
- 支持 7 种递减分类：昏迷、迷惑、瘫痪、定身、沉默、击退、缴械
- 可拖拽容器，位置自动保存
- 图标大小、间距、字体大小、增长方向均可配置

### 姓名版递减镜像 (HealthBarDR)
- JJC 内将 Blizzard DR 帧镜像到敌方姓名板上
- 世界/BG 中追踪玩家自身 DR（基于 UNIT_SPELLCAST_SUCCEEDED）
- 集火目标预测（三元组启发式匹配）

### 姓名版饰品镜像 (NameplateTrinket)
- 将 Blizzard CompactArenaFrame 的 PvP CC remover 图标和 CD 镜像到姓名板

### 宠物框体
- 上游 sArena Reloaded 已自带宠物框体时，直接使用上游实现（含鼠标拖动）
- 仅在上游没有宠物框体时，才启用 DIY PetBar 作为后备

---

## 更新记录

### v1.1.1 (2026-08-17)
- 上游基线升级到 v2.0.6e，并恢复 DIY 接线（SelfDR / 姓名板递减 / 姓名板饰品）
- 宠物框体与鼠标拖动：上游已有则用上游，没有才用 DIY PetBar
- 合并 MyDRs v1.1.3：SelfDR 递减重置时间 16 秒 → 20 秒（免疫发光与 Masque 未并入）
- 姓名板锚点解析对齐 MidnightDR：优先走姓名板自身的 `GetAnchor()`，再按 TPFrame / AnchorFrame / UnitFrame 顺序回退

### v1.1.0 (2026-08-17)
- 基线升级到上游 v2.0.6e
- 修复 12.1 Class Color API 变更
- 修复 Secret boolean taint 问题
- 新增 Race Text 显示
- 保留所有 DIY 功能模块

---

## 致谢

Credits: Stako, Bodify (sArena Reloaded)  
参考插件: GladiusEx, MidnightDR, MyDRs
