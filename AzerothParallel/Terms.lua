-- ==========================================
-- Terms.lua: 称谓词条库（技能 / 天赋的种族化称呼）
-- ==========================================
-- 这个文件只存“数据”，不画界面。界面在 Flavor.lua 的“称谓典籍”按钮里读取它。
--
-- 设计前提（很重要）：
--   这些称呼只显示在我们自己的面板里，绝不修改游戏客户端里的技能名。
--   所以别人看不到、不会和其他插件冲突、也不会被私服阉割的 API 影响。
--
-- 怎么加词条：
--   AP_Terms[职业token][流派id] = { 一条一条的词条 }
--   职业 token 就是 UnitClass 的第二个返回值，例如 "DRUID"、"PALADIN"。
--   流派 id 必须和 Flavor.lua 里 FlavorData[职业].factions[].id 完全一致，
--   写错了不会报错，只是典籍里查不到这组词条。
--
--   每条词条有 4 个字段：
--     category（分类）：变形 / 技能 / 天赋 / 其他，相同分类会自动归在一起
--     official（官方名）：游戏里原本显示的名字，用来对照
--     alias（专属称呼）：本流派的叫法
--     note（备注，可选）：一句话说明，不写也可以
--
-- 目前是初稿：德鲁伊三个流派各整理了一批高频技能和天赋，
-- 名字随时可以按你的 RP 设定改，改完 /reload 就能在典籍里看到。

AP_Terms = AP_Terms or {}

AP_Terms["DRUID"] = {

    -- ------------------------------------------------------------
    -- 夜爪德鲁伊：荒野、月色、申多雷血脉的回响
    -- 用词偏“野性、自然、低语”，尽量少出现学院式词汇
    -- ------------------------------------------------------------
    ["Nightclaw"] = {
        -- 变形
        { category = "变形", official = "熊形态", alias = "荒野兽躯", note = "以血肉之躯站在队伍最前面。" },
        { category = "变形", official = "猎豹形态", alias = "夜爪之形", note = "隐入阴影，用爪牙说话。" },
        { category = "变形", official = "旅行形态", alias = "逐风之形", note = "荒野从不等人。" },
        { category = "变形", official = "水栖形态", alias = "潜流之形", note = "水下也是荒野的一部分。" },
        { category = "变形", official = "枭兽形态", alias = "月枭形态", note = "月光下的守望者。" },
        -- 技能
        { category = "技能", official = "愤怒", alias = "荒野怒嚎" },
        { category = "技能", official = "星火术", alias = "星屑之火" },
        { category = "技能", official = "月火术", alias = "月痕" },
        { category = "技能", official = "纠缠根须", alias = "藤缚", note = "让土地自己抓住敌人。" },
        { category = "技能", official = "治疗之触", alias = "生命抚触" },
        { category = "技能", official = "回春术", alias = "春醒" },
        { category = "技能", official = "愈合", alias = "再生之种" },
        { category = "技能", official = "宁静", alias = "万籁安眠", note = "林间最安静的一刻，也是伤口愈合的一刻。" },
        { category = "技能", official = "野性印记", alias = "兽群之印" },
        { category = "技能", official = "精灵之火", alias = "妖灵之炬", note = "被它照到的东西，再也藏不住。" },
        { category = "技能", official = "荆棘术", alias = "刺篱" },
        { category = "技能", official = "飓风", alias = "风暴之唤" },
        { category = "技能", official = "潜行", alias = "隐入夜色" },
        { category = "技能", official = "急奔", alias = "林间疾奔" },
        { category = "技能", official = "凶猛撕咬", alias = "血牙" },
        { category = "技能", official = "撕裂", alias = "裂魂" },
        { category = "技能", official = "猛虎之怒", alias = "兽性狂怒" },
        { category = "技能", official = "狂暴回复", alias = "野性回生" },
        { category = "技能", official = "复生", alias = "归林", note = "死者回到森林，生者继续前行。" },
        { category = "技能", official = "激活", alias = "生命灌注" },
        { category = "技能", official = "星辰坠落", alias = "星陨" },
        -- 天赋
        { category = "天赋", official = "清晰预兆", alias = "林间低语", note = "荒野提前告诉你，下一击不需要法力。" },
        { category = "天赋", official = "自然迅捷", alias = "荒野迅捷" },
        { category = "天赋", official = "野性冲锋", alias = "兽形冲锋" },
        { category = "天赋", official = "月神指引", alias = "月辉指引" },
        { category = "天赋", official = "梦境", alias = "翡翠之梦", note = "睡眠时也在守护这片森林。" },
        { category = "天赋", official = "自然之力", alias = "荒野之唤" },
    },

    -- ------------------------------------------------------------
    -- 高阶会：天裔的奥术与学术传统
    -- 用词偏“星界、秘法、贤者”，把自然法术解释成一种古老的奥术遗产
    -- ------------------------------------------------------------
    ["Highborne"] = {
        -- 变形
        { category = "变形", official = "熊形态", alias = "守御兽形", note = "以奥术重铸血肉，作为前排的盾。" },
        { category = "变形", official = "猎豹形态", alias = "猎影兽形" },
        { category = "变形", official = "旅行形态", alias = "秘径之形" },
        { category = "变形", official = "枭兽形态", alias = "星枭形态" },
        -- 技能
        { category = "技能", official = "愤怒", alias = "奥能脉冲" },
        { category = "技能", official = "星火术", alias = "星界之火" },
        { category = "技能", official = "月火术", alias = "银月弧光" },
        { category = "技能", official = "纠缠根须", alias = "奥藤咒缚" },
        { category = "技能", official = "治疗之触", alias = "奥光抚触" },
        { category = "技能", official = "回春术", alias = "复苏咒" },
        { category = "技能", official = "愈合", alias = "再生咒印" },
        { category = "技能", official = "宁静", alias = "静谧法阵", note = "刻在空气里的治愈符文。" },
        { category = "技能", official = "野性印记", alias = "贤者印记" },
        { category = "技能", official = "精灵之火", alias = "灵辉标记" },
        { category = "技能", official = "荆棘术", alias = "秘刺结界" },
        { category = "技能", official = "飓风", alias = "星界风暴" },
        { category = "技能", official = "树皮术", alias = "秘壳护体" },
        { category = "技能", official = "激活", alias = "法力回响" },
        { category = "技能", official = "复生", alias = "灵魂回响", note = "把还没走远的灵魂重新唤回躯壳。" },
        { category = "技能", official = "星辰坠落", alias = "星穹倾泻" },
        -- 天赋
        { category = "天赋", official = "清晰预兆", alias = "奥术预兆" },
        { category = "天赋", official = "自然迅捷", alias = "秘法疾行" },
        { category = "天赋", official = "野性冲锋", alias = "相位突进" },
        { category = "天赋", official = "月神指引", alias = "星界指引" },
        { category = "天赋", official = "梦境", alias = "星界梦境" },
        { category = "天赋", official = "自然之力", alias = "秘法之唤" },
    },

    -- ------------------------------------------------------------
    -- 塑风者：元素与荒野的原始崇拜
    -- 用词偏“风、火、大地、水”，把每一招都说成元素借给族人的力量
    -- ------------------------------------------------------------
    ["Windshaper"] = {
        -- 变形
        { category = "变形", official = "熊形态", alias = "磐岩兽形", note = "大地借给你一副不会倒下的躯体。" },
        { category = "变形", official = "猎豹形态", alias = "疾风兽形" },
        { category = "变形", official = "旅行形态", alias = "追风之形" },
        { category = "变形", official = "枭兽形态", alias = "风枭形态" },
        -- 技能
        { category = "技能", official = "愤怒", alias = "雷鸣" },
        { category = "技能", official = "星火术", alias = "天火" },
        { category = "技能", official = "月火术", alias = "火灵印记" },
        { category = "技能", official = "纠缠根须", alias = "大地之缚" },
        { category = "技能", official = "治疗之触", alias = "活水抚触" },
        { category = "技能", official = "回春术", alias = "春风" },
        { category = "技能", official = "愈合", alias = "沃土之赐" },
        { category = "技能", official = "宁静", alias = "止息之风", note = "风停下的时候，伤口才会开始愈合。" },
        { category = "技能", official = "野性印记", alias = "元素印记" },
        { category = "技能", official = "精灵之火", alias = "灵火" },
        { category = "技能", official = "荆棘术", alias = "石棘" },
        { category = "技能", official = "飓风", alias = "旋风" },
        { category = "技能", official = "树皮术", alias = "岩石皮肤" },
        { category = "技能", official = "激活", alias = "元素灌注" },
        { category = "技能", official = "复生", alias = "归尘复生" },
        { category = "技能", official = "星辰坠落", alias = "群星之怒" },
        -- 天赋
        { category = "天赋", official = "清晰预兆", alias = "风之低语" },
        { category = "天赋", official = "自然迅捷", alias = "疾风祝福" },
        { category = "天赋", official = "野性冲锋", alias = "风袭" },
        { category = "天赋", official = "月神指引", alias = "元素指引" },
        { category = "天赋", official = "梦境", alias = "先祖之梦" },
        { category = "天赋", official = "自然之力", alias = "元素之唤" },
    },
}
