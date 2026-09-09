# Kiroshi Optics - DLSS 5 Neural Rendering Installer (OptiScaler DLSS-NR)
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
    Proxy='dxgi.dll'; Version=''
    Extra=@('dinput8.dll','ReShade64.dll','ReShadePreset.ini','nvngx_dlss.dll','nvngx_dlssd.dll','nvngx_dlssg.dll')
    ExtraDirs=@('reshade-shaders')
    IniMode='stock'; OptiDir='optiscaler-mhwilds'; KeepRe=$true; OverlayKo='Delete'
    # d3d12.dll 로 놓으면 부팅 즉시 크래시 (게임 폴더의 숨겨진 _storage_\ 무결성
    # 미러가 감시하는 것으로 보임 - DD2 와 같은 계열의 안티템퍼). dxgi.dll 만 안전하다.
    # 이 게임 전용 OptiScaler 빌드(v0.2.0-patch1) 를 쓴다 - 다른 게임들이 쓰는
    # 공용 payload\optiscaler\ 보다 최신인데, 이 게임에서만 검증됐다.
    #   v0.1.2 는 이 게임에서 부팅 크래시 (ExceptionCode 0xC0000005, exe 자체 코드 안).
    # dinput8.dll = REFramework (게임 무결성 우회, 필수).
    # ReShade64.dll + ReShadePreset.ini + reshade-shaders\ 는 OptiScaler 가
    # [Plugins] LoadReshade 로 내부에서 직접 불러준다 - dxgi.dll 자리를 나눠 갖는
    # 방식이 아니다. ReShade 를 dxgi.dll 로 따로 깔면 OptiScaler 가 아예 로드되지
    # 않는다.
    # nvngx_dlss.dll / nvngx_dlssd.dll / nvngx_dlssg.dll 은 NVIDIA 파일이라
    # nvngx_dlssnr.dll 과 같은 취급 - 재배포 대상 아님, 이 PC 에 이미 있던
    # 검증된 사본을 payload\mhwilds\ 에 개인 보관해둔 것뿐이다.
    IniSet=@{
      Spoofing=@{ StreamlineSpoofing='false'; Dxgi='false' }
      Menu=@{ ShortcutKey='0x2E' }
      Plugins=@{ LoadReshade='true' }
    }
  },
  @{
    Id='mhw'; NameKo="몬스터 헌터 월드"; NameEn='Monster Hunter World'
    SteamDir='Monster Hunter World'; Exe='MonsterHunterWorld.exe'; SubDir=''
    Method='reshade'; Proxy='d3d11.dll'; Version=''
    Extra=@('renodx-dlss.addon64','ReShade.ini','nvngx_dlss.dll',
            'sl.common.dll','sl.dlss.dll','sl.dlss_g.dll','sl.dlss_nr.dll',
            'sl.interposer.dll','sl.nis.dll','sl.pcl.dll','sl.reflex.dll')
    KeepRe=$false; OverlayKo='Home'; Warn='warn_mhw'
    GfxIni=@{ File='graphics_option.ini'; Set=@{ GraphicsOption=@{ DirectX12Enable='Off' } } }
    # 이 게임은 OptiScaler 방식이 아니다. MonsterHunterWorld.exe 가 패킹/보호되어
    # 있어(정적 PE import 1개) OptiScaler 는 dxgi.dll/d3d12.dll 로는 아예 로드조차
    # 안 되고, d3d11.dll 로 놓아도 로드는 되지만 디바이스 생성 훅이 전혀 안 걸린다
    # (Insert 키 무반응). 이 게임에서 실제로 후킹에 성공하는 건 ReShade 뿐이다.
    # 그래서 d3d11.dll = ReShade 본체 + renodx-dlss.addon64 (ShortFuse, renodx-dlss5
    # 아님 - 별개 애드온) 조합을 쓴다.
    # graphics_option.ini 의 DirectX12Enable 을 Off 로 강제한다 - On 이면 D3D11on12
    # 경로를 타면서 시스템 dxgi.dll 안에서 STATUS_BREAKPOINT 로 크래시한다(애드온을
    # 꺼도 동일 위치에서 크래시 - ReShade 자체의 D3D11on12 처리 문제였음).
    # ★ NR 은 화면 전환(로딩)과 겹치면 크래시하거나 검은 화면에 멈춘다 - 스왑체인이
    #   다시 만들어지는 타이밍과 충돌하는 것으로 보임. 그래서 NR 은 "부팅 시" 뿐
    #   아니라 "타이틀 <-> 실제 게임 화면" 을 오가는 모든 전환에서 꺼져 있어야 한다:
    #     - 부팅: ReShade.ini 의 DirectNeuralRenderingHookPoint 가 5(On Present) 로
    #       저장된 채 부팅하면 부팅 중 스왑체인 리사이즈 타이밍에 걸려 검은 화면에
    #       영원히 멈춘다(크래시 덤프도 안 남음). 그래서 이 템플릿 ReShade.ini 는
    #       HookPoint=0(Off) 으로 고정 배포한다.
    #     - 타이틀 -> 게임 진입: 타이틀 화면을 완전히 지나 실제 게임 화면에 들어온
    #       뒤에만 오버레이(Home 키)에서 RenoDX DLSS 탭 -> Options Mode=DLSS-NR ->
    #       Hook Point=On Present 로 라이브로 켤 것.
    #     - 게임 -> 타이틀 복귀: 타이틀로 나가기 전에 먼저 오버레이에서 NR 을 도로
    #       꺼야 한다. 켠 채로 나가면 그 전환에서 크래시한다.
    #   ReShade 는 Save Settings 버튼을 안 눌러도 종료 시 현재 상태를 ini 에 다시
    #   써버리는 것으로 보인다 - 그러니 게임을 끄기 전에도 NR 을 꺼두는 습관이
    #   필요하다(다음 부팅이 이 상태를 그대로 물려받음). Install 버튼을 누르면 이
    #   내용을 담은 경고 팝업(Warn='warn_mhw')이 먼저 뜬다.
    #   Manually Load DLSS Libraries(ForceNgxCore) 는 항상 Off 유지 - On 이면 크래시.
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
    # dbghelp.dll 은 게임 본체 파일, version.dll 은 CET, winmm.dll 은 RED4ext -
    # 이 셋은 다른 DLSS 5 도구 잔재 검사(OtherProxyOk)에서도 정상으로 취급한다.
    # dxgi.dll 은 ReShade 가 이미 쓴다. OptiScaler 가 쓸 수 있는 이름 중
    # 남는 자리는 d3d12.dll 하나뿐이다.
    OtherProxyOk=@('dbghelp.dll', 'version.dll', 'winmm.dll')
    # StreamlineSpoofing 을 끄지 않으면 GPU 가 두 장인 PC 에서 Streamline 이
    # DLSS-G(프레임 생성) 와 DLSS-D(레이 리컨스트럭션) 를 스스로 꺼버린다 - 이건
    # 개발 PC(듀얼 GPU) 사정이라 GPU 2장 감지될 때만 적용한다(F, Run-Install 참고).
    DualGpuIniSet=@{ Spoofing=@{ StreamlineSpoofing='false'; Dxgi='false' } }
  },
  @{
    Id='wwm'; NameKo="연운십육성 (Where Winds Meet)"; NameEn='Where Winds Meet'
    SteamDir='Where Winds Meet'; Exe='wwm.exe'; SubDir='Engine\Binaries\Win64r'
    Proxy='dxgi.dll'; Version=''
    Extra=@(); ExtraDirs=@()
    IniMode='stock'; OptiDir='optiscaler-mhwilds'; KeepRe=$true; OverlayKo='Insert'
    # 리쉐이드는 필수가 아니라 선택 항목 - 체크박스로 켜고 끌 수 있다 (OptionalReshade).
    OptionalReshade=@{
      Extra=@('ReShade64.dll','ReShade.ini','ReShadePreset.ini')
      ExtraDirs=@('reshade-shaders','DreamPunk')
      IniSet=@{ Plugins=@{ LoadReshade='true' } }
    }
    # 폴더 이름이 Win64 가 아니라 Win64r 인 게 오타가 아니라 실제 폴더명이다.
    # 프록시 자리가 전부 비어있어서(dxgi/d3d12/version/winmm/dbghelp 다 없음)
    # dxgi.dll 로 고정. 네이티브 Streamline/DLSS 를 이미 갖고 있는 게임이라
    # (Engine\Binaries\Win64r\Streamline\ 안에 sl.*.dll, nvngx_dlss.dll 등) NR 도
    # 기존 DLSS 호출을 후킹하는 방식으로 붙는다 - MH Wilds 처럼 FSR 리다이렉션이
    # 필요한 게임이 아니다.
    # 리쉐이드(ReShade64.dll + ReShade.ini + reshade-shaders\ + DreamPunk\ 프리셋)는
    # 전부 사이버펑크 2077 에서 그대로 가져온 것 - DreamPunk_2.1_HDR.ini 가 활성
    # 프리셋이다. 뎁스 관련 설정(RESHADE_DEPTH_INPUT_IS_REVERSED 등)은 사이버펑크
    # 렌더링에 맞춰진 값이라 이 게임에서 뎁스 기반 필터가 이상해 보이면 이것부터
    # 의심할 것 - 아직 실제 화면에서 검증 전.
    # CrashHunter (넷이즈 자체 안티치트/SDK) 가 있는 게임이니 온라인 매칭 등은
    # 조심할 것 - 싱글/오프라인 콘텐츠 위주로만 검증됨.
    # 이것도 사이버펑크와 마찬가지로 듀얼 GPU 사정 - GPU 2장일 때만 적용(F).
    DualGpuIniSet=@{ Spoofing=@{ StreamlineSpoofing='false'; Dxgi='false' } }
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
    title         = 'Kiroshi Optics - DLSS 5 Neural Rendering 설치기'
    lang          = '언어'
    game          = '게임'
    lblPath       = '설치 폴더'
    btnAuto       = '자동 탐지'
    btnBrowse     = '찾아보기'
    btnPrepare    = '0. 파일 받기'
    btnCheck      = '1. 검사'
    btnInstall    = '2. 설치'
    btnRestore    = '복원'
    chkReshade    = '리쉐이드(필터/프리셋) 같이 설치'
    askReshadeTitle = '리쉐이드 설치'
    askReshadeMsg   = '리쉐이드(필터/프리셋)도 같이 설치하시겠어요?'
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
    state_bakFail = '백업 실패 - 설치가 중단되었습니다'
    state_restOk  = '복원 완료'
    state_restNg  = '복원 중 일부 실패 - 로그를 확인하세요'
    state_noBak   = '백업이 없습니다'
    state_prep    = '파일을 받는 중입니다'
    state_prepOk  = '파일 준비 완료 - [1. 검사] 를 누르세요'
    state_prepNg  = '파일 받기 실패 - 로그를 확인하세요'
    state_needMdl = 'nvngx_dlssnr.dll 을 payload 폴더에 넣으세요'

    hdr1          = 'Kiroshi Optics - OptiScaler DLSS-NR 방식'
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
    writeOk       = '[O] 쓰기 테스트 통과'
    writeNg       = '[X] 게임 폴더에 쓸 수 없습니다: {0}'
    writeNgAdmin  = '    Program Files 아래입니다. 관리자 권한으로 이 설치기를 다시 실행해보세요.'
    writeBakNg    = '[X] 백업 위치에 쓸 수 없습니다: {0}'
    cfaWarn       = "[!] Windows 보안의 [제어된 폴더 액세스]가 켜져 있습니다. 보호된 폴더에 대한 쓰기가 막힐 수 있습니다.`n    걸리면: Windows 보안 -> 바이러스 및 위협 방지 -> 랜섬웨어 방지 -> 제어된 폴더 액세스를 통해 앱 허용, 에서 이 설치기를 등록하세요.`n    (설치기가 보안 설정을 대신 바꾸지는 않습니다)"
    sigOk         = '[O] nvngx_dlssnr.dll 서명 유효: {0}  (SHA-256 {1})'
    sigWarn       = '[!] nvngx_dlssnr.dll 서명 없음/무효 ({0}) - 커뮤니티 수정본이면 정상입니다.  (SHA-256 {1})'
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
    iniMissing    = '  [!] OptiScaler.ini 가 없어 설정을 적용하지 못했습니다: {0}'
    payOk         = '[O] payload 확인'
    proxyUse      = '[O] 주입 이름: {0}'
    conflict      = '[!] 충돌 파일 (설치 시 백업 후 제거): {0}'
    noConflict    = '[O] 충돌 파일 없음'
    keepRe        = '[-] ReShade 는 그대로 둡니다. 주입 이름이 다릅니다.'
    otherToolHdr  = '[X] 다른 DLSS 5 도구(DLSS 5 Swapper 등)로 설치한 흔적이 발견됐습니다:'
    otherToolItem = '    - {0}'
    otherToolHelp = "    먼저 해당 도구에서 [복원]으로 되돌린 뒤 다시 시도하세요.`n    이미 지운 도구라면: 스팀 -> 게임 우클릭 -> 속성 -> 설치된 파일 -> 게임 파일 무결성 검사로 원본을 복구하세요.`n    단, 게임 폴더에 남은 _DLSS5_Backup 폴더는 무결성 검사로 안 지워지니 수동으로 삭제하세요."

    gameRun       = '[X] 게임이 실행 중입니다. 종료 후 다시 시도하세요.'
    bakHdr        = '--- 백업: {0}  (게임 폴더 밖) ---'
    bakItem       = '  백업 {0}'
    bakFail       = '  [X] 백업 실패: {0}  ({1})'
    bakAbort      = '[X] 백업이 실패해 설치를 중단합니다. 게임 폴더나 바탕화면에 쓰기 권한이 있는지 확인하세요.'
    instHdr       = '--- 설치 ---'
    instItem      = '  {0}'
    instFail      = '  [X] {0} 복사 실패: {1}'
    dualGpuApplied = '  [i] GPU 2장 감지 - StreamlineSpoofing/Dxgi 스푸핑 적용'
    vfyHdr        = '--- 검증 ---'
    vfyOk         = '  [O] {0}'
    vfyNg         = '  [X] {0} 해시 불일치'
    vfyMissing    = '  [X] {0} 파일이 없습니다'
    vfyQuarantine = '  [!] {0} - 복사는 성공했는데 확인 시 파일이 없습니다. 백신이 격리했을 가능성이 높습니다. Windows 보안 -> 보호 기록에서 확인하세요.'
    bakPath       = '백업 위치: {0}'
    rmHdr         = '--- 제거 ---'
    rmItem        = '  삭제 {0}'
    rmFail        = '  [X] {0} 삭제 실패: {1}'
    restHdr       = '--- 복원: {0} ---'
    restItem      = '  {0}'
    restFail      = '  [X] {0} 복원 실패: {1}'
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
    warn_gta5     = "GTA V Enhanced 는 BattlEye 를 끄지 않으면 아무것도 동작하지 않습니다.`n`n[ 끄는 방법 ]`n 1. 게임을 완전히 종료합니다`n 2. Rockstar Games Launcher 를 엽니다`n 3. 오른쪽 위 톱니바퀴 -> 설정`n 4. 왼쪽 목록에서 Grand Theft Auto V Enhanced 선택`n 5. BattlEye 안티치트 항목의 체크를 해제합니다`n 6. 런처를 껐다 켜니다`n`nBattlEye 가 켜져 있으면 OptiScaler 와 ReShade 가 로드 차단됩니다.`n밴이 아니라 차단입니다.`n`n※ GTA 온라인은 BattlEye 가 필수입니다. 끄면 접속할 수 없으므로`n   스토리 모드 전용이 됩니다. 온라인을 하시려면 다시 켜세요.`n`n계속하시겠습니까?"
    warn_mhw      = "이 게임은 NR 을 켠 채로 화면 전환(로딩)을 하면 크래시하거나 검은 화면에`n멈춥니다. 스왑체인이 다시 만들어지는 타이밍과 겹치기 때문입니다.`n`n[ 지켜야 할 것 ]`n 1. 게임을 켤 때: 반드시 NR 이 꺼진 채로 부팅해서, 타이틀 화면을 지나`n    실제 게임 화면에 완전히 들어온 뒤에만 오버레이(Home 키)에서 NR 을`n    켜세요. 타이틀 화면이나 로딩 중에 켜져 있으면 안 됩니다.`n 2. 타이틀로 돌아갈 때: 게임에서 타이틀로 나가기 전에 먼저 오버레이에서`n    NR 을 도로 끄세요. 켜진 채로 나가면 그 전환에서 크래시합니다.`n 3. ReShade 는 Save Settings 를 안 눌러도 종료 시 현재 상태를 ini 에`n    저장하는 것으로 보입니다. 그러니 게임을 끄기 전에도 NR 을 꺼두는`n    습관을 들이세요 - 다음 부팅이 이 상태를 그대로 물려받습니다.`n`n설치기가 배포하는 ReShade.ini 는 NR 이 꺼진 상태로 시작합니다.`n`n계속하시겠습니까?"
    warnLog       = '[!] 설치 전 확인 사항을 표시했습니다.'
    warnCancel    = '[-] 사용자가 취소했습니다.'
  }
  en = @{
    title         = 'Kiroshi Optics - DLSS 5 Neural Rendering Installer'
    lang          = 'Language'
    game          = 'Game'
    lblPath       = 'Install folder'
    btnAuto       = 'Auto-detect'
    btnBrowse     = 'Browse'
    btnPrepare    = '0. Get files'
    btnCheck      = '1. Check'
    btnInstall    = '2. Install'
    btnRestore    = 'Restore'
    chkReshade    = 'Also install ReShade (filters/preset)'
    askReshadeTitle = 'Install ReShade'
    askReshadeMsg   = 'Also install ReShade (filters/preset)?'
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
    state_bakFail = 'Backup failed - installation aborted'
    state_restOk  = 'Restore complete'
    state_restNg  = 'Restore had failures - see the log'
    state_noBak   = 'No backup found'
    state_prep    = 'Downloading files'
    state_prepOk  = 'Files ready - press [1. Check]'
    state_prepNg  = 'Download failed - see the log'
    state_needMdl = 'Place nvngx_dlssnr.dll in the payload folder'

    hdr1          = 'Kiroshi Optics - OptiScaler DLSS-NR method'
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
    writeOk       = '[O] Write test passed'
    writeNg       = '[X] Cannot write to the game folder: {0}'
    writeNgAdmin  = '    This is under Program Files. Try re-running this installer as Administrator.'
    writeBakNg    = '[X] Cannot write to the backup location: {0}'
    cfaWarn       = "[!] Windows Security's [Controlled Folder Access] is on - writes to protected folders may be blocked.`n    If it blocks you: Windows Security -> Virus & threat protection -> Ransomware protection -> Allow an app through Controlled Folder Access, and add this installer.`n    (This installer never changes that setting for you)"
    sigOk         = '[O] nvngx_dlssnr.dll signature valid: {0}  (SHA-256 {1})'
    sigWarn       = '[!] nvngx_dlssnr.dll is unsigned/invalid ({0}) - normal for a community-modified build.  (SHA-256 {1})'
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
    iniMissing    = '  [!] OptiScaler.ini is missing - could not apply settings: {0}'
    payOk         = '[O] Payload verified'
    proxyUse      = '[O] Proxy name: {0}'
    conflict      = '[!] Conflicting files (backed up and removed on install): {0}'
    noConflict    = '[O] No conflicting files'
    keepRe        = '[-] ReShade is left in place; it uses a different proxy name.'
    otherToolHdr  = '[X] Found traces of another DLSS 5 tool (e.g. DLSS 5 Swapper):'
    otherToolItem = '    - {0}'
    otherToolHelp = "    Restore with that tool first, then try again.`n    If you already removed that tool: Steam -> right-click the game -> Properties -> Installed Files -> Verify integrity of game files to restore the originals.`n    Verify won't remove a leftover _DLSS5_Backup folder in the game folder - delete that one by hand."

    gameRun       = '[X] The game is running. Close it and try again.'
    bakHdr        = '--- Backup: {0}  (outside the game folder) ---'
    bakItem       = '  backed up {0}'
    bakFail       = '  [X] Backup failed: {0}  ({1})'
    bakAbort      = '[X] Backup failed - installation aborted. Check that you have write access to the game folder and the desktop.'
    instHdr       = '--- Install ---'
    instItem      = '  {0}'
    instFail      = '  [X] {0} copy failed: {1}'
    dualGpuApplied = '  [i] 2+ GPUs detected - applying StreamlineSpoofing/Dxgi override'
    vfyHdr        = '--- Verify ---'
    vfyOk         = '  [O] {0}'
    vfyNg         = '  [X] {0} hash mismatch'
    vfyMissing    = '  [X] {0} is missing'
    vfyQuarantine = '  [!] {0} - copy reported success but the file is missing now. Your antivirus may have quarantined it - check Windows Security -> Protection history.'
    bakPath       = 'Backup location: {0}'
    rmHdr         = '--- Remove ---'
    rmItem        = '  removed {0}'
    rmFail        = '  [X] Failed to remove {0}: {1}'
    restHdr       = '--- Restore: {0} ---'
    restItem      = '  {0}'
    restFail      = '  [X] Failed to restore {0}: {1}'
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
    warn_mhw      = "This game crashes or hangs on a black screen if NR is left on across a`nscreen transition (loading) - it collides with the swapchain being`nrecreated.`n`n[ Rules to follow ]`n 1. Booting: always boot with NR off, get all the way past the title`n    screen into the actual game, and only then turn NR on from the`n    overlay (Home key). Never leave it on during the title screen or a`n    loading screen.`n 2. Quitting to title: turn NR off from the overlay BEFORE backing out`n    to the title screen. Leaving it on during that transition crashes.`n 3. ReShade appears to save its current state to the ini on exit even`n    without pressing Save Settings. So get in the habit of turning NR`n    off before closing the game too - the next boot inherits whatever`n    state was last saved.`n`nThe ReShade.ini this installer ships starts with NR off.`n`nContinue?"
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
  $Script:chkReshade.Text = T 'chkReshade'
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
  if (-not (Test-Path $path)) { Log 'iniMissing' @($path); return @() }
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

# Copy-Item/Move-Item/Remove-Item are non-terminating by default: a failure writes to the
# error stream and execution just continues to the next line, so a bare
# `Copy-Item ...; Log 'instItem' ...` logs "installed" even when the copy failed and
# Safe {} never sees an exception to catch. -ErrorAction Stop + try/catch here makes
# failures visible and lets the caller track what actually happened.
function Copy-Step($src, $dst, $desc, [switch]$Recurse) {
  try {
    Copy-Item $src $dst -Force -Recurse:$Recurse -ErrorAction Stop
    Log 'instItem' @($desc)
    return $true
  } catch {
    Log 'instFail' @($desc, $_.Exception.Message)
    return $false
  }
}

function Move-Step($src, $dst, $desc) {
  try {
    Move-Item $src $dst -Force -ErrorAction Stop
    Log 'bakItem' @($desc)
    return $true
  } catch {
    Log 'bakFail' @($desc, $_.Exception.Message)
    return $false
  }
}

function Test-Writable($dir) {
  if (-not (Test-Path $dir)) { return @{ Ok = $false; Msg = 'not found' } }
  $probe = Join-Path $dir ('.kiroshi_write_test_' + [guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [IO.File]::WriteAllBytes($probe, [byte[]](1..1024))
    Remove-Item $probe -Force -ErrorAction Stop
    return @{ Ok = $true }
  } catch {
    return @{ Ok = $false; Msg = $_.Exception.Message }
  }
}

# P: 바탕화면은 OneDrive 로 리디렉션돼 있는 경우가 흔하다 (이 개발 PC 자체가 그렇다) -
# 백업마다 수백 MB가 클라우드로 올라가고, 나중에 파일 온디맨드로 로컬 사본이 비워지면
# 복원이 깨질 수 있다. LOCALAPPDATA 는 동기화 대상이 아니라 여기를 기본으로 쓴다.
function Backup-Root {
  $r = Join-Path $env:LOCALAPPDATA 'KiroshiOptics\backups'
  if (-not (Test-Path $r)) { New-Item -ItemType Directory -Path $r -Force | Out-Null }
  return $r
}

# 기존 사용자의 백업은 바탕화면에 있으므로, 새 위치와 옛 위치 둘 다 뒤져서
# 가장 최근 것을 고른다.
function Find-LatestBackup($p) {
  $roots = @((Backup-Root), ([Environment]::GetFolderPath('Desktop')))
  $all = @()
  foreach ($r in $roots) {
    if (Test-Path $r) {
      $all += Get-ChildItem $r -Directory -Filter ('DLSS5-backup_' + $p.Id + '_*') -ErrorAction SilentlyContinue
    }
  }
  return ($all | Sort-Object Name | Select-Object -Last 1)
}

# O: 제어된 폴더 액세스(랜섬웨어 방지)가 켜져 있으면 허용 목록에 없는 앱의 보호 폴더
# 쓰기가 막힌다. 제3자 백신이면 Get-MpPreference 자체가 의미 없을 수 있으므로
# 조회 실패는 "켜짐"이 아니라 "확인 불가"로 취급한다(경고하지 않음).
function Test-CfaOn {
  try {
    $mp = Get-MpPreference -ErrorAction Stop
    return ($mp.EnableControlledFolderAccess -eq 1)
  } catch {
    return $false
  }
}

function Get-NvidiaGpuCount {
  return @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'NVIDIA' }).Count
}

# $force=$true ignores the checkbox and always merges in OptionalReshade - used by
# Restore, so a stray ReShade install gets cleaned up even if the box is unchecked now.
function Effective-Prof($p, [bool]$force = $false) {
  if (-not $p.OptionalReshade) { return $p }
  $want = $force -or ($Script:chkReshade -and $Script:chkReshade.Checked)
  if (-not $want) { return $p }
  $ep = $p.Clone()
  # Where-Object { $_ } drops $null/'' - a profile missing Extra/ExtraDirs entirely
  # (e.g. no key set) makes @($p.Extra) become @($null), and a $null child path
  # makes Join-Path collapse back to the game folder itself - Remove-Item -Recurse
  # on THAT deletes the whole install. Never let a blank slip into these arrays.
  $ep.Extra = @((@($p.Extra) + @($p.OptionalReshade.Extra)) | Where-Object { $_ })
  $ep.ExtraDirs = @((@($p.ExtraDirs) + @($p.OptionalReshade.ExtraDirs)) | Where-Object { $_ })
  $ini = @{}
  foreach ($sec in $p.IniSet.Keys) { $ini[$sec] = $p.IniSet[$sec].Clone() }
  foreach ($sec in $p.OptionalReshade.IniSet.Keys) {
    if (-not $ini.ContainsKey($sec)) { $ini[$sec] = @{} }
    foreach ($k in $p.OptionalReshade.IniSet[$sec].Keys) { $ini[$sec][$k] = $p.OptionalReshade.IniSet[$sec][$k] }
  }
  $ep.IniSet = $ini
  return $ep
}

function Payload-Files($p) {
  if ($p.Method -eq 'reshade') {
    $dir = Join-Path $Script:Payload $p.Id
    $f = @{
      $p.Proxy           = (Join-Path $dir $p.Proxy)
      'nvngx_dlssnr.dll' = (Join-Path $Script:Payload 'nvngx_dlssnr.dll')
    }
    foreach ($e in $p.Extra) { $f[$e] = (Join-Path $dir $e) }
    return $f
  }
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
  Say 'state_prep' @() ([System.Drawing.Color]::Black)
  Log 'prepHdr'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $mhwOpti = Join-Path $Script:Payload 'optiscaler-mhwilds'
  foreach ($d in $Script:Payload, $Script:Opti, $mhwOpti, (Join-Path $Script:Payload 'dd2')) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
  }
  $ok = $true

  if (-not (Test-Path (Join-Path $Script:Opti 'OptiScaler.dll'))) {
    $url = 'https://github.com/Dagherbou/OptiScaler_DLSSNR/releases/download/v0.1.1.5-dlssnr/OptiScaler-DLSSNR-v0.1.1.5-dlssnr.zip'
    $zip = Join-Path $env:TEMP 'OptiScaler-DLSSNR.zip'
    try {
      Log 'prepDl' @('OptiScaler-DLSSNR-v0.1.1.5-dlssnr.zip')
      Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
      Log 'prepDone' @('OptiScaler-DLSSNR.zip', (Get-Item $zip).Length)
      Log 'prepExtract' @('OptiScaler-DLSSNR.zip')
      Expand-Archive -Path $zip -DestinationPath $Script:Opti -Force
      Remove-Item $zip -Force -ErrorAction SilentlyContinue
    } catch { Log 'prepFail' @('OptiScaler'); $ok = $false }
  }
  else { Log 'prepSkip' @('OptiScaler') }

  # 몬스터 헌터 와일즈 / 연운십육성 전용 빌드 (v0.2.0-patch1) - 이 게임들만 OptiDir='optiscaler-mhwilds'.
  # 예전엔 이 폴더를 채우는 코드가 없어서 새로 받은 사람은 [1. 검사]에서 막혔음(payNg).
  if (-not (Test-Path (Join-Path $mhwOpti 'OptiScaler.dll'))) {
    $url2 = 'https://github.com/Dagherbou/OptiScaler_DLSSNR/releases/download/v0.2.0-patch1/OptiScaler-DLSSNR-v0.2.0-onimusha-fix.zip'
    $zip2 = Join-Path $env:TEMP 'OptiScaler-DLSSNR-mhwilds.zip'
    try {
      Log 'prepDl' @('OptiScaler-DLSSNR-v0.2.0-onimusha-fix.zip')
      Invoke-WebRequest -Uri $url2 -OutFile $zip2 -UseBasicParsing
      Log 'prepDone' @('OptiScaler-DLSSNR-mhwilds.zip', (Get-Item $zip2).Length)
      Log 'prepExtract' @('OptiScaler-DLSSNR-mhwilds.zip')
      Expand-Archive -Path $zip2 -DestinationPath $mhwOpti -Force
      Remove-Item $zip2 -Force -ErrorAction SilentlyContinue
    } catch { Log 'prepFail' @('optiscaler-mhwilds'); $ok = $false }
  }
  else { Log 'prepSkip' @('optiscaler-mhwilds') }

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

  if (-not (Test-Path (Join-Path $Script:Payload 'nvngx_dlssnr.dll'))) {
    Log 'mdlNg'; Log 'mdlHint'; Log 'mdlHint2'
    Say 'state_needMdl' @() ([System.Drawing.Color]::Firebrick); return
  }
  if ($ok) { Say 'state_prepOk' @() ([System.Drawing.Color]::SeaGreen) }
  else { Say 'state_prepNg' @() ([System.Drawing.Color]::Firebrick) }
}

function Run-Check {
  $p = Effective-Prof $Script:Prof
  $ok = $true
  Log 'ckStart'

  if (-not $Script:Game -or -not (Test-Path (Join-Path $Script:Game $p.Exe))) {
    Log 'noPath'; Say 'state_needPath' @() ([System.Drawing.Color]::Firebrick); return $false
  }
  Log 'folder' @($Script:Game)

  $wt = Test-Writable $Script:Game
  if ($wt.Ok) { Log 'writeOk' }
  else {
    Log 'writeNg' @($wt.Msg)
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ((-not $isAdmin) -and ($Script:Game -match '^[A-Za-z]:\\Program Files')) { Log 'writeNgAdmin' }
    $ok = $false
  }
  $dwt = Test-Writable (Backup-Root)
  if (-not $dwt.Ok) { Log 'writeBakNg' @($dwt.Msg); $ok = $false }

  if (Test-CfaOn) { Log 'cfaWarn' }

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
  if ($p.Method -ne 'reshade') {
    $od = Opti-Dir $p
    if (-not (Test-Path (Join-Path $od 'OptiScaler'))) { Log 'payNg' @('OptiScaler\'); $ok = $false }
  }
  foreach ($d in $p.ExtraDirs) {
    if (-not $d) { continue }
    if (-not (Test-Path (Join-Path $Script:Payload ($p.Id + '\' + $d)))) { Log 'payNg' @(($d + '\')); $ok = $false }
  }
  if ($p.IniMode -eq 'project') {
    $i = $files['OptiScaler.ini']
    if ((Test-Path $i) -and ((Get-Item $i).Length -gt 2000)) { Log 'iniNg'; $ok = $false }
  }
  if ($ok) { Log 'payOk' }
  Log 'proxyUse' @($p.Proxy)

  # D: nvngx_dlssnr.dll 서명 검증. 지금 배포 중인 310.8.SF 커뮤니티 수정본 자체가
  # NotSigned 라, Valid 만 통과시키면 전원 차단된다 - 그래서 경고만 하고 막지 않는다.
  $nrDll = Join-Path $Script:Payload 'nvngx_dlssnr.dll'
  if (Test-Path $nrDll) {
    $sig = Get-AuthenticodeSignature $nrDll
    $hash = (Get-FileHash $nrDll -Algorithm SHA256).Hash
    if ($sig.Status -eq 'Valid') { Log 'sigOk' @($sig.SignerCertificate.Subject, $hash) }
    else { Log 'sigWarn' @($sig.Status, $hash) }
  }

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

  # C: 다른 DLSS 5 도구(DLSS 5 Swapper 등)의 잔재. 겹쳐 설치하면 프록시 DLL 자리가
  # 충돌해서 "설치는 성공했는데 화면이 이상함" 증상이 남는다 - 감지되면 설치를 막는다.
  $otherTool = @()
  foreach ($n in '_DLSS5_Backup', 'dlss5-feed.addon64', 'dlss5-feed.cfg', 'dgVoodoo.conf') {
    if (Test-Path (Join-Path $Script:Game $n)) { $otherTool += $n }
  }
  foreach ($n in 'reshade-shaders\Shaders\DLSS5_Feed.fx', 'reshade-shaders\Shaders\MartysMods_LAUNCHPAD.fx') {
    if (Test-Path (Join-Path $Script:Game $n)) { $otherTool += $n }
  }
  $proxyNames = 'dxgi.dll', 'd3d12.dll', 'd3d11.dll', 'version.dll', 'winmm.dll', 'dbghelp.dll'
  $okProxy = @($p.Proxy) + @($p.OtherProxyOk)
  if ($p.KeepRe) { $okProxy += 'dxgi.dll' }  # ReShade가 이미 여기 있는 게 이 게임에선 정상이고 위에서 별도로 다룬다
  foreach ($n in $proxyNames) {
    if (($okProxy -notcontains $n) -and (Test-Path (Join-Path $Script:Game $n))) { $otherTool += $n }
  }
  if ($otherTool.Count) {
    Log 'otherToolHdr'
    foreach ($n in $otherTool) { Log 'otherToolItem' @($n) }
    Log 'otherToolHelp'
    $ok = $false
  }

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
  if ($Script:Prof.OptionalReshade) {
    $ra = [System.Windows.Forms.MessageBox]::Show((T 'askReshadeMsg'), (T 'askReshadeTitle'), 'YesNo', 'Question')
    $Script:chkReshade.Checked = ($ra -eq 'Yes')
  }
  $p = Effective-Prof $Script:Prof
  if (Game-Running $p) { Log 'gameRun'; Say 'state_running' @() ([System.Drawing.Color]::Firebrick); return }
  if ($p.Warn) {
    Log 'warnLog'
    $r = [System.Windows.Forms.MessageBox]::Show((T $p.Warn), (T 'warnTitle'), 'OKCancel', 'Warning')
    if ($r -ne 'OK') { Log 'warnCancel'; return }
  }
  if (-not (Run-Check)) { return }

  $bk = Join-Path (Backup-Root) ('DLSS5-backup_' + $p.Id + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
  New-Item -ItemType Directory -Path $bk -Force | Out-Null
  Log 'bakHdr' @($bk)

  $bakFailed = $false
  $move = @($p.Proxy, 'OptiScaler.ini', 'nvngx_dlssnr.dll', 'nvngx.dll_dlssnr.dll', 'OptiScaler.asi') + $p.Extra
  if (-not $p.KeepRe) { $move += @('dxgi.dll', 'd3d12.dll', 'ReShade.ini', 'ReShade.log', 'ReShade.log.prev', 'ReShadePreset.ini') }
  foreach ($n in ($move | Select-Object -Unique)) {
    if (-not $n) { continue }
    $s = Join-Path $Script:Game $n
    if (Test-Path $s) { if (-not (Move-Step $s (Join-Path $bk $n) $n)) { $bakFailed = $true } }
  }
  $dirs = @('OptiScaler')
  if (-not $p.KeepRe) { $dirs += 'reshade-shaders' }
  $dirs += $p.ExtraDirs
  foreach ($d in ($dirs | Select-Object -Unique)) {
    if (-not $d) { continue }
    $s = Join-Path $Script:Game $d
    if (Test-Path $s) { if (-not (Move-Step $s (Join-Path $bk $d) ($d + '\'))) { $bakFailed = $true } }
  }
  foreach ($a in (Get-ChildItem $Script:Game -Filter '*.addon64' -ErrorAction SilentlyContinue)) {
    if (-not (Move-Step $a.FullName (Join-Path $bk $a.Name) $a.Name)) { $bakFailed = $true }
  }

  # 백업 자체가 실패한 채로 설치를 진행하면, 뭔가 잘못됐을 때 원본으로 돌아갈 방법이 없다.
  # (Controlled Folder Access 등으로 바탕화면 쓰기가 막힌 경우가 대표적)
  if ($bakFailed) {
    Log 'bakAbort'
    Say 'state_bakFail' @() ([System.Drawing.Color]::Firebrick)
    return
  }

  Log 'instHdr'
  $files = Payload-Files $p
  $od = Opti-Dir $p
  $copyFails = @()

  # ini부터 먼저: 실패해도 뒤에 오는 대용량 OptiScaler\ 폴더 복사와 무관하게 항상 시도된다.
  if ($p.Method -ne 'reshade') {
    if (-not (Copy-Step $files['OptiScaler.ini'] (Join-Path $Script:Game 'OptiScaler.ini') 'OptiScaler.ini')) { $copyFails += 'OptiScaler.ini' }
  }
  foreach ($k in ($files.Keys | Where-Object { $_ -ne 'OptiScaler.ini' })) {
    if (-not (Copy-Step $files[$k] (Join-Path $Script:Game $k) $k)) { $copyFails += $k }
  }
  if ($p.Method -ne 'reshade') {
    $dstOd = Join-Path $Script:Game 'OptiScaler'
    # 백업 Move가 실패했다면 이미 위에서 걸렀지만, 방어적으로 한 번 더 -
    # 대상 폴더가 남아있으면 Copy-Item -Recurse가 그 안에 중첩 복사(game\OptiScaler\OptiScaler\...)를
    # 만들어버리는데, 에러 없이 조용히 성공한 것처럼 끝나서 SilentlyContinue로 지우기만 실패해도
    # 아무도 못 알아챈다(J) - 그래서 이 정리 자체를 실패로 취급해서 복사를 아예 안 하게 막는다.
    $clearOk = $true
    if (Test-Path $dstOd) {
      try { Remove-Item $dstOd -Recurse -Force -ErrorAction Stop }
      catch { Log 'instFail' @('OptiScaler\ (기존 폴더 정리)', $_.Exception.Message); $clearOk = $false }
    }
    if ($clearOk) {
      if (-not (Copy-Step (Join-Path $od 'OptiScaler') $dstOd 'OptiScaler\' -Recurse)) { $copyFails += 'OptiScaler\' }
    } else { $copyFails += 'OptiScaler\' }
  }
  foreach ($d in $p.ExtraDirs) {
    if (-not $d) { continue }
    $src = Join-Path $Script:Payload ($p.Id + '\' + $d)
    if (-not (Copy-Step $src (Join-Path $Script:Game $d) ($d + '\') -Recurse)) { $copyFails += ($d + '\') }
  }

  Log 'vfyHdr'
  $bad = $copyFails.Count
  foreach ($k in $files.Keys) {
    $tgt = Join-Path $Script:Game $k
    if (-not (Test-Path $tgt)) {
      # O: Copy-Step가 성공을 찍었는데 지금 보니 없다 - 백신 격리 가능성이 높다.
      if ($copyFails -notcontains $k) { Log 'vfyQuarantine' @($k) } else { Log 'vfyMissing' @($k) }
      $bad++; continue
    }
    if (-not (Test-Path $files[$k])) { Log 'vfyMissing' @($k); $bad++; continue }
    $h1 = (Get-FileHash $files[$k] -Algorithm SHA256).Hash
    $h2 = (Get-FileHash $tgt -Algorithm SHA256).Hash
    if ($h1 -eq $h2) { Log 'vfyOk' @($k) } else { Log 'vfyNg' @($k); $bad++ }
  }

  # F: 듀얼 GPU 전제값(StreamlineSpoofing 등)은 GPU 2장 감지될 때만 적용한다 -
  # 단일 GPU에선 불필요하거나 오히려 손해일 수 있다.
  $iniSet = @{}
  if ($p.IniSet) { foreach ($sec in $p.IniSet.Keys) { $iniSet[$sec] = $p.IniSet[$sec].Clone() } }
  if ($p.DualGpuIniSet -and (Get-NvidiaGpuCount) -ge 2) {
    foreach ($sec in $p.DualGpuIniSet.Keys) {
      if (-not $iniSet.ContainsKey($sec)) { $iniSet[$sec] = @{} }
      foreach ($k in $p.DualGpuIniSet[$sec].Keys) { $iniSet[$sec][$k] = $p.DualGpuIniSet[$sec][$k] }
    }
    Log 'dualGpuApplied'
  }
  foreach ($t in (Apply-IniSet (Join-Path $Script:Game 'OptiScaler.ini') $iniSet)) {
    Log 'instItem' @('OptiScaler.ini  ' + $t)
  }
  if ($p.Method -ne 'reshade') {
    # E: 로깅을 기본으로 켜둔다 - OptiScaler.ini가 없으면 다음 문제가 생겨도 진단 자체가 불가능하다.
    foreach ($t in (Apply-IniSet (Join-Path $Script:Game 'OptiScaler.ini') @{ Log = @{ LogToFile = 'true'; LogLevel = '2' } })) {
      Log 'instItem' @('OptiScaler.ini  ' + $t)
    }
  }
  if ($p.GfxIni) {
    $gp = Join-Path $Script:Game $p.GfxIni.File
    if (Test-Path $gp) {
      Copy-Item $gp (Join-Path $bk $p.GfxIni.File) -Force
      Log 'bakItem' @($p.GfxIni.File)
      foreach ($t in (Apply-IniSet $gp $p.GfxIni.Set)) { Log 'instItem' @(($p.GfxIni.File + '  ' + $t)) }
    }
    else { Log 'instItem' @(($p.GfxIni.File + ' not found yet - launch the game once, then press [2. Install] again')) }
  }

  if ($bad) { Say 'state_instNg' @() ([System.Drawing.Color]::Firebrick) }
  else { Say 'state_instOk' @($p.OverlayKo) ([System.Drawing.Color]::SeaGreen) }
  Log 'bakPath' @($bk)
}

function Run-Restore {
  $p = Effective-Prof $Script:Prof $true
  if (Game-Running $p) { Log 'gameRun'; Say 'state_running' @() ([System.Drawing.Color]::Firebrick); return }
  if (-not $Script:Game) { Log 'noPath'; return }

  $bk = Find-LatestBackup $p
  if (-not $bk) { Log 'noBakFound'; Say 'state_noBak' @() ([System.Drawing.Color]::Firebrick); return }

  Log 'rmHdr'
  $rmFails = @()
  $rm = @($p.Proxy, 'OptiScaler.ini', 'OptiScaler.log', 'nvngx_dlssnr.dll', 'nvngx.dll_dlssnr.dll') + $p.Extra
  foreach ($n in ($rm | Select-Object -Unique)) {
    if (-not $n) { continue }
    $t = Join-Path $Script:Game $n
    if (Test-Path $t) {
      try { Remove-Item $t -Force -ErrorAction Stop; Log 'rmItem' @($n) }
      catch { Log 'rmFail' @($n, $_.Exception.Message); $rmFails += $n }
    }
  }
  $od = Join-Path $Script:Game 'OptiScaler'
  if (Test-Path $od) {
    try { Remove-Item $od -Recurse -Force -ErrorAction Stop; Log 'rmItem' @('OptiScaler\') }
    catch { Log 'rmFail' @('OptiScaler\', $_.Exception.Message); $rmFails += 'OptiScaler\' }
  }
  foreach ($d in $p.ExtraDirs) {
    if (-not $d) { continue }
    $t = Join-Path $Script:Game $d
    if (Test-Path $t) {
      try { Remove-Item $t -Recurse -Force -ErrorAction Stop; Log 'rmItem' @(($d + '\')) }
      catch { Log 'rmFail' @(($d + '\'), $_.Exception.Message); $rmFails += ($d + '\') }
    }
  }

  Log 'restHdr' @($bk.Name)
  $restFails = @()
  foreach ($i in (Get-ChildItem $bk.FullName)) {
    try { Copy-Item $i.FullName (Join-Path $Script:Game $i.Name) -Recurse -Force -ErrorAction Stop; Log 'restItem' @($i.Name) }
    catch { Log 'restFail' @($i.Name, $_.Exception.Message); $restFails += $i.Name }
  }
  if ($rmFails.Count -or $restFails.Count) { Say 'state_restNg' @() ([System.Drawing.Color]::Firebrick) }
  else { Say 'state_restOk' @() ([System.Drawing.Color]::SeaGreen) }
}

# ---------------------------------------------------------------- UI
$form = New-Object System.Windows.Forms.Form
$form.Size = New-Object System.Drawing.Size(790, 674)
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

$chkReshade = New-Object System.Windows.Forms.CheckBox
$chkReshade.Location = New-Object System.Drawing.Point(14, 150)
$chkReshade.Size = New-Object System.Drawing.Size(752, 22)
$chkReshade.Checked = $false
$form.Controls.Add($chkReshade); $Script:chkReshade = $chkReshade

$lblState = New-Object System.Windows.Forms.Label
$lblState.Location = New-Object System.Drawing.Point(14, 178)
$lblState.Size = New-Object System.Drawing.Size(752, 22)
$form.Controls.Add($lblState); $Script:lblState = $lblState

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(14, 208)
$txtLog.Size = New-Object System.Drawing.Size(752, 406)
$txtLog.Multiline = $true; $txtLog.ScrollBars = 'Vertical'; $txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($txtLog); $Script:txtLog = $txtLog

$cboLang.Add_SelectedIndexChanged({
  $Script:Lang = $(if ($cboLang.SelectedIndex -eq 0) { 'en' } else { 'ko' })
  Apply-Lang
})

function Sync-ReshadeCheckbox {
  $has = [bool]$Script:Prof.OptionalReshade
  $Script:chkReshade.Visible = $has
  $Script:chkReshade.Enabled = $has
}

$cboGame.Add_SelectedIndexChanged({
  if ($cboGame.SelectedIndex -lt 0) { return }
  $Script:Prof = $Script:Games[$cboGame.SelectedIndex]
  Sync-ReshadeCheckbox
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
