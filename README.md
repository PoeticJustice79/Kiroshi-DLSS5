# Kiroshi Optics DLSS5 Installer

게임에 뉴럴 렌더링을 이식합니다.

One-click DLSS 5 Neural Rendering installer (OptiScaler + ReShade) for 8 verified games. Korean
and English UI.

This repository contains the installer only. It fetches OptiScaler and any game-specific
components from their original projects at run time and never redistributes them.

```
Auto-detect  ->  0. Get files  ->  1. Check  ->  2. Install
```

## Supported games

| Game | Version tested on | Notes |
|---|---|---|
| Monster Hunter Wilds | current | see below - REFramework required, `d3d12.dll` crashes at boot |
| Monster Hunter World (2018) | current | different method entirely - ReShade + `renodx-dlss.addon64`, not OptiScaler; see below |
| Dragon's Dogma 2 | 3.2.0.0 | see [DD2-DLSS5-Installer](https://github.com/PoeticJustice79/DD2-DLSS5-Installer) for a focused, DD2-only build of the same tool |
| FINAL FANTASY VII REBIRTH | current | ReShade already installed is left in place |
| The Witcher 3 | current (DX12 build) | ReShade already installed is left in place |
| Grand Theft Auto V Enhanced | current | requires BattlEye off in the Rockstar launcher, single-player only |
| Cyberpunk 2077 | 2.21 | see below - dual-GPU rigs need a spoofing fix, applied automatically |
| Where Winds Meet | current | run folder is `Win64r` (not a typo); ReShade install is optional (checkbox) |

Not supported: **Red Dead Redemption 2** (OptiScaler doesn't fit this game - handled separately
with Vulkan + DLSS5-Feeder + LumeniteFX, outside this tool) and **Crimson Desert** (moved to
OptiScaler_DLSSNR manually, no profile here yet).

**If you previously used another DLSS 5 tool (e.g. DLSS 5 Swapper) on the same game, fully
uninstall/restore it first.** Leftover files from a different tool can occupy the same proxy DLL
name this installer needs, which silently breaks rendering instead of failing cleanly.

## Requirements

| | |
|---|---|
| GPU | RTX card |
| Driver | NVIDIA `616.56` or newer |

The **Check** step verifies the game, GPU and driver, and refuses to install if the driver is
too old.

**You supply `nvngx_dlssnr.dll` yourself** and place it in `payload\`. It is an NVIDIA file and
is not redistributed here. The **DLSS-NR model** is available from the RenoDX Discord; `310.8.SF`
is the build documented as covering RTX 20 through 50.

## Install

1. Close the game.
2. Run `Install.cmd`.
3. Pick the game from the dropdown, then press **[Auto-detect]**, **[0. Get files]**,
   **[1. Check]**, **[2. Install]**.

`[0. Get files]` downloads OptiScaler (and, for Dragon's Dogma 2, its REFramework `dinput8.dll`)
from their original release pages. It cannot fetch `nvngx_dlssnr.dll` — see above.

## Monster Hunter Wilds specifics

- **REFramework is required and is not installed by this tool.** Get it from Nexus Mods first;
  without it the game won't accept the modified files at all.
- The proxy is `dxgi.dll`. Placing OptiScaler at `d3d12.dll` instead crashes the game at boot —
  the game folder has a hidden `_storage_\` integrity-mirror folder that appears to watch that
  name specifically (the same family of anti-tamper Dragon's Dogma 2 uses).
- REFramework already uses **Insert** for its own overlay, so the installer rebinds OptiScaler's
  menu key to **Delete** (`[Menu] ShortcutKey=0x2E`) to avoid the two overlays fighting over the
  same key.
- This game's OptiScaler build is fetched from a specific release
  ([v0.2.0-patch1](https://github.com/Dagherbou/OptiScaler_DLSSNR/releases/tag/v0.2.0-patch1)) —
  not necessarily the same version the other games in this list use. Build compatibility is
  per-game; newer is not always better. `v0.1.2` crashes this specific game at boot
  (access violation inside the game's own code).
- **ReShade can run alongside NR and Frame Generation**, but not by giving it its own proxy
  name — OptiScaler has to load it internally. Rename ReShade's DLL to `ReShade64.dll`, put it
  in the game folder next to OptiScaler, and set `LoadReshade=true` under `[Plugins]` in
  `OptiScaler.ini`. This is optional and not automated by the installer, since it assumes you
  already have your own ReShade preset you want to keep using.

## Monster Hunter World (2018) specifics

- **Not OptiScaler.** `MonsterHunterWorld.exe` is packed/protected, so OptiScaler's hooks never
  attach (loads as `d3d11.dll` but the device-creation hook never fires). ReShade is the only
  thing that hooks successfully in this game, so this profile installs ReShade +
  [`renodx-dlss.addon64`](https://github.com/clshortfuse/renodx) (ShortFuse's add-on) instead.
- **Force `DirectX12Enable=Off`** in `graphics_option.ini` - the installer does this
  automatically after your first launch. Leaving DX12 on crashes inside the system `dxgi.dll`
  (a ReShade D3D11-on-12 issue).
- **Never leave Neural Rendering on across a loading screen** - it collides with the swapchain
  being recreated and crashes or hangs on a black screen. Boot with NR off, get all the way into
  the game, then turn it on from the overlay (**Home**); turn it back off before returning to the
  title screen. ReShade saves its last state on exit (even a crash), so a crash with NR on gets
  inherited by the next boot.

## Where Winds Meet specifics

- The run folder is `Engine\Binaries\Win64r` - not a typo.
- Every usual proxy slot is already taken by something else in this game, so the proxy is fixed
  to `dxgi.dll`. The game ships its own native Streamline/DLSS, so NR hooks the existing DLSS
  calls rather than redirecting FSR like Monster Hunter Wilds does.
- ReShade is optional here (checkbox) rather than required.
- This game has CrashHunter anti-cheat; verified for single-player/offline content only.

## In game

1. Graphics settings -> upscaler = **NVIDIA DLSS** (DLAA also works)
2. Press the overlay key shown after install (**Insert** for most games here, **Delete** for
   Monster Hunter Wilds — REFramework keeps Insert for itself there)
3. Expand **DLSS Neural Rendering** -> tick **Enable Neural Rendering**
4. A green **Running - N ms per frame** means it is working
5. Press **Save Settings** (bottom right) so it survives a restart

## Uninstall

Open the installer, pick the game, and press **[Restore]**. It removes what it installed and
puts the backup back. Backups go to `Desktop\DLSS5-backup_<game>_<timestamp>`, deliberately
**outside** the game folder — a copy left inside it gets picked up as a second instance of the
same DLL.

## Notes

- Experimental. Not an official NVIDIA release.
- Single-player only. Do not use with anti-cheat.
- Build compatibility (both OptiScaler and, where relevant, REFramework) is per-game. If
  something that used to work stops working after an update, try a different build before
  assuming your setup is broken.

## Credits

| | |
|---|---|
| OptiScaler DLSS-NR | [Dagherbou/OptiScaler_DLSSNR](https://github.com/Dagherbou/OptiScaler_DLSSNR) |
| OptiScaler | [optiscaler/OptiScaler](https://github.com/optiscaler/OptiScaler) |
| DLSS 5 colour composition | [RenoDX](https://github.com/clshortfuse/renodx) by clshortfuse (MIT), used by OptiScaler_DLSSNR |
| REFramework | [praydog/REFramework](https://github.com/praydog/REFramework) (MIT) |
| Dragon's Dogma 2 install method | [dmitrysobolev/DD2-DLSS5](https://github.com/dmitrysobolev/DD2-DLSS5) |

This installer only automates their instructions.

한국어 안내는 [`GUIDE.ko.txt`](GUIDE.ko.txt) 를 보세요.
