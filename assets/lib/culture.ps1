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

# 外部数据：优先读 assets\data\culture\chengyu.json（可扩到几百条），读不到就用上面内置的
function Load-CultureData {
    if ($script:CultureDataLoading) { return }
    if ($script:CultureDataLoaded) { return }
    $script:CultureDataLoading = $true
    try {
        $p = Join-Path $script:FishAssets 'data\culture\chengyu.json'
        if (Test-Path $p) {
            $raw = Get-Content $p -Raw -Encoding UTF8
            $arr = $raw | ConvertFrom-Json
            $list = @()
            foreach ($x in @($arr)) {
                if ($x.name -and $x.src -and $x.text) {
                    $list += @{ name = [string]$x.name; src = [string]$x.src; text = [string]$x.text }
                }
            }
            if ($list.Count -gt 0) {
                $script:CultureAllusions = $list
                Write-Err ('CULTURE-DATA ' + $list.Count)
            }
        }
    } catch { Write-Err ('CULTURE-DATA-ERR ' + $_.Exception.Message) }
    finally { $script:CultureDataLoading = $false; $script:CultureDataLoaded = $true }
}
Load-CultureData

# 名句对：都是传世名句的原句，不是自拟

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


function Invoke-CultureCouplet([string]$upper = '') {
    # 实时创作：调模型对下联（原创），不套古人现成句子
    try {
        $upper = ([string]$upper).Trim()
        if ($upper) { $upper = $upper.Trim([char]0xFF1A, [char]0x003A, [char]0xFF0C, [char]0x002C, [char]0x0020) }
        if (-not $upper) { try { Show-Bubble '主人出个上联，本鱼来对～' } catch { }; return $true }
        $key = Get-ApiKey
        if (-not $key) { try { Show-Bubble '本鱼没钥匙，对不出来…' } catch { }; return $false }
        $sys = '你是会作对联的小鱼。规则：只输出一句下联，不加解释；字数必须与上联完全相同；词性对仗；平仄尽量相反；内容通顺有意境；必须原创，不得套用古人现成句子。'
        $msgs = @(
            @{ role = 'system'; content = $sys },
            @{ role = 'user'; content = ('上联：' + $upper) }
        )
        $body = @{ model = 'deepseek-flash'; messages = $msgs; max_tokens = 60; temperature = 0.95; thinking = @{ type = 'disabled' } } | ConvertTo-Json -Depth 6
        $http = New-Object System.Net.Http.HttpClient
        $http.Timeout = [TimeSpan]::FromSeconds(30)
        $http.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $key)
        $content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')
        $resp = $http.PostAsync('https://api.deepseek.com/chat/completions', $content).GetAwaiter().GetResult()
        $json = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $obj = $null
        try { $obj = $json | ConvertFrom-Json } catch { }
        $lower = ''
        try { $lower = [string]$obj.choices[0].message.content } catch { }
        $lower = ($lower -replace '[\r\n]+', ' ').Trim()
        $lower = $lower.Trim([char]0xFF1A, [char]0x003A, [char]0x0022, [char]0x3002)
        if (-not $lower) { try { Show-Bubble '这会儿想不出来，等下再对～' } catch { }; return $false }
        $say = ('上联：' + $upper + '。下联：' + $lower + '。这是本鱼原创的。')
        try { Show-Bubble $say } catch { }
        try { Speak-Text $say } catch { }
        Write-Err ('CULTURE-COUPLET ' + $upper + ' -> ' + $lower)
        return $true
    } catch { Write-Err ('CULTURE-ERR ' + $_.Exception.Message); return $false }
}
