# ============================================================
# culture.ps1 — 文化气：讲典故 + 对名句
# 依赖（主脚本提供）：Show-Bubble / Speak-Text / Write-Err
# ============================================================

# 典故：只收出处明确、经得起核对的
$script:CultureAllusions = @(
    @{ name = '刻舟求剑'; src = '《吕氏春秋·察今》'; text = '楚人过江，剑掉进水里，他在船舷上刻个记号，说剑是从这儿掉的。船走了，剑没走，等靠岸再按记号下水找，当然找不到。' },
    @{ name = '守株待兔'; src = '《韩非子·五蠹》'; text = '宋国农夫见兔子撞树桩死了，从此放下农具守着树桩，指望再捡一只。兔子没再来，田也荒了。' },
    @{ name = '掩耳盗铃'; src = '《吕氏春秋·自知》'; text = '有人想偷铃铛，怕响，就捂住自己的耳朵，以为别人也听不见。' },
    @{ name = '画蛇添足'; src = '《战国策·齐策二》'; text = '几个人比赛画蛇，先画完的人本可以拿酒，却非要给蛇添上脚，结果输给了后面的人。' },
    @{ name = '亡羊补牢'; src = '《战国策·楚策四》'; text = '羊丢了才修羊圈，旁人劝他，他说现在补也不晚。比喻出了问题及时补救。' },
    @{ name = '卧薪尝胆'; src = '《史记·越王勾践世家》'; text = '越王勾践被吴国打败后，睡柴草、尝苦胆，提醒自己不忘耻辱，终于复国。' },
    @{ name = '破釜沉舟'; src = '《史记·项羽本纪》'; text = '项羽渡河救赵，过河后砸破锅、凿沉船，只带三天干粮，让士兵知道没有退路，结果大破秦军。' },
    @{ name = '完璧归赵'; src = '《史记·廉颇蔺相如列传》'; text = '秦王想用城池换赵国的和氏璧，蔺相如看出他没诚意，凭机智把璧完好带回赵国。' },
    @{ name = '一鼓作气'; src = '《左传·庄公十年》'; text = '齐鲁交战，曹刿等齐军擂了三通鼓才让鲁军出击，说打仗靠的是一股气，头通鼓最有劲。' },
    @{ name = '望梅止渴'; src = '《世说新语·假谲》'; text = '曹操行军缺水，说前面有梅林，士兵想到酸梅就流口水，暂时解了渴。' }
)

# 名句对：都是传世名句的原句，不是自拟
$script:CultureCouplets = @(
    @{ up = '海内存知己'; down = '天涯若比邻'; src = '王勃《送杜少府之任蜀州》' },
    @{ up = '欲穷千里目'; down = '更上一层楼'; src = '王之涣《登鹳雀楼》' },
    @{ up = '野火烧不尽'; down = '春风吹又生'; src = '白居易《赋得古原草送别》' },
    @{ up = '两个黄鹂鸣翠柳'; down = '一行白鹭上青天'; src = '杜甫《绝句》' },
    @{ up = '会当凌绝顶'; down = '一览众山小'; src = '杜甫《望岳》' },
    @{ up = '山重水复疑无路'; down = '柳暗花明又一村'; src = '陆游《游山西村》' },
    @{ up = '大漠孤烟直'; down = '长河落日圆'; src = '王维《使至塞上》' },
    @{ up = '落霞与孤鹜齐飞'; down = '秋水共长天一色'; src = '王勃《滕王阁序》' },
    @{ up = '春潮带雨晚来急'; down = '野渡无人舟自横'; src = '韦应物《滁州西涧》' },
    @{ up = '千山鸟飞绝'; down = '万径人踪灭'; src = '柳宗元《江雪》' }
)

function Invoke-CultureAllusion {
    try {
        if (-not $script:CultureAllusions -or $script:CultureAllusions.Count -eq 0) { return $false }
        $one = $script:CultureAllusions[(Get-Random -Maximum $script:CultureAllusions.Count)]
        $say = ('讲个典故——' + $one.name + '，出自' + $one.src + '。' + $one.text)
        try { Show-Bubble $say } catch { }
        try { Speak-Text $say } catch { }
        Write-Err ('CULTURE-ALLUSION ' + $one.name)
        return $true
    } catch { Write-Err ('CULTURE-ERR ' + $_.Exception.Message); return $false }
}

function Invoke-CultureCouplet {
    try {
        if (-not $script:CultureCouplets -or $script:CultureCouplets.Count -eq 0) { return $false }
        $one = $script:CultureCouplets[(Get-Random -Maximum $script:CultureCouplets.Count)]
        $say = ('出个上联：' + $one.up + '。主人对得上吗？答案是——' + $one.down + '，出自' + $one.src + '。')
        try { Show-Bubble $say } catch { }
        try { Speak-Text $say } catch { }
        Write-Err ('CULTURE-COUPLET ' + $one.up)
        return $true
    } catch { Write-Err ('CULTURE-ERR ' + $_.Exception.Message); return $false }
}
