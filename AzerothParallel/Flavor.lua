-- ==========================================
-- Flavor.lua: 职业流派 (全职业大图鉴 & 无限制预览版)
-- ==========================================
local playerFaction = UnitFactionGroup("player")
-- 职业流派 UI 挂在第 2 个面板（对应顶部“职业流派” Tab），不是第 1 个“设定”页
local p1 = AP_Panels[2]
local LeftPage = p1.LeftPage
local RightPage = p1.RightPage

-- 强制校验数据
AP_DB.flavor = AP_DB.flavor or {}
AP_DB.flavor.rep = AP_DB.flavor.rep or {}
AP_DB.flavor.history = AP_DB.flavor.history or {}

local _, realClassToken = UnitClass("player")
AP_DB.flavor.currentClass = realClassToken
AP_DB.flavor.previewClass = AP_DB.flavor.previewClass or realClassToken

-- 是否把称谓反映到游戏内的鼠标提示（只改 tooltip 第一行，安全开关，默认关）
AP_DB.flavor.tooltipAlias = AP_DB.flavor.tooltipAlias and true or false

if not AP_DB.flavor.currentFaction or AP_DB.flavor.currentFaction == "" then
    AP_DB.flavor.currentFaction = "Nightclaw"
end
AP_DB.flavor.previewFaction = AP_DB.flavor.previewFaction or AP_DB.flavor.currentFaction
if not AP_DB.flavor.customName or AP_DB.flavor.customName == "" then
    AP_DB.flavor.customName = UnitName("player")
end

-- ==========================================
-- 1. 数据层 (Data Layer)
-- ==========================================
-- 头衔生成：前 6 级 = 通用前缀 + base，后 4 级为每个流派手写的专属头衔
-- base: 前 6 级的称呼名词（如 "骑士"）；top: 第 7~10 级的 4 个头衔
local TIER_PREFIXES = { "见习", "初级", "游历", "资深", "精锐", "高阶" }
local function MakeTiers(base, top)
    local tiers = {}
    for i = 1, 10 do
        local name
        if i <= 6 then
            name = TIER_PREFIXES[i] .. base
        else
            name = (top and top[i - 6]) or (base .. "长老")
        end
        local exp = 0
        if i > 1 then exp = (i - 1) * (i - 1) * 500 end
        table.insert(tiers, { level = i, name = name, exp = exp })
    end
    return tiers
end

-- 说明：流派 id 保持不变（存档里的声望是按 id 存的），只改了显示用的 name / description
-- 流派名建议控制在 5 个汉字以内，否则 Tab 按钮会被截断
local FlavorData = {
    ["DRUID"] = {
        className = "德鲁伊",
        classColor = RAID_CLASS_COLORS["DRUID"],
        factions = {
            {
                id = "Highborne",
                name = "高阶会",
                reqFaction = "Alliance",
                icon = "Interface\\Icons\\Spell_Arcane_Arcane02",
                description =
                "天裔是无限服全新种族，没有历史层积的专属职业称呼。德鲁伊直接使用职业名，但这群天裔的血脉中流淌着高阶会的奥术遗产。\n\n泽风岛的天空正在剥落，风灵失踪的真相、族人的分裂、密教的威胁——这一切都还没有答案。你是高阶会的一员，追寻着奥术与学术的传统，试图在危机中寻找真相。",
                tiers = MakeTiers("德鲁伊", { "星界学徒", "奥术贤者", "高阶会长老", "高阶会贤者" })
            },
            {
                id = "Windshaper",
                name = "塑风者",
                reqFaction = "Horde",
                icon = "Interface\\Icons\\Spell_Nature_Cyclone",
                description =
                "塑风者天裔的德鲁伊直接使用职业名，但他们的信仰深处是对元素与荒野的原始崇拜。\n\n萨满之道是塑风者的主流——图腾、元素、先祖。你作为其中的一员，肩负着在异乡重建族群荣光的使命。风之灵失踪了。你的族人需要答案。而你，需要让元素重新咆哮。",
                tiers = MakeTiers("德鲁伊", { "风语者", "塑风长老", "元素先行者", "风暴之声" })
            },
            {
                id = "Nightclaw",
                name = "夜爪德鲁伊",
                reqFaction = "Neutral",
                icon = "Interface\\Icons\\Ability_Druid_Rake",
                description =
                "夜爪不是某个组织的名字，而是一种选择。当天裔的族人分裂为元素与奥术两派时，仍有一小群人选择走入荒野，倾听草木与野兽的低语。\n\n他们不效忠高阶会，也不加入塑风者。他们是夜爪，是申多雷德鲁伊血脉中几乎断绝的回响。现在，荒野在呼唤你。",
                tiers = {
                    { level = 1, name = "荒野旅者", exp = 0 }, { level = 2, name = "月影行者", exp = 500 },
                    { level = 3, name = "林间守望者", exp = 1500 }, { level = 4, name = "自然之友", exp = 3000 },
                    { level = 5, name = "星界引路人", exp = 6000 }, { level = 6, name = "荒野守护者", exp = 10000 },
                    { level = 7, name = "梦境行者", exp = 15000 }, { level = 8, name = "翡翠之友", exp = 25000 },
                    { level = 9, name = "荒野贤者", exp = 40000 }, { level = 10, name = "永恒回响", exp = 60000 },
                }
            },
        }
    },
    ["PALADIN"] = {
        className = "圣骑士",
        classColor = RAID_CLASS_COLORS["PALADIN"],
        factions = {
            {
                id = "SilverHand",
                name = "白银之手",
                reqFaction = "Alliance",
                icon = "Interface\\Icons\\INV_Hammer_01",
                description =
                "白银之手是人类与矮人圣骑士共同的传统，誓言比铠甲更重。\n\n它在第二次战争之后由最初的圣骑士们创立，也曾在背叛与堕落中受过考验，却始终没有熄灭。\n\n现在，圣光选择了你。你要证明这套誓言，在新的战场上依然有分量。",
                tiers = MakeTiers("圣骑士", { "白银骑士", "圣光护卫", "白银领主", "大领主" })
            },
            {
                id = "Sunwalker",
                name = "烈日行者",
                reqFaction = "Horde",
                icon = "Interface\\Icons\\Spell_Holy_Sunwell",
                description =
                "烈日行者是牛头人圣骑士的传统，他们追随太阳神安舍，把光明看作草原上的第一缕晨曦。\n\n他们不靠厚重的板甲，而是以誓言与部族的信任守护同伴。这个名字既是荣耀，也是承诺。\n\n现在，太阳正在你的身后升起。",
                tiers = MakeTiers("行者", { "晨光之盾", "正午之矛", "黎明使者", "日神化身" })
            },
            {
                id = "UndeadPaladin",
                name = "灰烬誓约",
                reqFaction = "Horde",
                icon = "Interface\\Icons\\Spell_Shadow_DeathCoil",
                description =
                "死亡没有解除他们的誓言，只是让誓言变得更沉。灰烬誓约由那些在亡灵之躯中仍守着最后一点光明的圣骑士组成。\n\n他们不被生者完全接纳，也不愿被黑暗彻底吞没。苍白的圣光，是他们仅剩的一点体温。\n\n你守着的，是什么誓言？",
                tiers = MakeTiers("守誓者", { "苍白骑士", "灰烬卫士", "誓约统领", "不朽誓者" })
            },
            {
                id = "LoneOath",
                name = "独行誓者",
                reqFaction = "Neutral",
                icon = "Interface\\Icons\\Spell_Holy_SealOfSalvation",
                description =
                "没有教会，没有军团，也没有旗帜。独行誓者把誓言刻在自己身上，向圣光负责，也向自己负责。\n\n他们在各个阵营的边境游荡，有人称他们为异端，也有人在最黑暗的夜里等着他们出现。\n\n你的誓言，由你自己来定。",
                tiers = MakeTiers("誓者", { "无旗骑士", "孤灯守卫", "黎明行者", "不灭之誓" })
            },
        }
    },
    ["PRIEST"] = {
        className = "牧师",
        classColor = RAID_CLASS_COLORS["PRIEST"],
        factions = {
            {
                id = "HolyChurch",
                name = "圣光牧师",
                reqFaction = "Alliance",
                icon = "Interface\\Icons\\Spell_Holy_HolyBolt",
                description =
                "圣光教会是人类、矮人与侏儒牧师共同的体系，既治愈伤痛，也守住信念。\n\n教会的钟声在暴风城与铁炉堡的街头回响，那里有最古老的祷词，也有最现实的责任。\n\n现在，轮到你为受伤的人祈祷。",
                tiers = MakeTiers("牧师", { "教会司铎", "圣光主祭", "主教", "大主教" })
            },
            {
                id = "MoonPriestess",
                name = "月之女祭司",
                reqFaction = "Alliance",
                icon = "Interface\\Icons\\Spell_Nature_StarFall",
                description =
                "暗夜精灵的牧师向月神艾露恩祈祷，她们的祷词里有月光，也有森林的低语。\n\n在月色笼罩的神殿里，月之女祭司守护的不只是信仰，还有一个种族漫长的记忆。\n\n月光照着你，你照着同伴。",
                tiers = MakeTiers("祭司", { "月之侍女", "月神使者", "大祭司", "艾露恩之选" })
            },
            {
                id = "ShadowPriest",
                name = "遗忘之影",
                reqFaction = "Horde",
                icon = "Interface\\Icons\\Spell_Shadow_Shadowform",
                description =
                "亡灵牧师的信仰并非来自光明，而是来自被遗忘者的暗影。他们接受死亡，也利用死亡。\n\n他们倾听无数被抛弃的低语，把它们变成对抗天灾与敌人的力量。\n\n你在暗影中看见的，才是真相。",
                tiers = MakeTiers("影祭司", { "暗影司铎", "虚空先知", "被遗忘者之声", "遗忘之主" })
            },
            {
                id = "VoodooPriest",
                name = "巫毒祭司",
                reqFaction = "Horde",
                icon = "Interface\\Icons\\Spell_Nature_Polymorph",
                description = "巨魔牧师的力量来自洛阿神，来自鼓声、鲜血与古老的契约。\n\n巫毒不是邪术，而是一种与神灵共同呼吸的方式。\n\n洛阿在听，你要对它们说什么？",
                tiers = MakeTiers("祭司", { "洛阿侍者", "鼓声先知", "大巫医", "洛阿之选" })
            },
        }
    },
    ["WARLOCK"] = {
        className = "术士",
        classColor = RAID_CLASS_COLORS["WARLOCK"],
        factions = {
            {
                id = "StandardWarlock",
                name = "契约术士",
                reqFaction = "Neutral",
                icon = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
                description =
                "没有哪个术士是无缘无故走上这条路的。契约术士以代价换取力量，用恶魔的火焰为自己照路。\n\n他们不属于任何阵营，只和自己的契约有关。力量是借来的，债总有一天要还。\n\n你签下的，是哪一份契约？",
                tiers = MakeTiers("术士", { "深渊契约者", "暗火领主", "恶魔主宰", "虚空领主" })
            },
            {
                id = "Necromancer",
                name = "死灵法师",
                reqFaction = "Horde",
                icon = "Interface\\Icons\\Spell_Shadow_RaiseDead",
                description =
                "亡灵术士在背景上偏向死灵魔法。他们研究的不是如何杀死敌人，而是死亡之后还剩下什么。\n\n在瘟疫与废墟之间，死灵法师把骸骨与灵魂当作最后的工具。\n\n有人说那是亵渎，你却从中看到了答案。",
                tiers = MakeTiers("死灵法师", { "骸骨学者", "亡魂使者", "亡灵导师", "巫妖" })
            },
            {
                id = "ShadowCouncil",
                name = "暗影议会",
                reqFaction = "Horde",
                icon = "Interface\\Icons\\Spell_Shadow_DemonicTactics",
                description =
                "古尔丹创立的暗影议会，是兽人术士最古老也最黑暗的传承。他们用邪能换取力量，也把整个种族一步步推向了深渊。\n\n议会的席位是用鲜血和背叛换来的。有人至今仍把它视为兽人崛起的开端，也有人把它当作永远洗不掉的耻辱。\n\n力量就在眼前，代价由别人来付。你，要不要坐上这个位置？",
                tiers = MakeTiers("议员", { "议会密使", "暗影长老", "邪能先知", "古尔丹的继承者" })
            },
            {
                id = "SuccubusFan",
                name = "魅魔常客",
                reqFaction = "Neutral",
                icon = "Interface\\Icons\\Spell_Shadow_SummonSuccubus",
                description =
                "有人和恶魔订立契约是为了力量，有人是为了复仇，而你——是为了她。魅魔的鞭子、低语，还有那句“你又来了”。\n\n常客们对外宣称是在研究恶魔学，实际上研究的永远是同一位魅魔。每次召唤都是一次预约，每次反噬都是一次甜蜜的小惩罚。\n\n别紧张，魅魔不会咬人，只会收账。",
                tiers = MakeTiers("常客", { "贵宾会员", "私人助理", "鞭下常客", "魅魔宠臣" })
            },
            {
                id = "LegionCultist",
                name = "军团信徒",
                reqFaction = "Neutral",
                icon = "Interface\\Icons\\Spell_Fire_FelFlameStrike",
                description =
                "他们不相信艾泽拉斯有未来，只相信燃烧军团终将降临。军团信徒把邪能当作信仰，把毁灭当作救赎。\n\n多数人对他们避之不及，他们却认为自己是少数清醒的人，在为迎接新世界做准备。\n\n军团已经注意到了你。",
                tiers = MakeTiers("信徒", { "邪焰祭司", "军团使者", "深渊先知", "军团代行者" })
            },
        }
    },
    ["MAGE"] = {
        className = "法师",
        classColor = RAID_CLASS_COLORS["MAGE"],
        factions = {
            {
                id = "StandardMage",
                name = "肯瑞托学者",
                reqFaction = "Alliance",
                icon = "Interface\\Icons\\INV_Misc_Book_09",
                description =
                "肯瑞托是达拉然的法师议会，联盟奥术传统的正统。他们崇尚规范、学术与克制。\n\n每一位肯瑞托学者都在图书馆里度过了漫长的岁月，才被允许把火焰握在手中。\n\n你学到的每一条法则，都有人为之付出过代价。",
                tiers = MakeTiers("学者", { "达拉然议员", "奥术导师", "六人议会候补", "大法师" })
            },
            {
                id = "WildMage",
                name = "流浪奥术士",
                reqFaction = "Horde",
                icon = "Interface\\Icons\\Spell_Fire_FireBolt02",
                description =
                "没有导师，没有学院，只有自己摸索出来的危险奥术。流浪奥术士从不被正统认可，却比谁都清楚魔法的边界在哪里。\n\n他们的法术粗糙而有效，有时也会反噬施法者。\n\n规则是别人写的，你有你的办法。",
                tiers = MakeTiers("奥术士", { "奥术游民", "禁忌研究者", "奥术狂人", "奥术宗师" })
            },
            {
                id = "MercenaryMage",
                name = "雇佣兵法师",
                reqFaction = "Neutral",
                icon = "Interface\\Icons\\INV_Misc_Coin_02",
                description = "只要金币给够，放火、传送、变面包都行。雇佣兵法师把奥术当成手艺，把委托当成生活。\n\n他们没有立场，只有报价单和信誉，而信誉往往比金币更值钱。\n\n下一单，价钱谈好了吗？",
                tiers = MakeTiers("法师", { "金牌法师", "首席承包人", "赏金大师", "赏金领主" })
            },
        }
    },
    ["WARRIOR"] = {
        className = "战士",
        classColor = RAID_CLASS_COLORS["WARRIOR"],
        factions = {
            {
                id = "StandardWarrior",
                name = "狮盾近卫",
                reqFaction = "Alliance",
                icon = "Interface\\Icons\\INV_Sword_04",
                description = "为联盟而战的正规军士兵。狮盾近卫在号角声中列队，在盾牌之后守住阵线。\n\n他们不追求个人荣耀，而是用纪律把整个联盟的防线连在一起。\n\n你站在哪里，防线就在哪里。",
                tiers = MakeTiers("近卫", { "军士", "百夫长", "联盟将官", "联盟元帅" })
            },
            {
                id = "HordeWarrior",
                name = "血旗战士",
                reqFaction = "Horde",
                icon = "Interface\\Icons\\INV_Axe_04",
                description = "部落的战士在血与火中长大，他们用战旗记录每一场胜利，也记录每一位倒下的兄弟。\n\n血旗战士不问为何而战，只问谁与自己并肩。\n\n旗帜在你手里，别让它倒下。",
                tiers = MakeTiers("战士", { "旗手", "战团队长", "血旗战将", "战争领袖" })
            },
            {
                id = "MercenaryWarrior",
                name = "自由佣兵",
                reqFaction = "Neutral",
                icon = "Interface\\Icons\\INV_Misc_Coin_01",
                description = "不问对错，只认合同。自由佣兵走过每一座城市、每一片战场，卖的是剑，也是命。\n\n有人鄙视他们，也有人离不开他们。\n\n报酬收好了，该上路了。",
                tiers = MakeTiers("佣兵", { "老练佣兵", "佣兵队长", "传奇佣兵", "佣兵王" })
            },
            {
                id = "TavernBrawler",
                name = "酒馆打手",
                reqFaction = "Neutral",
                icon = "Interface\\Icons\\INV_Mace_01",
                description =
                "没有军队，没有军功，只有一间酒馆和一群喝多了的客人。酒馆打手的战场是吧台和桌椅，武器是啤酒杯和板凳。\n\n他们的规矩只有一条：砸坏的东西，记在对方账上。老板娘说他们是店里的镇店之宝，也是最贵的损耗。\n\n今晚也有人要被扔出去。希望不是你。",
                tiers = MakeTiers("打手", { "吧台霸主", "镇店之宝", "酒馆传说", "拆店之王" })
            },
        }
    },
    ["ROGUE"] = {
        className = "潜行者",
        classColor = RAID_CLASS_COLORS["ROGUE"],
        factions = {
            {
                id = "SI7",
                name = "军情七处",
                reqFaction = "Alliance",
                icon = "Interface\\Icons\\INV_ThrowingKnife_04",
                description = "暴风城的暗影机构。军情七处的特工没有名字，也没有墓碑，用情报、毒药与匕首守护联盟看不见的另一面。\n\n他们的存在被否认，他们的功绩无人知晓。\n\n从现在起，你的名字到此为止。",
                tiers = MakeTiers("特工", { "高级特工", "行动主管", "影子指挥官", "暗影大师" })
            },
            {
                id = "Uncrowned",
                name = "无冕者密探",
                reqFaction = "Horde",
                icon = "Interface\\Icons\\Ability_Stealth",
                description = "无冕者是部落阴影中的刺客与情报员。他们不穿战袍，不举旗帜，只在需要的时候出现在需要的位置。\n\n没有头衔的人，才最清楚头衔有多脆弱。\n\n黑暗里的路，你比谁都熟。",
                tiers = MakeTiers("密探", { "影行者", "暗杀教官", "无冕使者", "无冕之王" })
            },
            {
                id = "Pirate",
                name = "血帆海盗",
                reqFaction = "Neutral",
                icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
                description = "血帆海盗以海为家，以劫掠为生。他们不受任何王国约束，也不被任何港口信任。\n\n每一面黑色的帆下，都有一段不愿提起的往事。\n\n风向对了，就起航。",
                tiers = MakeTiers("水手", { "大副", "船长", "海盗领主", "海盗王" })
            },
            {
                id = "Scoundrel",
                name = "无耻混蛋",
                reqFaction = "Neutral",
                icon = "Interface\\Icons\\Ability_BackStab",
                description =
                "规矩是写给别人看的。无耻混蛋不讲武德，也不讲道义，最擅长的是在你转头的那一秒，出现在你背后。\n\n他们偷东西从不空手而归，打架从不堂堂正正，输了就跑，赢了就拿。有人骂他们下流，他们也不反驳——毕竟你的钱包还在他们口袋里。\n\n恭喜，今天的主角就是你。记得先把对方的口袋翻一遍。",
                tiers = MakeTiers("无赖", { "口袋猎手", "背刺专家", "江湖老赖", "无耻之王" })
            },
        }
    },
    ["HUNTER"] = {
        className = "猎人",
        classColor = RAID_CLASS_COLORS["HUNTER"],
        factions = {
            {
                id = "Ranger",
                name = "游侠",
                reqFaction = "Alliance",
                icon = "Interface\\Icons\\INV_Weapon_Bow_07",
                description = "游侠是穿行于荒野的孤独猎手，追踪猎物，也守护着林间的平衡。\n\n无论在哪片森林，他们都信奉同一条规矩：箭射出去，就不能后悔。\n\n你的目标，就在前方。",
                tiers = MakeTiers("游侠", { "林地斥候", "游侠队长", "边境守望者", "游侠领主" })
            },
            {
                id = "Rifleman",
                name = "火枪手",
                reqFaction = "Alliance",
                icon = "Interface\\Icons\\INV_Weapon_Rifle_01",
                description =
                "矮人与侏儒的火枪，是联盟猎人中最嘈杂、也最准的一种。火枪手相信弓箭已经是过去，现在的世界要用火药来说话。\n\n每一枪都要装填、瞄准，再让整个山谷替它回响。他们有句口头禅：听见枪声的时候，就已经晚了。\n\n铁炉堡的火药库向你敞开，下一个靶子在哪里？",
                tiers = MakeTiers("火枪手", { "神枪手", "狙击教官", "枪炮大师", "火枪统领" })
            },
            {
                id = "ShadowHunter",
                name = "暗影猎手",
                reqFaction = "Horde",
                icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",
                description = "暗影猎手是巨魔猎人中最接近洛阿的一群人，他们借神灵之力追踪猎物，也追踪猎物的恐惧。\n\n在丛林里，他们既是猎手，也是祭司。\n\n洛阿指向的方向，就是你的猎场。",
                tiers = MakeTiers("猎手", { "丛林追踪者", "洛阿猎手", "暗影狩猎者", "神选猎手" })
            },
            {
                id = "WildHunter",
                name = "独行猎手",
                reqFaction = "Neutral",
                icon = "Interface\\Icons\\Ability_Hunter_BeastCall",
                description =
                "没有部族，没有誓言，只有一个伙伴和一片荒野。独行猎手靠着耐心、脚力与野兽的默契活下来。\n\n他们不介入战争，却总能在战争的边缘看见别人看不到的东西。\n\n荒野很大，足够你一直走下去。",
                tiers = MakeTiers("猎人", { "荒野追迹者", "孤影弓手", "兽语者", "荒野传说" })
            },
        }
    },
    ["SHAMAN"] = {
        className = "萨满祭司",
        classColor = RAID_CLASS_COLORS["SHAMAN"],
        factions = {
            {
                id = "StandardShaman",
                name = "先祖萨满",
                reqFaction = "Horde",
                icon = "Interface\\Icons\\Spell_Nature_AncestralGuardian",
                description = "萨满祭司是兽人与牛头人古老的传统，他们与元素、图腾和先祖对话。\n\n他们的力量不属于自己，而来自大地、风、火与水的约定。\n\n倾听吧，元素正在呼唤你。",
                tiers = MakeTiers("萨满", { "图腾守护者", "元素行者", "先祖之声", "部族长老" })
            },
            {
                id = "EarthenRing",
                name = "大地之环",
                reqFaction = "Neutral",
                icon = "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02",
                description = "大地之环是各族萨满共同的团体，他们不效忠任何阵营，只守护世界本身的平衡。\n\n当元素失衡，大地之环就会出现在每一个需要他们的地方。\n\n无论你从哪里来，元素都不问出身。",
                tiers = MakeTiers("萨满", { "元素使者", "大地使者", "环之长老", "大地之环领袖" })
            },
        }
    },
}

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- 玩家阵营是否能选这个流派
local function IsFactionUsable(f)
    return f.reqFaction == "Neutral" or f.reqFaction == playerFaction
end

local function FindFaction(classData, factionID)
    if not classData or not classData.factions then return nil end
    for _, f in ipairs(classData.factions) do
        if f.id == factionID then return f end
    end
    return nil
end

-- 数据自检：保证 previewClass / currentFaction / previewFaction 都指向真实存在的数据
if not FlavorData[AP_DB.flavor.previewClass] then
    AP_DB.flavor.previewClass = FlavorData[realClassToken] and realClassToken or "DRUID"
end

do
    local ownData = FlavorData[AP_DB.flavor.currentClass]
    if ownData then
        local cur = FindFaction(ownData, AP_DB.flavor.currentFaction)
        -- 流派不存在，或者和玩家阵营不符（例如换了角色/阵营）时，重新选一个可用的
        if not cur or not IsFactionUsable(cur) then
            local pick = ownData.factions[1]
            for _, f in ipairs(ownData.factions) do
                if IsFactionUsable(f) then
                    pick = f; break
                end
            end
            AP_DB.flavor.currentFaction = pick.id
        end
    end
    if not FindFaction(FlavorData[AP_DB.flavor.previewClass], AP_DB.flavor.previewFaction) then
        AP_DB.flavor.previewFaction = FlavorData[AP_DB.flavor.previewClass].factions[1].id
    end
end

-- ==========================================
-- 2. 逻辑层 (Manager Layer)
-- ==========================================
local FlavorManager = {}

function FlavorManager.GetCurrentFactionData()
    local classData = FlavorData[AP_DB.flavor.currentClass]
    if not classData or not classData.factions then return nil, nil end
    return FindFaction(classData, AP_DB.flavor.currentFaction) or classData.factions[1], classData
end

function FlavorManager.GetPreviewFactionData()
    local classData = FlavorData[AP_DB.flavor.previewClass]
    if not classData or not classData.factions then return nil, classData end
    return FindFaction(classData, AP_DB.flavor.previewFaction) or classData.factions[1], classData
end

function FlavorManager.GetTierInfo(selectedData)
    if not selectedData or not selectedData.tiers then return nil, nil, 0 end
    local currentRep = AP_DB.flavor.rep[selectedData.id] or 0
    local currentTier = selectedData.tiers[1]
    local nextTier = nil
    for i, tier in ipairs(selectedData.tiers) do
        if currentRep >= (tier.exp or 0) then
            currentTier = tier
            nextTier = selectedData.tiers[i + 1]
        end
    end
    return currentTier, nextTier, currentRep
end

function FlavorManager.AddHistory(text)
    -- 和上一条完全相同时不重复记录（比如反复进出同一区域）
    if AP_DB.flavor.history[1] == text then return end
    table.insert(AP_DB.flavor.history, 1, text)
    while #AP_DB.flavor.history > 5 do table.remove(AP_DB.flavor.history) end
    if AP_FlavorUI and AP_FlavorUI.RefreshHistory then AP_FlavorUI.RefreshHistory() end
end

function FlavorManager.ConvertFaction(newFactionID)
    if newFactionID == AP_DB.flavor.currentFaction then return end
    -- 只允许转投本职业下、且玩家阵营可用的流派
    local newData = FindFaction(FlavorData[AP_DB.flavor.currentClass], newFactionID)
    if not newData or not IsFactionUsable(newData) then return end

    AP_DB.flavor.currentFaction = newFactionID
    AP_DB.flavor.rep[newFactionID] = 0
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd700[AP]|r 你已正式转投 " .. newData.name .. "，声望已清零。")
    UIErrorsFrame:AddMessage("你已转投 " .. newData.name, 1, 0.82, 0, 1)
    FlavorManager.AddHistory("转投了 " .. newData.name)
    if AP_FlavorUI and AP_FlavorUI.Refresh then AP_FlavorUI.Refresh() end
end

function FlavorManager.AddReputation(amount)
    local selectedData = FlavorManager.GetCurrentFactionData()
    if not selectedData then return end
    local oldTier = FlavorManager.GetTierInfo(selectedData)
    AP_DB.flavor.rep[selectedData.id] = (AP_DB.flavor.rep[selectedData.id] or 0) + amount
    local newTier = FlavorManager.GetTierInfo(selectedData)

    DEFAULT_CHAT_FRAME:AddMessage("|cff0070dd你获得了 " .. amount .. " 点 [" .. selectedData.name .. "] 声望。|r")
    UIErrorsFrame:AddMessage("你获得了 " .. amount .. " 点 [" .. selectedData.name .. "] 声望", 0, 0.5, 1, 1)

    if oldTier and newTier and oldTier.level < newTier.level then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd700[AP]|r 你的 [" ..
            selectedData.name .. "] 头衔已变更为：|cffffd700" .. newTier.name .. "|r")
        UIErrorsFrame:AddMessage("[" .. selectedData.name .. "] 头衔提升：" .. newTier.name, 1, 0.82, 0, 1)
        FlavorManager.AddHistory("头衔变更为 " .. newTier.name)
    end
    if AP_FlavorUI and AP_FlavorUI.Refresh then AP_FlavorUI.Refresh() end
end

AP_FlavorManager = FlavorManager

-- 转化流派前弹出确认框（声望清零不可逆）
StaticPopupDialogs["AP_FLAVOR_CONVERT_CONFIRM"] = {
    text = "确定要转投 |cffffd700%s|r 吗？\n\n你在当前流派的声望将会清零。",
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(self, data)
        if data then FlavorManager.ConvertFaction(data) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ==========================================
-- 3. 表现层 (UI Layer)
-- ==========================================
local UI = {}
AP_FlavorUI = UI

-- 职业书签顺序：默认和游戏内一致（战士、圣骑士、猎人、潜行者、牧师、萨满、法师、术士、德鲁伊），
-- 但玩家自己的职业永远排在第一枚，其余按上面的顺序往后串。
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local classesList = {}
do
    -- 玩家职业如果在图鉴里有数据，就第一个放；没有（例如数据还没做的职业）就退回德鲁伊打头
    local firstClass = FlavorData[realClassToken] and realClassToken or "DRUID"
    table.insert(classesList, firstClass)
    for _, token in ipairs(CLASS_ORDER) do
        if token ~= firstClass then table.insert(classesList, token) end
    end
end

-- ==========================================
-- 职业书签：彩旗状丝带，从书页左缘垂出
-- 丝带贴图是白灰色的燕尾旗 (Media/Ribbon.tga)，运行时用职业色上色
-- ==========================================
local RIBBON_TEXTURE = "Interface\\AddOns\\AzerothParallel\\Media\\Ribbon.tga"
local RIBBON_W, RIBBON_H, RIBBON_STEP = 124, 44, 48 -- 丝带尺寸 / 纵向间距
local RIBBON_BASE_X = 15                            -- 丝带压进书页的长度（越大越“插”进书里）
local RIBBON_POP_SELECTED, RIBBON_POP_HOVER = 12, 6 -- 选中 / 悬停时向外拉出的距离
local ribbonButtons = {}

local function ApplyRibbonLayout(btn)
    local pop = 0
    if btn.isSelected then
        pop = RIBBON_POP_SELECTED
    elseif btn.isHover then
        pop = RIBBON_POP_HOVER
    end
    btn:ClearAllPoints()
    btn:SetPoint("TOPRIGHT", LeftPage, "TOPLEFT", RIBBON_BASE_X - pop, btn.baseY)
    btn.body:SetAlpha(btn.isSelected and 1 or 0.88)
    btn:SetFrameLevel(p1:GetFrameLevel() + (btn.isSelected and 6 or 3))
end

for i, classID in ipairs(classesList) do
    local data = FlavorData[classID]
    local c = data.classColor or RAID_CLASS_COLORS[classID] or { r = 0.5, g = 0.5, b = 0.5 }

    local btn = CreateFrame("Button", nil, p1)
    btn:SetSize(RIBBON_W, RIBBON_H)
    btn.baseY = -24 - (i - 1) * RIBBON_STEP

    -- 投在书页上的阴影（同一张贴图染成黑色，向右下偏一点）
    local shadow = btn:CreateTexture(nil, "BACKGROUND")
    shadow:SetTexture(RIBBON_TEXTURE)
    shadow:SetVertexColor(0, 0, 0, 0.4)
    shadow:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    shadow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)

    -- 丝带本体
    local body = btn:CreateTexture(nil, "ARTWORK")
    body:SetTexture(RIBBON_TEXTURE)
    body:SetAllPoints()
    body:SetVertexColor(c.r, c.g, c.b)
    btn.body = body

    -- 悬停时微微提亮
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(RIBBON_TEXTURE)
    hl:SetAllPoints()
    hl:SetVertexColor(1, 1, 1, 0.3)
    hl:SetBlendMode("ADD")

    -- 文字：浅色丝带（牧师白、潜行者黄等）用深色字，深色丝带用浅色描边字
    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER", 2, 0)
    text:SetText(data.className)
    local fontPath = text:GetFont()
    local luminance = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    if luminance > 0.62 then
        text:SetFont(fontPath, 15, "")
        text:SetTextColor(0.16, 0.09, 0.03)
    else
        text:SetFont(fontPath, 15, "OUTLINE")
        text:SetTextColor(1, 0.96, 0.84)
    end

    btn:SetScript("OnEnter", function(self)
        self.isHover = true; ApplyRibbonLayout(self)
    end)
    btn:SetScript("OnLeave", function(self)
        self.isHover = false; ApplyRibbonLayout(self)
    end)
    btn:SetScript("OnClick", function()
        AP_DB.flavor.previewClass = classID
        local newClassData = FlavorData[classID]
        if newClassData and newClassData.factions then
            -- 预览职业切换时，优先定位到玩家自己当前流派（如果是同一职业），否则第一个
            local target = newClassData.factions[1].id
            if classID == AP_DB.flavor.currentClass then
                target = AP_DB.flavor.currentFaction
            end
            AP_DB.flavor.previewFaction = target
        end
        UI.Refresh()
    end)

    ribbonButtons[classID] = btn
    ApplyRibbonLayout(btn)
end

function UI.RefreshRibbons()
    for classID, btn in pairs(ribbonButtons) do
        btn.isSelected = (classID == AP_DB.flavor.previewClass)
        ApplyRibbonLayout(btn)
    end
end

-- 左页内容区：统一宽度并相对 LeftPage 水平居中
-- 名牌 / 流派 Tab / 声望条都挂在它上面，左右边缘自然对齐；想整体左右微调就改下面的 offsetX
local CONTENT_WIDTH = 340
local leftContent = CreateFrame("Frame", nil, LeftPage)
leftContent:SetSize(CONTENT_WIDTH, 400)
leftContent:SetPoint("TOP", LeftPage, "TOP", 0, 0)

-- 名牌区域
local namePlate = CreateFrame("Frame", nil, leftContent, "BackdropTemplate")
namePlate:SetSize(CONTENT_WIDTH, 44)
namePlate:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -15)
namePlate:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
namePlate:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
namePlate:SetBackdropBorderColor(0.8, 0.7, 0.5, 1)

local nameLabel = namePlate:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
nameLabel:SetPoint("CENTER", 0, 0)
nameLabel:SetFont(nameLabel:GetFont(), 22, "OUTLINE")
nameLabel:SetText("|cffd4af37" .. AP_DB.flavor.customName .. "|r")

local nameInput = CreateFrame("EditBox", nil, namePlate)
nameInput:SetSize(200, 30)
nameInput:SetPoint("CENTER", 0, 0)
nameInput:SetFontObject("GameFontNormalLarge")
nameInput:SetAutoFocus(false)
nameInput:SetMaxLetters(12) -- 限制名字长度，避免超出名牌
nameInput:Hide()
nameInput:SetScript("OnEnterPressed", function(self)
    if self:GetText() ~= "" then AP_DB.flavor.customName = self:GetText() end
    nameLabel:SetText("|cffd4af37" .. AP_DB.flavor.customName .. "|r")
    self:Hide(); nameLabel:Show(); self:ClearFocus()
end)
nameInput:SetScript("OnEscapePressed", function(self)
    self:Hide(); nameLabel:Show(); self:ClearFocus()
end)

local pencilBtn = CreateFrame("Button", nil, namePlate)
pencilBtn:SetSize(24, 24)
pencilBtn:SetPoint("RIGHT", -15, 0)
local pencilIcon = pencilBtn:CreateTexture(nil, "ARTWORK")
pencilIcon:SetAllPoints()
pencilIcon:SetTexture("Interface\\Icons\\INV_Misc_Quill_01")
pencilBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
pencilBtn:SetScript("OnClick", function()
    nameLabel:Hide(); nameInput:Show(); nameInput:SetText(AP_DB.flavor.customName)
    nameInput:SetFocus(); nameInput:HighlightText()
end)

local factionTabContainer = CreateFrame("Frame", nil, leftContent)
factionTabContainer:SetSize(CONTENT_WIDTH, 35)
factionTabContainer:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -65)

-- ★ 流派 Tab 按钮池：按钮只创建一次，之后每次 Refresh 复用
local TAB_MAX_WIDTH, TAB_HEIGHT, TAB_GAP, TAB_PADDING = 110, 26, 4, 14
local TAB_FONT_SIZE, TAB_MIN_FONT_SIZE = 13, 9
local tabPool = {}

local function AcquireTab(index)
    local tab = tabPool[index]
    if not tab then
        -- 匿名按钮 (name = nil)，所以不能用 _G[tab:GetName() .. "Text"]，统一用 GetFontString()
        tab = CreateFrame("Button", nil, factionTabContainer, "UIPanelButtonTemplate")
        tab:SetHeight(TAB_HEIGHT)

        local fs = tab:GetFontString()
        if fs then
            tab.apFontPath = fs:GetFont() -- 记下字体路径，后面按需调整字号
            if tab.apFontPath then
                fs:SetFont(tab.apFontPath, TAB_FONT_SIZE, "OUTLINE")
            end
            fs:SetWordWrap(false) -- 不折行
        end

        tabPool[index] = tab
    end
    return tab
end

local levelDisplay = LeftPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
levelDisplay:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -105)
levelDisplay:SetFont(levelDisplay:GetFont(), 20, "OUTLINE")
levelDisplay:SetTextColor(1, 0.8, 0)

local repBar = CreateFrame("StatusBar", nil, leftContent, "BackdropTemplate")
repBar:SetSize(CONTENT_WIDTH, 20)
repBar:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -140)
repBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
repBar:SetStatusBarColor(0.3, 0.8, 0.3)
repBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
repBar:SetBackdropColor(0, 0, 0, 0.8)

local repText = repBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
repText:SetPoint("CENTER")
repText:SetFont(repText:GetFont(), 12, "OUTLINE")

local nextTierDisplay = LeftPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
nextTierDisplay:SetPoint("TOP", repBar, "BOTTOM", 0, -5)
nextTierDisplay:SetFont(nextTierDisplay:GetFont(), 14, "OUTLINE")
nextTierDisplay:SetTextColor(0.8, 0.8, 0.8)

local historyTitle = LeftPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
historyTitle:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -190)
historyTitle:SetText("|cffffd700最近履历：|r")

local historyText = LeftPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
historyText:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -210)
historyText:SetWidth(CONTENT_WIDTH)
historyText:SetJustifyH("LEFT")
historyText:SetSpacing(5)

local convertBtn = CreateFrame("Button", nil, leftContent, "UIPanelButtonTemplate")
convertBtn:SetSize(180, 30)
convertBtn:SetPoint("TOP", leftContent, "TOP", 0, -330)
convertBtn:SetText("转化流派 (声望清零)")
convertBtn:SetScript("OnClick", function()
    local data = FindFaction(FlavorData[AP_DB.flavor.currentClass], AP_DB.flavor.previewFaction)
    if not data then return end
    -- 弹出确认框，确认后才真正转化
    StaticPopup_Show("AP_FLAVOR_CONVERT_CONFIRM", data.name, nil, data.id)
end)

-- ★ 称谓典籍按钮：点一下，右页从“流派介绍”切换成“技能/天赋称呼对照表”
-- 这个开关只是本插件内部的一页，不会改动游戏里的任何技能名，别人完全看不到。
local showingSpellBook = false
local spellBookBtn = CreateFrame("Button", nil, leftContent, "UIPanelButtonTemplate")
spellBookBtn:SetSize(180, 30)
spellBookBtn:SetPoint("TOP", leftContent, "TOP", 0, -368)
spellBookBtn:SetText("称谓典籍（技能/天赋）")
spellBookBtn:SetScript("OnClick", function()
    showingSpellBook = not showingSpellBook
    UI.Refresh()
end)

local iconFrame = CreateFrame("Frame", nil, RightPage, "BackdropTemplate")
iconFrame:SetSize(80, 80)
iconFrame:SetPoint("TOP", RightPage, "TOP", 0, -20)
iconFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
iconFrame:SetBackdropColor(0, 0, 0, 1)
iconFrame:SetBackdropBorderColor(1, 0.8, 0, 1)
local badgeIcon = iconFrame:CreateTexture(nil, "ARTWORK")
badgeIcon:SetAllPoints()

local scrollFrame = CreateFrame("ScrollFrame", nil, RightPage, "UIPanelScrollFrameTemplate")
scrollFrame:SetSize(310, 400)
scrollFrame:SetPoint("TOPLEFT", 55, -120)
local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollFrame:SetScrollChild(scrollChild)
scrollChild:SetWidth(280)
scrollChild:SetHeight(1)

local descText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
descText:SetPoint("TOPLEFT", 0, 0)
descText:SetWidth(280)
descText:SetJustifyH("LEFT")
descText:SetSpacing(12)
descText:SetFont(descText:GetFont(), 18, "")

-- “反映到游戏内提示”的开关：勾选后，鼠标悬停技能时第一行显示本流派的称呼。
-- 只包装 tooltip 的显示函数，不碰 GetSpellInfo，别人看不到，也不会影响其他插件。
local tooltipToggle = CreateFrame("CheckButton", "AP_TooltipAliasToggle", RightPage, "ChatConfigCheckButtonTemplate")
tooltipToggle:SetPoint("TOPLEFT", RightPage, "TOPLEFT", 50, -32)
local toggleText = _G[tooltipToggle:GetName() .. "Text"]
toggleText:SetText("应用到游戏内提示（仅自己可见）")
toggleText:SetFont(toggleText:GetFont(), 14, "OUTLINE")
tooltipToggle:SetChecked(AP_DB.flavor.tooltipAlias and true or false)
tooltipToggle:SetScript("OnClick", function(self)
    local on = self:GetChecked() and true or false
    AP_DB.flavor.tooltipAlias = on
    if AP_TooltipAlias then AP_TooltipAlias.SetEnabled(on) end
end)
tooltipToggle:Hide() -- 只在“称谓典籍”模式下显示

-- 称谓典籍的滚动区：和“流派介绍”共用右页，同一时间只显示其中一个。
-- 顶部要给上面的开关留位置，所以从 -72 开始。
local spellScrollFrame = CreateFrame("ScrollFrame", nil, RightPage, "UIPanelScrollFrameTemplate")
spellScrollFrame:SetSize(310, 400)
spellScrollFrame:SetPoint("TOPLEFT", 55, -72)
local spellChild = CreateFrame("Frame", nil, spellScrollFrame)
spellScrollFrame:SetScrollChild(spellChild)
spellChild:SetWidth(280)
spellChild:SetHeight(1)

local spellText = spellChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
spellText:SetPoint("TOPLEFT", 0, 0)
spellText:SetWidth(280)
spellText:SetJustifyH("LEFT")
spellText:SetSpacing(8)
spellText:SetFont(spellText:GetFont(), 16, "")
spellScrollFrame:Hide()

-- 记住上一次显示的是哪个流派，切流派时把滚动条拉回顶部
local lastSpellKey

-- 把“职业通用词条”和“流派专属覆盖”合成一份完整列表：
--   AP_Terms[职业]._common = 该职业所有技能/天赋的默认称呼
--   AP_Terms[职业][流派id] = 只写这个流派叫法不同的条目，用来覆盖同名的通用词条
-- 这样不用把同一个技能在 3~5 个流派里各抄一遍，改一个技能也只需要改通用那份。
local function BuildTermList(classToken, factionID)
    local classTerms = AP_Terms and AP_Terms[classToken]
    if not classTerms then return nil end

    local list, byOfficial = {}, {}
    local function Add(term)
        if not term or not term.official then return end
        local existing = byOfficial[term.official]
        if existing then
            -- 同名技能：流派覆盖的那一份只替换称呼/备注
            if term.alias then existing.alias = term.alias end
            if term.note then existing.note = term.note end
            if term.category then existing.category = term.category end
        else
            -- 拷贝一份再放进结果表，避免运行时修改到 AP_Terms 里的原始数据
            local copy = {
                category = term.category,
                official = term.official,
                alias = term.alias,
                note = term.note,
            }
            table.insert(list, copy)
            byOfficial[term.official] = copy
        end
    end

    if classTerms._common then
        for _, term in ipairs(classTerms._common) do Add(term) end
    end
    local factionTerms = classTerms[factionID]
    if factionTerms then
        for _, term in ipairs(factionTerms) do Add(term) end
    end

    if #list == 0 then return nil end
    return list
end

-- 导出给 Overrides.lua 用：它需要知道“当前流派有哪些称呼”，才能改鼠标提示。
AP_FlavorManager.GetTermList = BuildTermList

function UI.RefreshSpellBook(previewData)
    if not previewData then
        spellText:SetText("|cff888888暂无数据|r")
        return
    end

    -- 词条 = 职业通用 + 流派覆盖，具体合并规则见上面的 BuildTermList
    local terms = BuildTermList(AP_DB.flavor.previewClass, previewData.id)
    local key = tostring(AP_DB.flavor.previewClass) .. ":" .. tostring(previewData.id)

    if not terms or #terms == 0 then
        spellText:SetText("|cffffd700" .. previewData.name .. " · 称谓典籍|r\n\n" ..
            "|cff888888该流派暂时没有词条。\n\n词条库按“职业 → 流派”整理，目前只有德鲁伊的三个流派有初稿，其他职业会陆续补上。|r")
    else
        local lines = { "|cffffd700" .. previewData.name .. " · 称谓典籍|r\n" }
        local lastCategory
        for _, term in ipairs(terms) do
            -- 换了分类就插一条金色小标题（同分类的条目自动归在一起）
            if term.category and term.category ~= lastCategory then
                table.insert(lines, (lastCategory and "\n" or "") .. "|cffd4af37【" .. term.category .. "】|r")
                lastCategory = term.category
            end
            -- 一行：绿色 = 本流派称呼，灰色 = 官方原名，方便对照
            table.insert(lines, "|cff9be54f" .. (term.alias or "?") .. "|r |cff888888（官方：" .. (term.official or "?") .. "）|r")
            -- 有备注的话，缩进一行灰字补一句说明
            if term.note and term.note ~= "" then
                table.insert(lines, "|cff888888　　" .. term.note .. "|r")
            end
        end
        spellText:SetText(table.concat(lines, "\n"))
    end

    spellChild:SetHeight(spellText:GetStringHeight() + 30)
    if lastSpellKey ~= key then
        spellScrollFrame:SetVerticalScroll(0)
        lastSpellKey = key
    end
end

function UI.RefreshHistory()
    local lines = {}
    for _, text in ipairs(AP_DB.flavor.history) do table.insert(lines, "• " .. text) end
    if #lines == 0 then
        historyText:SetText("|cff888888暂无履历，去冒险吧。|r")
    else
        historyText:SetText(table.concat(lines, "\n"))
    end
end

local lastShownFactionID = nil

function UI.Refresh()
    -- 按钮文字跟着右页模式走：已经在典籍里，就提示可以返回
    spellBookBtn:SetText(showingSpellBook and "返回流派介绍" or "称谓典籍（技能/天赋）")
    UI.RefreshRibbons() -- 选中的职业书签向外拉出一截
    local previewData, previewClassData = FlavorManager.GetPreviewFactionData()

    -- 先把池子里的按钮全部隐藏，下面按需 Show
    for _, tab in ipairs(tabPool) do tab:Hide() end

    -- 动态渲染 Tab (复用按钮池，宽度按流派数量自适应，保证不超出容器)
    if previewClassData and previewClassData.factions then
        local count = #previewClassData.factions
        local selectedID = previewData and previewData.id or AP_DB.flavor.previewFaction
        local containerWidth = factionTabContainer:GetWidth()
        local avail = containerWidth - TAB_GAP * (count - 1)

        -- 第一遍：按文字实际宽度算出每个按钮需要多宽（"月之女祭司"这类长名字不会再被截断）
        local widths, textWidths, sum = {}, {}, 0
        for i, faction in ipairs(previewClassData.factions) do
            local tab = AcquireTab(i)
            local fs = tab:GetFontString()
            if fs and tab.apFontPath then
                -- 先恢复标准字号、自动宽度，再量文字真实宽度
                fs:SetFont(tab.apFontPath, TAB_FONT_SIZE, "OUTLINE")
                fs:SetWidth(0)
            end
            tab:SetText(faction.name)
            textWidths[i] = fs and fs:GetStringWidth() or 60
            widths[i] = textWidths[i] + TAB_PADDING
            sum = sum + widths[i]
        end

        -- 放不下就等比缩小；有富余就平均加宽（单个按钮不超过 TAB_MAX_WIDTH）
        if sum > avail then
            local scale = avail / sum
            for i = 1, count do widths[i] = widths[i] * scale end
        else
            local extra = (avail - sum) / count
            for i = 1, count do widths[i] = math.min(TAB_MAX_WIDTH, widths[i] + extra) end
        end

        local total = TAB_GAP * (count - 1)
        for i = 1, count do total = total + widths[i] end
        local x = (containerWidth - total) / 2 -- 整行在容器内居中

        -- 第二遍：定位、上色、绑定点击
        for i, faction in ipairs(previewClassData.factions) do
            local tab = tabPool[i]
            tab:SetWidth(widths[i])
            local fs = tab:GetFontString()
            if fs then
                -- 按钮被压窄、放不下标准字号时，自动缩小字号（最小 TAB_MIN_FONT_SIZE），不再出现 "..."
                local space = widths[i] - 6
                local size = TAB_FONT_SIZE
                if textWidths[i] > space then
                    size = math.max(TAB_MIN_FONT_SIZE, math.floor(TAB_FONT_SIZE * space / textWidths[i]))
                end
                if tab.apFontPath then fs:SetFont(tab.apFontPath, size, "OUTLINE") end
                fs:SetWidth(widths[i] - 2)
            end

            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", factionTabContainer, "TOPLEFT", x, 0)
            x = x + widths[i] + TAB_GAP

            -- 当前选中的高亮为绿色，其余恢复普通文字
            if selectedID == faction.id then
                tab:SetText("|cff00ff00" .. faction.name .. "|r")
            else
                tab:SetText(faction.name)
            end

            tab:SetScript("OnClick", function()
                AP_DB.flavor.previewFaction = faction.id
                UI.Refresh()
            end)

            tab:Show()
        end
    end

    local canConvert = false
    if AP_DB.flavor.previewClass == AP_DB.flavor.currentClass and previewData then
        if previewData.id ~= AP_DB.flavor.currentFaction and IsFactionUsable(previewData) then
            canConvert = true
        end
    end

    if canConvert then
        convertBtn:Show()
    else
        convertBtn:Hide()
    end

    if not previewData then return end

    -- 右页两种模式二选一：流派介绍（默认） / 称谓典籍
    if showingSpellBook then
        iconFrame:Hide()
        scrollFrame:Hide()
        spellScrollFrame:Show()
        tooltipToggle:Show()
        UI.RefreshSpellBook(previewData)
    else
        iconFrame:Show()
        scrollFrame:Show()
        spellScrollFrame:Hide()
        tooltipToggle:Hide()
    end

    badgeIcon:SetTexture(previewData.icon or FALLBACK_ICON)
    descText:SetText(previewData.description or "")
    scrollChild:SetHeight(descText:GetStringHeight() + 40)

    -- 切换到不同流派时，说明文字滚回顶部（声望变化触发的刷新不重置）
    if lastShownFactionID ~= previewData.id then
        scrollFrame:SetVerticalScroll(0)
        lastShownFactionID = previewData.id
    end

    -- 只有“正在看自己当前流派”才算当前身份。
    -- 预览别的流派/职业时，声望条显示的是那个流派自己的存档数据，并用灰色区分。
    local isOwn = (AP_DB.flavor.previewClass == AP_DB.flavor.currentClass
        and previewData.id == AP_DB.flavor.currentFaction)

    if isOwn then
        repBar:SetStatusBarColor(0.3, 0.8, 0.3)
    else
        repBar:SetStatusBarColor(0.5, 0.5, 0.5)
    end

    local tier, nextTier, rep = FlavorManager.GetTierInfo(previewData)
    if tier then
        if isOwn then
            levelDisplay:SetText("|cffffd700当前身份：|r" .. tier.name)
        else
            -- 明确写“未激活”，避免把这里的 0 声望误当成自己当前流派的经验
            levelDisplay:SetText("|cff888888预览：" .. previewData.name .. " · " .. tier.name .. "（未激活）|r")
        end
        if nextTier then
            local prevExp = tier.exp or 0
            local nextExp = nextTier.exp
            repBar:SetMinMaxValues(prevExp, nextExp)
            repBar:SetValue(rep)
            repText:SetText(string.format("%d / %d", rep, nextExp))
            if isOwn then
                nextTierDisplay:SetText("下一阶级：" .. nextTier.name .. " (还需 " .. (nextExp - rep) .. ")")
            else
                nextTierDisplay:SetText("|cff888888预览下一阶级：" .. nextTier.name .. " (还需 " .. (nextExp - rep) .. ")|r")
            end
        else
            repBar:SetMinMaxValues(0, 1)
            repBar:SetValue(1)
            repText:SetText("崇拜")
            nextTierDisplay:SetText(isOwn and "已到达最高阶级。" or "|cff888888该流派已达最高阶级。|r")
        end
    end
end

-- ==========================================
-- 4. 事件层 (安全版修复)
-- ==========================================
local repFrame = CreateFrame("Frame")
repFrame:RegisterEvent("QUEST_TURNED_IN")
repFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

repFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "QUEST_TURNED_IN" then
        FlavorManager.AddReputation(100)
        -- 兼容处理：新一点的内核用 C_QuestLog，老内核（1.12 / 3.3.5 私服常见）没有这个接口。
        -- 拿不到名字时退回“未知任务”，绝不让一个报错打断加声望。
        local title = "未知任务"
        if C_QuestLog and C_QuestLog.GetTitleForQuestID then
            local ok, t = pcall(C_QuestLog.GetTitleForQuestID, arg1)
            if ok and t then title = t end
        elseif GetQuestLogTitle then
            local ok, t = pcall(GetQuestLogTitle, arg1)
            if ok and t then title = t end
        end
        FlavorManager.AddHistory("完成任务：" .. title)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        local zoneName = GetZoneText()
        if zoneName and zoneName ~= "" and zoneName ~= GetRealZoneText() then
            FlavorManager.AddHistory("抵达了 " .. zoneName)
        end
    end
end)

UI.RefreshHistory()
UI.Refresh()
