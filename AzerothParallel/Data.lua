-- ==========================================
-- Data.lua: 职业流派数据表（纯数据，无 UI/逻辑）
-- ==========================================
-- 从 Flavor.lua 抽出来，方便单独查改职业、流派、头衔、图标。
-- 加载顺序见 AzerothParallel.toc：Core → Terms → Data → Flavor。

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
AP_FlavorData = {
    ["DRUID"] = {
        className = "德鲁伊",
        classColor = RAID_CLASS_COLORS["DRUID"],
        -- 无限服的德鲁伊只有四个种族：暗夜精灵、牛头人、巨魔、天裔。
        -- 每个流派用 races 限定种族；Flavor.lua 会按玩家种族只显示对应的一个。
        factions = {
            {
                id = "Cenarius",
                name = "塞纳里奥",
                -- 流派主题色：高光特写优先用它，不配则回退职业色
                themeColor = { r = 0.34, g = 0.72, b = 0.46 }, -- 月林绿
                reqFaction = "Alliance",
                races = { "NightElf" }, -- 暗夜精灵
                icon = "Interface\\Icons\\Spell_Nature_StarFall",
                description =
                "塞纳里奥议会的德鲁伊之道传承自上古之夜。暗夜精灵在月光下沉睡于翡翠梦境，也在海加尔山的树根之间守望世界之树。\n\n他们既是祭司，也是野兽；既向艾露恩祈祷，也倾听每一棵树的声音。\n\n月光照在你的爪尖，森林在等你回去。",
                tiers = MakeTiers("德鲁伊", { "月林学徒", "塞纳里奥守护者", "大德鲁伊", "半神之友" })
            },
            {
                id = "Runetotem",
                name = "符文图腾",
                themeColor = { r = 0.72, g = 0.46, b = 0.22 }, -- 大地棕
                reqFaction = "Horde",
                races = { "Tauren" }, -- 牛头人
                icon = "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02",
                description =
                "符文图腾部族把德鲁伊之道看作大地母亲的呼吸。牛头人在莫高雷的草原上与科多兽同行，用图腾与先祖对话，把每一场战斗都当作对自然的敬礼。\n\n他们不追求奥术的答案，而是倾听土地的疼痛。\n\n大地母亲在看着你，别让她的孩子白白流血。",
                tiers = MakeTiers("德鲁伊", { "大地学徒", "符文行者", "符文长老", "大地之子的回声" })
            },
            {
                id = "Loa",
                name = "洛阿德鲁伊",
                themeColor = { r = 0.62, g = 0.36, b = 0.82 }, -- 洛阿紫
                reqFaction = "Horde",
                races = { "Troll" }, -- 巨魔
                icon = "Interface\\Icons\\Ability_Druid_TigersRoar",
                description =
                "巨魔德鲁伊的力量来自洛阿，尤其是迅猛龙之神贡克。暗矛部族的德鲁伊在丛林中学习野兽的形状，把贡克的狡黠与猎手的耐心一起带进战斗。\n\n他们不崇拜月亮，也不向大地母亲祈祷；他们与神灵讨价还价，然后变成神灵想要的样子。\n\n洛阿在听，你的獠牙准备好了吗？",
                tiers = MakeTiers("德鲁伊", { "洛阿侍者", "兽形信徒", "贡克之爪", "洛阿神选" })
            },
            {
                id = "Nightclaw",
                name = "夜爪德鲁伊",
                themeColor = { r = 0.58, g = 0.38, b = 0.78 }, -- 暗夜紫
                reqFaction = "Neutral",
                races = { "Tianyi" }, -- 天裔（自定义种族；Flavor.lua 里做兜底归类）
                icon = "Interface\\Icons\\Ability_Druid_Rake",
                description =
                "夜爪不是某个组织的名字，而是一种选择。当天裔的族人分裂为元素与奥术两派时，仍有一小群人选择走入荒野，倾听草木与野兽的低语。\n\n他们不效忠分裂后的任何一方，也不愿被部族的旗帜绑住。他们是夜爪，是申多雷德鲁伊血脉中几乎断绝的回响。现在，荒野在呼唤你。",
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
