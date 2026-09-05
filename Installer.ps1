# DLSS 5 Neural Rendering Installer (OptiScaler DLSS-NR)
# Profile-driven. Add a game by adding an entry to $Script:Games.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---- single instance ----
$Script:Created = $false
$Script:Mutex = New-Object System.Threading.Mutex($true, 'Local\DLSS5-Installer', [ref]$Script:Created)
if (-not $Script:Created) {
  [void][System.Windows.Forms.MessageBox]::Show(
    "The installer is already running." + [Environment]::NewLine +
    "설치기가 이미 실행 중입니다.",
    'DLSS 5 Installer', 'OK', 'Warning')
  exit
}

$Script:Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:Payload = Join-Path $Script:Root 'payload'
$Script:Opti    = Join-Path $Script:Payload 'optiscaler'
$Script:Game    = ''
$Script:Lang    = 'en'
$Script:Entries = New-Object System.Collections.ArrayList
$Script:StateKey = 'state_initial'
$Script:StateArg = @()
$Script:StateCol = [System.Drawing.Color]::Black

# ---------------------------------------------------------------- games
$Script:Games = @(
  @{
    Id='mhwilds'; NameKo="몬스터 헌터 와일즈"; NameEn='Monster Hunter Wilds'
    SteamDir='MonsterHunterWilds'; Exe='MonsterHunterWilds.exe'; SubDir=''
    Proxy='dxgi.dll'; Version=''; Extra=@()
    IniMode='stock'; OptiDir='optiscaler-mhwilds'; KeepRe=$true; OverlayKo='Delete'
    OptiUrl='https://github.com/Dagherbou/OptiScaler_DLSSNR/releases/download/v0.2.0-patch1/OptiScaler-DLSSNR-v0.2.0-onimusha-fix.zip'
    # d3d12.dll 로 놓으면 부팅 즉시 크래시 (게임 폴더의 숨겨진 _storage_\ 무결성
    # 미러가 감시하는 것으로 보임 - DD2 와 같은 계열의 안티템퍼). dxgi.dll 만 안전하다.
    # 이 게임 전용 OptiScaler 빌드(v0.2.0-patch1) 를 쓴다 - 다른 게임들이 쓰는
    # 공용 v0.1.1.5 보다 최신인데, 이 게임에서만 검증됐다. v0.1.2 는 이 게임에서
    # 부팅 크래시 (ExceptionCode 0xC0000005, exe 자체 코드 안).
    # REFramework(dinput8.dll)는 이 게임에 필수지만 넥서스에서 각자 받아야 한다.
    # 리쉐이드를 같이 쓰고 싶으면 ReShade 를 ReShade64.dll 로 이름 바꿔 게임
    # 폴더에 넣고 OptiScaler.ini 의 [Plugins] LoadReshade 를 true 로 켤 것 -
    # dxgi.dll 자리를 나눠 갖는 게 아니라 OptiScaler 가 내부에서 불러주는
    # 방식이라 이렇게 해야 동시에 된다.
    IniSet=@{
      Spoofing=@{ StreamlineSpoofing='false'; Dxgi='false' }
      Menu=@{ ShortcutKey='0x2E' }
    }
  },
  @{
    Id        = 'dd2'
    NameKo    = "드래곤즈 도그마 2"
    NameEn    = "Dragon's Dogma 2"
    SteamDir  = 'Dragons Dogma 2'
    Exe       = 'DD2.exe'
    SubDir    = ''
    Proxy     = 'dxgi.dll'
    Version   = '3.2.0.0'
    Extra     = @('dinput8.dll')
    IniMode   = 'project'
    KeepRe    = $false
    OverlayKo = 'Insert'
  },
  @{
    Id        = 'ff7r'
    NameKo    = "파이널 판타지 7 리버스"
    NameEn    = 'FINAL FANTASY VII REBIRTH'
    SteamDir  = 'FINAL FANTASY VII REBIRTH'
    Exe       = 'ff7rebirth_.exe'
    SubDir    = 'End\Binaries\Win64'
    Proxy     = 'winmm.dll'
    Version   = ''
    Extra     = @()
    IniMode   = 'stock'
    KeepRe    = $true
    OverlayKo = 'Insert'
  },
  @{
    Id='w3'; NameKo="위처 3"; NameEn='The Witcher 3'
    SteamDir='The Witcher 3'; Exe='witcher3.exe'; SubDir='bin\x64_dx12'
    Proxy='dbghelp.dll'; Version=''; Extra=@()
    IniMode='stock'; KeepRe=$true; OverlayKo='Insert'
  },
  @{
    Id='gta5'; NameKo="GTA V Enhanced"; NameEn='GTA V Enhanced'
    SteamDir='Grand Theft Auto V Enhanced'; Exe='GTA5_Enhanced.exe'; SubDir=''
    Proxy='version.dll'; Version=''; Extra=@()
    IniMode='stock'; KeepRe=$true; OverlayKo='Insert'; Warn='warn_gta5'
  },
  @{
    Id='cp2077'; NameKo="사이버펑크 2077"; NameEn='Cyberpunk 2077'
    SteamDir='Cyberpunk 2077'; Exe='Cyberpunk2077.exe'; SubDir='bin\x64'
    Proxy='d3d12.dll'; Version=''; Extra=@()
    IniMode='stock'; KeepRe=$true; OverlayKo='Insert'
    # dbghelp.dll 은 게임 본체 파일, version.dll 은 CET, winmm.dll 은 RED4ext,
    # dxgi.dll 은 ReShade 가 이미 쓴다. OptiScaler 가 쓸 수 있는 이름 중
    # 남는 자리는 d3d12.dll 하나뿐이다.
    # StreamlineSpoofing 을 끄지 않으면 GPU 가 두 장인 PC 에서 Streamline 이
    # DLSS-G(프레임 생성) 와 DLSS-D(레이 리컨스트럭션) 를 스스로 꺼버린다.
    IniSet=@{ Spoofing=@{ StreamlineSpoofing='false'; Dxgi='false' } }
  }
)

# 제외됨 - 레드 데드 리뎀션 2  (2026-09-03 검증)
#   DX12 모드에서 OptiScaler 단독은 정상 동작한다. 문제는 공존이다.
#   로딩 중 ERR_GFX_D3D_DEFERRED_MEM ("메모리 부족") 으로 죽는 조합:
#     - OptiScaler + ReShade  (dxgi.dll 프록시 / OptiScaler LoadReshade 둘 다 실패)
#     - OptiScaler + nvngx_dlss.dll 310.8.0  (게임 원본 2.2.10 의 4배 크기)
#   즉 NR 을 쓰려면 ReShade 를 버리고 DLSS 도 2021 년 구버전에 묶여야 하는데,
#   구버전 DLSS 로는 NR 이 제대로 붙지 않는다. 남는 조합이 없다.
#   효과 없었던 시도: FrameGen/Vulkan 스푸핑 끄기, PreferFirstDedicatedGpu,
#                    CreateD3D12DeviceForLuma
#   따라서 레데리2 는 DLSS5-Feeder + LumeniteFX + 전역 ReShade Vulkan 레이어를 쓴다.
#   자세한 내용: MHWilds-DLSS5-2026-08-29\RDR2-구성.txt
$Script:Prof = $Script:Games[0]

# ---------------------------------------------------------------- strings
$Script:S = @{
  ko = @{
    title         = 'DLSS 5 Neural Rendering 설치기'
    lang          = '언어'
    game          = '게임'
    lblPath       = '설치 폴더'
    btnAuto       = '자동 탐지'
    btnBrowse     = '찾아보기'
    btnPrepare    = '0. 파일 받기'
    btnCheck      = '1. 검사'
    btnInstall    = '2. 설치'
    btnRestore    = '복원'
    dlgTitle      = '{0} 을(를) 선택하세요'

    state_initial = '게임을 고르고 [자동 탐지] -> [0. 파일 받기] -> [1. 검사] -> [2. 설치]'
    state_found   = '경로를 찾았습니다. [1. 검사] 를 누르세요'
    state_autoFail= '자동 탐지 실패'
    state_needPath= '게임 경로를 먼저 지정하세요'
    state_checkOk = '검사 통과 - 설치할 수 있습니다'
    state_checkNg = '검사 실패 - 로그를 확인하세요'
    state_running = '게임을 먼저 종료하세요'
    state_instOk  = '설치 완료 - 게임에서 {0} 키를 누르세요'
    state_instNg  = '설치했지만 검증에 실패했습니다'
    state_restOk  = '복원 완료'
    state_noBak   = '백업이 없습니다'
    state_prep    = '파일을 받는 중입니다'
    state_prepOk  = '파일 준비 완료 - [1. 검사] 를 누르세요'
    state_prepNg  = '파일 받기 실패 - 로그를 확인하세요'
    state_needMdl = 'nvngx_dlssnr.dll 을 payload 폴더에 넣으세요'

    hdr1          = 'DLSS 5 Neural Rendering 설치기 - OptiScaler DLSS-NR 방식'
    hdr2          = '드라이버 616.56 이상 / RTX 카드'
    blank         = ''
    gameSel       = '게임 선택: {0}'
    gameFound     = '경로 발견: {0}'
    gameSet       = '경로 지정: {0}'
    autoFail      = '자동 탐지 실패 - [찾아보기] 로 {0} 을(를) 지정하세요'

    ckStart       = '--- 검사 시작 ---'
    ckEnd         = '--- 검사 끝 ---'
    noPath        = '[X] 설치 폴더가 지정되지 않았습니다.'
    folder        = '[O] 설치 폴더: {0}'
    verOk         = '[O] 게임 버전 {0}'
    verWarn       = '[!] 게임 버전 {0} - 검증된 버전은 {1} 입니다. 계속은 가능합니다.'
    verSkip       = '[-] 이 게임은 버전 검사를 하지 않습니다.'
    gpuOk         = '[O] GPU: {0}'
    noGpu         = '[X] RTX GPU 를 찾지 못했습니다.'
    drvOk         = '[O] 드라이버 {0}'
    drvNg         = '[X] 드라이버 {0} - 616.56 이상이 필요합니다.'
    drvErr        = '[!] 드라이버 버전을 해석하지 못했습니다.'
    payNg         = '[X] payload 누락: {0}'
    iniNg         = '[X] OptiScaler.ini 가 프로젝트 수정본이 아닙니다 (414 bytes 여야 합니다).'
    payOk         = '[O] payload 확인'
    proxyUse      = '[O] 주입 이름: {0}'
    conflict      = '[!] 충돌 파일 (설치 시 백업 후 제거): {0}'
    noConflict    = '[O] 충돌 파일 없음'
    keepRe        = '[-] ReShade 는 그대로 둡니다. 주입 이름이 다릅니다.'

    gameRun       = '[X] 게임이 실행 중입니다. 종료 후 다시 시도하세요.'
    bakHdr        = '--- 백업: {0}  (게임 폴더 밖) ---'
    bakItem       = '  백업 {0}'
    instHdr       = '--- 설치 ---'
    instItem      = '  {0}'
    vfyHdr        = '--- 검증 ---'
    vfyOk         = '  [O] {0}'
    vfyNg         = '  [X] {0} 해시 불일치'
    bakPath       = '백업 위치: {0}'
    rmHdr         = '--- 제거 ---'
    rmItem        = '  삭제 {0}'
    restHdr       = '--- 복원: {0} ---'
    restItem      = '  {0}'
    noBakFound    = '[X] 백업 폴더를 찾지 못했습니다.'

    prepHdr       = '--- 파일 받기 ---'
    prepDl        = '  받는 중: {0}'
    prepDone      = '  완료: {0}  ({1} bytes)'
    prepFail      = '  [X] 실패: {0}'
    prepExtract   = '  압축 해제: {0}'
    prepSkip      = '  이미 있음: {0}'
    mdlNg         = '[X] nvngx_dlssnr.dll 이 payload 폴더에 없습니다.'
    mdlHint       = '    NVIDIA 파일이라 함께 배포하지 않습니다. RenoDX 디스코드에서'
    mdlHint2      = '    "DLSS-NR model" 을 구해 payload 폴더에 넣으세요. 310.8.SF 권장.'
    err           = '[X] 오류: {0}'
    errAt         = '    위치: {0}'
    warnTitle     = '설치 전 확인'
    warn_gta5     = "GTA V Enhanced 는 BattlEye 를 끄지 않으면 아무것도 동작하지 않습니다.`n`n[ 끄는 방법 ]`n 1. 게임을 완전히 종료합니다`n 2. Rockstar Games Launcher 를 엽니다`n 3. 오른쪽 위 톱니바퀴 -> 설정`n 4. 왼쪽 목록에서 Grand Theft Auto V Enhanced 선택`n 5. BattlEye 안티치트 항목의 체크를 해제합니다`n 6. 런처를 껐다 켭니다`n`nBattlEye 가 켜져 있으면 OptiScaler 와 ReShade 가 로드 차단됩니다.`n밴이 아니라 차단입니다.`n`n※ GTA 온라인은 BattlEye 가 필수입니다. 끄면 접속할 수 없으므로`n   스토리 모드 전용이 됩니다. 온라인을 하시려면 다시 켜세요.`n`n계속하시겠습니까?"
    warnLog       = '[!] 설치 전 확인 사항을 표시했습니다.'
    warnCancel    = '[-] 사용자가 취소했습니다.'
  }
  en = @{
    title         = 'DLSS 5 Neural Rendering Installer'
    lang          = 'Language'
    game          = 'Game'
    lblPath       = 'Install folder'
    btnAuto       = 'Auto-detect'
    btnBrowse     = 'Browse'
    btnPrepare    = '0. Get files'
    btnCheck      = '1. Check'
    btnInstall    = '2. Install'
    btnRestore    = 'Restore'
    dlgTitle      = 'Select {0}'

    state_initial = 'Pick a game, then [Auto-detect] -> [0. Get files] -> [1. Check] -> [2. Install]'
    state_found   = 'Path found. Press [1. Check]'
    state_autoFail= 'Auto-detect failed'
    state_needPath= 'Set the install folder first'
    state_checkOk = 'Check passed - ready to install'
    state_checkNg = 'Check failed - see the log'
    state_running = 'Close the game first'
    state_instOk  = 'Installed - press {0} in game'
    state_instNg  = 'Installed, but verification failed'
    state_restOk  = 'Restore complete'
    state_noBak   = 'No backup found'
    state_prep    = 'Downloading files'
    state_prepOk  = 'Files ready - press [1. Check]'
    state_prepNg  = 'Download failed - see the log'
    state_needMdl = 'Place nvngx_dlssnr.dll in the payload folder'

    hdr1          = 'DLSS 5 Neural Rendering installer - OptiScaler DLSS-NR method'
    hdr2          = 'Driver 616.56 or newer / RTX card'
    blank         = ''
    gameSel       = 'Game selected: {0}'
    gameFound     = 'Path found: {0}'
    gameSet       = 'Path set: {0}'
    autoFail      = 'Auto-detect failed - use [Browse] to point at {0}'

    ckStart       = '--- Check started ---'
    ckEnd         = '--- Check finished ---'
    noPath        = '[X] No install folder has been set.'
    folder        = '[O] Install folder: {0}'
    verOk         = '[O] Game version {0}'
    verWarn       = '[!] Game version {0} - verified on {1}. You may continue.'
    verSkip       = '[-] No version check for this game.'
    gpuOk         = '[O] GPU: {0}'
    noGpu         = '[X] No RTX GPU found.'
    drvOk         = '[O] Driver {0}'
    drvNg         = '[X] Driver {0} - 616.56 or newer is required.'
    drvErr        = '[!] Could not parse the driver version.'
    payNg         = '[X] Missing from payload: {0}'
    iniNg         = '[X] OptiScaler.ini is not the project build (it must be 414 bytes).'
    payOk         = '[O] Payload verified'
    proxyUse      = '[O] Proxy name: {0}'
    conflict      = '[!] Conflicting files (backed up and removed on install): {0}'
    noConflict    = '[O] No conflicting files'
    keepRe        = '[-] ReShade is left in place; it uses a different proxy name.'

    gameRun       = '[X] The game is running. Close it and try again.'
    bakHdr        = '--- Backup: {0}  (outside the game folder) ---'
    bakItem       = '  backed up {0}'
    instHdr       = '--- Install ---'
    instItem      = '  {0}'
    vfyHdr        = '--- Verify ---'
    vfyOk         = '  [O] {0}'
    vfyNg         = '  [X] {0} hash mismatch'
    bakPath       = 'Backup location: {0}'
    rmHdr         = '--- Remove ---'
    rmItem        = '  removed {0}'
    restHdr       = '--- Restore: {0} ---'
    restItem      = '  {0}'
    noBakFound    = '[X] No backup folder found.'

    prepHdr       = '--- Getting files ---'
    prepDl        = '  downloading: {0}'
    prepDone      = '  done: {0}  ({1} bytes)'
    prepFail      = '  [X] failed: {0}'
    prepExtract   = '  extracting: {0}'
    prepSkip      = '  already present: {0}'
    mdlNg         = '[X] nvngx_dlssnr.dll is not in the payload folder.'
    mdlHint       = '    It is an NVIDIA file and is not redistributed here. Get the'
    mdlHint2      = '    "DLSS-NR model" from the RenoDX Discord; 310.8.SF is recommended.'
    err           = '[X] Error: {0}'
    errAt         = '    at: {0}'
    warnTitle     = 'Before you install'
    warn_gta5     = "GTA V Enhanced does nothing at all unless BattlEye is turned off.`n`n[ How to turn it off ]`n 1. Close the game completely`n 2. Open the Rockstar Games Launcher`n 3. Gear icon, top right -> Settings`n 4. Pick Grand Theft Auto V Enhanced in the left list`n 5. Untick the BattlEye Anti-Cheat option`n 6. Restart the launcher`n`nWith BattlEye on, both OptiScaler and ReShade are blocked from loading.`nA block, not a ban.`n`nNote: GTA Online requires BattlEye. With it off you cannot go online,`n   so this is single-player only. Turn it back on to play online.`n`nContinue?"
    warnLog       = '[!] Showed the pre-install warning.'
    warnCancel    = '[-] Cancelled by the user.'
  }
}

function T([string]$k, [object[]]$a) {
  $s = $Script:S[$Script:Lang][$k]
  if ($null -eq $s) { return $k }
  if ($a -and $a.Count) { return ($s -f $a) }
  return $s
}
function GName($p) { if ($Script:Lang -eq 'ko') { $p.NameKo } else { $p.NameEn } }

function Render-Log {
  if (-not $Script:txtLog) { return }
  $sb = New-Object System.Text.StringBuilder
  foreach ($e in $Script:Entries) {
    if ($e.k -eq 'blank') { [void]$sb.AppendLine('') }
    else { [void]$sb.AppendLine(('[{0}] {1}' -f $e.t, (T $e.k $e.a))) }
  }
  $Script:txtLog.Text = $sb.ToString()
  $Script:txtLog.SelectionStart = $Script:txtLog.Text.Length
  $Script:txtLog.ScrollToCaret()
}
function Log([string]$k, [object[]]$a) {
  [void]$Script:Entries.Add(@{ k = $k; a = $a; t = (Get-Date -Format 'HH:mm:ss') })
  Render-Log
}
function Say([string]$k, [object[]]$a, $c) {
  $Script:StateKey = $k; $Script:StateArg = $a; $Script:StateCol = $c
  if ($Script:lblState) { $Script:lblState.Text = (T $k $a); $Script:lblState.ForeColor = $c }
}
function Apply-Lang {
  $Script:form.Text       = T 'title'
  $Script:lblLang.Text    = T 'lang'
  $Script:lblGame.Text    = T 'game'
  $Script:lblPath.Text    = T 'lblPath'
  $Script:btnAuto.Text    = T 'btnAuto'
  $Script:btnBrowse.Text  = T 'btnBrowse'
  $Script:btnPrepare.Text = T 'btnPrepare'
  $Script:btnCheck.Text   = T 'btnCheck'
  $Script:btnInstall.Text = T 'btnInstall'
  $Script:btnRestore.Text = T 'btnRestore'
  $Script:lblState.Text   = T $Script:StateKey $Script:StateArg
  $Script:lblState.ForeColor = $Script:StateCol
  $i = $Script:cboGame.SelectedIndex
  $Script:cboGame.Items.Clear()
  foreach ($g in $Script:Games) { [void]$Script:cboGame.Items.Add((GName $g)) }
  $Script:cboGame.SelectedIndex = $(if ($i -ge 0) { $i } else { 0 })
  Render-Log
}

# ---------------------------------------------------------------- helpers
function Find-Game($p) {
  $roots = @()
  foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
    try { $v = (Get-ItemProperty $k -ErrorAction Stop).InstallPath; if ($v) { $roots += $v } } catch {}
  }
  $libs = @()
  foreach ($r in $roots) {
    $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
      foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
        $libs += ($m.Groups[1].Value -replace '\\\\', '\')
      }
    }
    $libs += $r
  }
  foreach ($l in ($libs | Select-Object -Unique)) {
    $g = Join-Path $l ('steamapps\common\' + $p.SteamDir)
    $d = if ($p.SubDir) { Join-Path $g $p.SubDir } else { $g }
    if (Test-Path (Join-Path $d $p.Exe)) { return $d }
  }
  return ''
}

function Apply-IniSet($path, $set) {
  if (-not $set) { return @() }
  $txt  = [IO.File]::ReadAllText($path)
  $done = @()
  foreach ($sec in $set.Keys) {
    foreach ($key in $set[$sec].Keys) {
      $val = $set[$sec][$key]
      $rx  = [regex]::new('(?ms)(^\[' + [regex]::Escape($sec) + '\]\r?\n)(.*?)(?=^\[|\z)')
      $m   = $rx.Match($txt)
      if (-not $m.Success) { continue }
      $body = $m.Groups[2].Value
      $krx  = [regex]::new('(?m)^' + [regex]::Escape($key) + '=.*$')
      if (-not $krx.IsMatch($body)) { continue }
      $new = $krx.Replace($body, ($key + '=' + $val), 1)
      $txt = $txt.Substring(0, $m.Groups[2].Index) + $new +
             $txt.Substring($m.Groups[2].Index + $m.Groups[2].Length)
      $done += ('[' + $sec + '] ' + $key + '=' + $val)
    }
  }
  [IO.File]::WriteAllText($path, $txt)
  return $done
}

function Opti-Dir($p) {
  if ($p.OptiDir) { return (Join-Path $Script:Payload $p.OptiDir) }
  return $Script:Opti
}

function Payload-Files($p) {
  $od = Opti-Dir $p
  $f = @{
    $p.Proxy               = (Join-Path $od 'OptiScaler.dll')
    'nvngx.dll_dlssnr.dll' = (Join-Path $od 'nvngx.dll_dlssnr.dll')
    'nvngx_dlssnr.dll'     = (Join-Path $Script:Payload 'nvngx_dlssnr.dll')
  }
  if ($p.IniMode -eq 'project') { $f['OptiScaler.ini'] = (Join-Path $Script:Payload ($p.Id + '\OptiScaler.ini')) }
  else { $f['OptiScaler.ini'] = (Join-Path $od 'OptiScaler.ini') }
  foreach ($e in $p.Extra) { $f[$e] = (Join-Path $Script:Payload ($p.Id + '\' + $e)) }
  return $f
}

# ---------------------------------------------------------------- actions
function Get-Payload {
  $p = $Script:Prof
  Say 'state_prep' @() ([System.Drawing.Color]::Black)
  Log 'prepHdr'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $od = Opti-Dir $p
  $dirs = @($Script:Payload, $od)
  if ($p.Id -eq 'dd2') { $dirs += (Join-Path $Script:Payload 'dd2') }
  foreach ($d in $dirs) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
  }
  $ok = $true

  if (-not (Test-Path (Join-Path $od 'OptiScaler.dll'))) {
    $url = $(if ($p.OptiUrl) { $p.OptiUrl } else { 'https://github.com/Dagherbou/OptiScaler_DLSSNR/releases/download/v0.1.1.5-dlssnr/OptiScaler-DLSSNR-v0.1.1.5-dlssnr.zip' })
    $name = $url.Substring($url.LastIndexOf('/') + 1)
    $zip = Join-Path $env:TEMP $name
    try {
      Log 'prepDl' @($name)
      Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
      Log 'prepDone' @($name, (Get-Item $zip).Length)
      Log 'prepExtract' @($name)
      Expand-Archive -Path $zip -DestinationPath $od -Force
      Remove-Item $zip -Force -ErrorAction SilentlyContinue
    } catch { Log 'prepFail' @('OptiScaler'); $ok = $false }
  }
  else { Log 'prepSkip' @('OptiScaler') }

  if ($p.Id -eq 'dd2') {
    $base = 'https://raw.githubusercontent.com/dmitrysobolev/DD2-DLSS5/main/GameFiles/'
    foreach ($n in 'dinput8.dll', 'OptiScaler.ini') {
      $dst = Join-Path $Script:Payload ('dd2\' + $n)
      if (Test-Path $dst) { Log 'prepSkip' @(('dd2\' + $n)); continue }
      try {
        Log 'prepDl' @(('dd2\' + $n))
        Invoke-WebRequest -Uri ($base + $n) -OutFile $dst -UseBasicParsing
        Log 'prepDone' @(('dd2\' + $n), (Get-Item $dst).Length)
      } catch { Log 'prepFail' @(('dd2\' + $n)); $ok = $false }
    }
  }

  if (-not (Test-Path (Join-Path $Script:Payload 'nvngx_dlssnr.dll'))) {
    Log 'mdlNg'; Log 'mdlHint'; Log 'mdlHint2'
    Say 'state_needMdl' @() ([System.Drawing.Color]::Firebrick); return
  }
  if ($ok) { Say 'state_prepOk' @() ([System.Drawing.Color]::SeaGreen) }
  else { Say 'state_prepNg' @() ([System.Drawing.Color]::Firebrick) }
}

function Run-Check {
  $p = $Script:Prof
  $ok = $true
  Log 'ckStart'

  if (-not $Script:Game -or -not (Test-Path (Join-Path $Script:Game $p.Exe))) {
    Log 'noPath'; Say 'state_needPath' @() ([System.Drawing.Color]::Firebrick); return $false
  }
  Log 'folder' @($Script:Game)

  if ($p.Version) {
    $v = (Get-Item (Join-Path $Script:Game $p.Exe)).VersionInfo.FileVersion
    if ($v -eq $p.Version) { Log 'verOk' @($v) } else { Log 'verWarn' @($v, $p.Version) }
  }
  else { Log 'verSkip' }

  $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'RTX' } | Select-Object -First 1
  if ($gpu) {
    Log 'gpuOk' @($gpu.Name)
    $d = $gpu.DriverVersion -replace '\.', ''
    try {
      $n = [double]('{0}.{1}' -f $d.Substring($d.Length - 5, 3), $d.Substring($d.Length - 2, 2))
      if ($n -ge 616.56) { Log 'drvOk' @($n) } else { Log 'drvNg' @($n); $ok = $false }
    } catch { Log 'drvErr' }
  }
  else { Log 'noGpu'; $ok = $false }

  $files = Payload-Files $p
  foreach ($k in $files.Keys) {
    if (-not (Test-Path $files[$k])) { Log 'payNg' @($k); $ok = $false }
  }
  $od = Opti-Dir $p
  if (-not (Test-Path (Join-Path $od 'OptiScaler'))) { Log 'payNg' @('OptiScaler\'); $ok = $false }
  foreach ($d in $p.ExtraDirs) {
    if (-not (Test-Path (Join-Path $Script:Payload ($p.Id + '\' + $d)))) { Log 'payNg' @(($d + '\')); $ok = $false }
  }
  if ($p.IniMode -eq 'project') {
    $i = $files['OptiScaler.ini']
    if ((Test-Path $i) -and ((Get-Item $i).Length -gt 2000)) { Log 'iniNg'; $ok = $false }
  }
  if ($ok) { Log 'payOk' }
  Log 'proxyUse' @($p.Proxy)

  $conf = @()
  if (-not $p.KeepRe) {
    $gx = Join-Path $Script:Game 'dxgi.dll'
    if ((Test-Path $gx) -and ((Get-Item $gx).VersionInfo.ProductName -match 'ReShade')) { $conf += 'ReShade dxgi.dll' }
    foreach ($n in 'ReShade.ini', 'ReShade.log', 'ReShadePreset.ini', 'reshade-shaders') {
      if (Test-Path (Join-Path $Script:Game $n)) { $conf += $n }
    }
  }
  else { Log 'keepRe' }
  foreach ($a in (Get-ChildItem $Script:Game -Filter '*.addon64' -ErrorAction SilentlyContinue)) { $conf += $a.Name }
  if (Test-Path (Join-Path $Script:Game 'OptiScaler.asi')) { $conf += 'OptiScaler.asi' }
  if ($conf.Count) { Log 'conflict' @(($conf -join ', ')) } else { Log 'noConflict' }

  if ($ok) { Say 'state_checkOk' @() ([System.Drawing.Color]::SeaGreen) }
  else { Say 'state_checkNg' @() ([System.Drawing.Color]::Firebrick) }
  Log 'ckEnd'
  return $ok
}

function Game-Running($p) {
  $n = [IO.Path]::GetFileNameWithoutExtension($p.Exe)
  return [bool](Get-Process $n -ErrorAction SilentlyContinue)
}

function Run-Install {
  $p = $Script:Prof
  if (Game-Running $p) { Log 'gameRun'; Say 'state_running' @() ([System.Drawing.Color]::Firebrick); return }
  if ($p.Warn) {
    Log 'warnLog'
    $r = [System.Windows.Forms.MessageBox]::Show((T $p.Warn), (T 'warnTitle'), 'OKCancel', 'Warning')
    if ($r -ne 'OK') { Log 'warnCancel'; return }
  }
  if (-not (Run-Check)) { return }

  $bk = Join-Path ([Environment]::GetFolderPath('Desktop')) ('DLSS5-backup_' + $p.Id + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
  New-Item -ItemType Directory -Path $bk -Force | Out-Null
  Log 'bakHdr' @($bk)

  $move = @($p.Proxy, 'OptiScaler.ini', 'nvngx_dlssnr.dll', 'nvngx.dll_dlssnr.dll', 'OptiScaler.asi') + $p.Extra
  if (-not $p.KeepRe) { $move += @('dxgi.dll', 'd3d12.dll', 'ReShade.ini', 'ReShade.log', 'ReShade.log.prev', 'ReShadePreset.ini') }
  foreach ($n in ($move | Select-Object -Unique)) {
    $s = Join-Path $Script:Game $n
    if (Test-Path $s) { Move-Item $s (Join-Path $bk $n) -Force -ErrorAction SilentlyContinue; Log 'bakItem' @($n) }
  }
  $dirs = @('OptiScaler')
  if (-not $p.KeepRe) { $dirs += 'reshade-shaders' }
  $dirs += $p.ExtraDirs
  foreach ($d in ($dirs | Select-Object -Unique)) {
    $s = Join-Path $Script:Game $d
    if (Test-Path $s) { Move-Item $s (Join-Path $bk $d) -Force -ErrorAction SilentlyContinue; Log 'bakItem' @(($d + '\')) }
  }
  foreach ($a in (Get-ChildItem $Script:Game -Filter '*.addon64' -ErrorAction SilentlyContinue)) {
    Move-Item $a.FullName (Join-Path $bk $a.Name) -Force -ErrorAction SilentlyContinue; Log 'bakItem' @($a.Name)
  }

  Log 'instHdr'
  $files = Payload-Files $p
  $od = Opti-Dir $p
  foreach ($k in ($files.Keys | Where-Object { $_ -ne 'OptiScaler.ini' })) {
    Copy-Item $files[$k] (Join-Path $Script:Game $k) -Force; Log 'instItem' @($k)
  }
  Copy-Item (Join-Path $od 'OptiScaler') (Join-Path $Script:Game 'OptiScaler') -Recurse -Force
  Log 'instItem' @('OptiScaler\')
  Copy-Item $files['OptiScaler.ini'] (Join-Path $Script:Game 'OptiScaler.ini') -Force
  Log 'instItem' @('OptiScaler.ini')
  foreach ($d in $p.ExtraDirs) {
    $src = Join-Path $Script:Payload ($p.Id + '\' + $d)
    Copy-Item $src (Join-Path $Script:Game $d) -Recurse -Force
    Log 'instItem' @(($d + '\'))
  }

  Log 'vfyHdr'
  $bad = 0
  foreach ($k in $files.Keys) {
    $h1 = (Get-FileHash $files[$k] -Algorithm SHA256).Hash
    $h2 = (Get-FileHash (Join-Path $Script:Game $k) -Algorithm SHA256).Hash
    if ($h1 -eq $h2) { Log 'vfyOk' @($k) } else { Log 'vfyNg' @($k); $bad++ }
  }
  foreach ($t in (Apply-IniSet (Join-Path $Script:Game 'OptiScaler.ini') $p.IniSet)) {
    Log 'instItem' @('OptiScaler.ini  ' + $t)
  }

  if ($bad) { Say 'state_instNg' @() ([System.Drawing.Color]::Firebrick) }
  else { Say 'state_instOk' @($p.OverlayKo) ([System.Drawing.Color]::SeaGreen) }
  Log 'bakPath' @($bk)
}

function Run-Restore {
  $p = $Script:Prof
  if (Game-Running $p) { Log 'gameRun'; Say 'state_running' @() ([System.Drawing.Color]::Firebrick); return }
  if (-not $Script:Game) { Log 'noPath'; return }

  $desk = [Environment]::GetFolderPath('Desktop')
  $bk = Get-ChildItem $desk -Directory -Filter ('DLSS5-backup_' + $p.Id + '_*') -ErrorAction SilentlyContinue |
        Sort-Object Name | Select-Object -Last 1
  if (-not $bk) { Log 'noBakFound'; Say 'state_noBak' @() ([System.Drawing.Color]::Firebrick); return }

  Log 'rmHdr'
  $rm = @($p.Proxy, 'OptiScaler.ini', 'OptiScaler.log', 'nvngx_dlssnr.dll', 'nvngx.dll_dlssnr.dll') + $p.Extra
  foreach ($n in ($rm | Select-Object -Unique)) {
    $t = Join-Path $Script:Game $n
    if (Test-Path $t) { Remove-Item $t -Force -ErrorAction SilentlyContinue; Log 'rmItem' @($n) }
  }
  $od = Join-Path $Script:Game 'OptiScaler'
  if (Test-Path $od) { Remove-Item $od -Recurse -Force -ErrorAction SilentlyContinue; Log 'rmItem' @('OptiScaler\') }
  foreach ($d in $p.ExtraDirs) {
    $t = Join-Path $Script:Game $d
    if (Test-Path $t) { Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue; Log 'rmItem' @(($d + '\')) }
  }

  Log 'restHdr' @($bk.Name)
  foreach ($i in (Get-ChildItem $bk.FullName)) {
    Copy-Item $i.FullName (Join-Path $Script:Game $i.Name) -Recurse -Force -ErrorAction SilentlyContinue
    Log 'restItem' @($i.Name)
  }
  Say 'state_restOk' @() ([System.Drawing.Color]::SeaGreen)
}

# ---------------------------------------------------------------- UI
$form = New-Object System.Windows.Forms.Form
$form.Size = New-Object System.Drawing.Size(790, 650)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Malgun Gothic', 9)
$Script:form = $form

$lblGame = New-Object System.Windows.Forms.Label
$lblGame.Location = New-Object System.Drawing.Point(14, 18); $lblGame.AutoSize = $true
$form.Controls.Add($lblGame); $Script:lblGame = $lblGame

$cboGame = New-Object System.Windows.Forms.ComboBox
$cboGame.Location = New-Object System.Drawing.Point(70, 14)
$cboGame.Size = New-Object System.Drawing.Size(330, 24)
$cboGame.DropDownStyle = 'DropDownList'
$form.Controls.Add($cboGame); $Script:cboGame = $cboGame

$lblLang = New-Object System.Windows.Forms.Label
$lblLang.Location = New-Object System.Drawing.Point(566, 16)
$lblLang.Size = New-Object System.Drawing.Size(70, 20); $lblLang.TextAlign = 'MiddleRight'
$form.Controls.Add($lblLang); $Script:lblLang = $lblLang

$cboLang = New-Object System.Windows.Forms.ComboBox
$cboLang.Location = New-Object System.Drawing.Point(640, 14)
$cboLang.Size = New-Object System.Drawing.Size(126, 24)
$cboLang.DropDownStyle = 'DropDownList'
[void]$cboLang.Items.Add('English'); [void]$cboLang.Items.Add('한국어')
$cboLang.SelectedIndex = 0
$form.Controls.Add($cboLang)

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Location = New-Object System.Drawing.Point(14, 50); $lblPath.AutoSize = $true
$form.Controls.Add($lblPath); $Script:lblPath = $lblPath

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object System.Drawing.Point(14, 72)
$txtPath.Size = New-Object System.Drawing.Size(578, 24); $txtPath.ReadOnly = $true
$form.Controls.Add($txtPath)

$btnAuto = New-Object System.Windows.Forms.Button
$btnAuto.Location = New-Object System.Drawing.Point(602, 70)
$btnAuto.Size = New-Object System.Drawing.Size(80, 27)
$form.Controls.Add($btnAuto); $Script:btnAuto = $btnAuto

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Location = New-Object System.Drawing.Point(688, 70)
$btnBrowse.Size = New-Object System.Drawing.Size(78, 27)
$form.Controls.Add($btnBrowse); $Script:btnBrowse = $btnBrowse

$btnPrepare = New-Object System.Windows.Forms.Button
$btnPrepare.Location = New-Object System.Drawing.Point(14, 110)
$btnPrepare.Size = New-Object System.Drawing.Size(150, 34)
$form.Controls.Add($btnPrepare); $Script:btnPrepare = $btnPrepare

$btnCheck = New-Object System.Windows.Forms.Button
$btnCheck.Location = New-Object System.Drawing.Point(174, 110)
$btnCheck.Size = New-Object System.Drawing.Size(150, 34)
$form.Controls.Add($btnCheck); $Script:btnCheck = $btnCheck

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Location = New-Object System.Drawing.Point(334, 110)
$btnInstall.Size = New-Object System.Drawing.Size(150, 34)
$form.Controls.Add($btnInstall); $Script:btnInstall = $btnInstall

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Location = New-Object System.Drawing.Point(494, 110)
$btnRestore.Size = New-Object System.Drawing.Size(110, 34)
$form.Controls.Add($btnRestore); $Script:btnRestore = $btnRestore

$lblState = New-Object System.Windows.Forms.Label
$lblState.Location = New-Object System.Drawing.Point(14, 154)
$lblState.Size = New-Object System.Drawing.Size(752, 22)
$form.Controls.Add($lblState); $Script:lblState = $lblState

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(14, 184)
$txtLog.Size = New-Object System.Drawing.Size(752, 406)
$txtLog.Multiline = $true; $txtLog.ScrollBars = 'Vertical'; $txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($txtLog); $Script:txtLog = $txtLog

$cboLang.Add_SelectedIndexChanged({
  $Script:Lang = $(if ($cboLang.SelectedIndex -eq 0) { 'en' } else { 'ko' })
  Apply-Lang
})

$cboGame.Add_SelectedIndexChanged({
  if ($cboGame.SelectedIndex -lt 0) { return }
  $Script:Prof = $Script:Games[$cboGame.SelectedIndex]
  Log 'gameSel' @((GName $Script:Prof))
  $g = Find-Game $Script:Prof
  $Script:Game = $g
  $txtPath.Text = $g
  if ($g) { Log 'gameFound' @($g); Say 'state_found' @() ([System.Drawing.Color]::Black) }
  else { Say 'state_initial' @() ([System.Drawing.Color]::Black) }
})

$btnAuto.Add_Click({
  $g = Find-Game $Script:Prof
  if ($g) { $Script:Game = $g; $txtPath.Text = $g; Log 'gameFound' @($g); Say 'state_found' @() ([System.Drawing.Color]::Black) }
  else { Log 'autoFail' @($Script:Prof.Exe); Say 'state_autoFail' @() ([System.Drawing.Color]::Firebrick) }
})

$btnBrowse.Add_Click({
  $d = New-Object System.Windows.Forms.OpenFileDialog
  $d.Filter = ('{0}|{0}' -f $Script:Prof.Exe)
  $d.Title = (T 'dlgTitle' @($Script:Prof.Exe))
  if ($d.ShowDialog() -eq 'OK') {
    $Script:Game = Split-Path -Parent $d.FileName
    $txtPath.Text = $Script:Game
    Log 'gameSet' @($Script:Game)
  }
})

function Safe([scriptblock]$b) {
  try { & $b }
  catch {
    Log 'err' @($_.Exception.Message)
    if ($_.InvocationInfo) { Log 'errAt' @($_.InvocationInfo.PositionMessage.Trim()) }
    Say 'state_checkNg' @() ([System.Drawing.Color]::Firebrick)
  }
}

$btnPrepare.Add_Click({ Safe { Get-Payload } })
$btnCheck.Add_Click({ Safe { [void](Run-Check) } })
$btnInstall.Add_Click({ Safe { Run-Install } })
$btnRestore.Add_Click({ Safe { Run-Restore } })

Log 'hdr1'
Log 'hdr2'
Log 'blank'
Apply-Lang
$cboGame.SelectedIndex = 0
[void]$form.ShowDialog()

if ($Script:Created -and $Script:Mutex) {
  try { $Script:Mutex.ReleaseMutex() } catch {}
  $Script:Mutex.Dispose()
}
