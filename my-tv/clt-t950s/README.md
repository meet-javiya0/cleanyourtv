# CLT SMART_TV — setup runbook

A personal record of everything that was done to one TV, kept so the setup can be rebuilt or undone
without the original session. **This folder is not part of upstream CleanYourTV** — it lives on a branch
of a fork, and it describes one specific set.

The two changes that matter are on this same branch:

| Commit | What |
|---|---|
| `Launcher: direct-boot-aware Home…` | the boot fix, 3 files, the thing that made this TV start Home before unlock |
| `config: this TV's dock, inputs pill and hidden apps` | this TV's `config.xml` |

Nothing here contains the TV's IP address or serial number; use `<tv ip>` (found under
Settings → Network) wherever the commands below show it.

---

## 1. The TV

| | |
|---|---|
| Model reported | `SMART_TV` |
| Board | `TP.SK535.PB802` — Amlogic T950S, CVTE firmware |
| Android | 14 (SDK 34) |
| RAM | 958 MB |
| Encryption | file-based (`ro.crypto.type=file`) |
| FallbackHome | **none** — this is what makes the boot fix necessary |
| Stock launcher | `com.cvte.tv.launcher.mars` — **enabled, never runs** |
| Launcher | `com.gathin.tvhome` = the HOME app |

---

## 2. What was done

| # | Change | Undo |
|---|---|---|
| 1 | Backed up package list, disabled list, `getprop`, settings | — |
| 2 | 348 components disabled across 34 packages | `restore.sh` (§3) |
| 3 | CleanYourTV launcher installed and made HOME | reinstall stock launcher (§7) |
| 4 | Dock: YouTube, JioHotstar, VLC, Play Store | `config.xml` |
| 5 | Launcher clock as screensaver, not the CVTE ad one | — |
| 6 | Direct-boot fix so Home draws before the unlock | revert the commit (§7) |
| 7 | 5 apps AOT-compiled | `cmd package compile -m verify` (§7) |
| 8 | `ambient-glass` theme, 5 columns, rotating wallpapers | `tools/theme.sh --reset` (§6) |
| 9 | ADB turned off in the CVTE factory menu (2026-11-13) | factory menu |

---

## 3. Debloat

`components-disabled.txt` in this folder — 348 `package component` pairs, the authoritative record.

| Package | Components | What it is |
|---|---|---|
| `com.google.android.apps.wellbeing` | 105 | Digital Wellbeing |
| `com.cvte.tv.pictorial` | 25 | CVTE ad/art screensaver |
| `com.android.devicelockcontroller` | 22 | Device lock |
| `com.android.ext.adservices.api` | 20 | Privacy sandbox |
| `com.seraphic.openinet.cvte` | 19 | CVTE OTT/web portal |
| `com.android.adservices.api` | 19 | Privacy sandbox |
| `com.google.android.apps.restore` | 14 | Restore from old device |
| `com.android.managedprovisioning` | 13 | Enterprise provisioning |
| `com.stark.bytelloremoteserver` | 11 | Remote-app server |
| `com.zeasn.services.general` | 10 | Whale/Zeasn services |
| `com.android.providers.contacts` | 10 | Contacts provider |
| + 23 more | 61 | setup, telemetry, print, VPN dialogs, etc. |

### Two things to remember

- **Package-level `pm disable-user` does not survive a reboot on this firmware.** It is reset at every boot.
  Component-level disables (`pm disable-user --user 0 <pkg>/<component>`) **do** survive. That is why the list
  is 348 components and why `pm list packages -d` shows 0.
- Nothing was **uninstalled**. Every step is reversible, and the 34 packages sit on read-only `/system` or
  `/apex`, so removing them would free 0 KB of the 2.1 GB `/data` anyway.

### Verify it is still applied

```bash
adb -s <tv ip>:5555 shell \
  'dumpsys package | awk "/disabledComponents:/{f=1;next} /^      [A-Za-z]/{f=0} f && /^        /{print}" | wc -l'
```

### Packages deliberately left enabled

TV app and input services (HDMI/tuner), input/source menu, remote and Bluetooth pairing, on-screen keyboard,
Play Store and Play Services, the voice assistant and Chromecast/Miracast, and the firmware updater
(`com.cvte.tv.systemupgrade`) — OTA updates are kept on purpose.

Also **never** disable the Android core set: `com.android.providers.*`, `com.android.systemui`,
`com.android.settings`, `com.android.shell`, `com.android.permissioncontroller`, `android.ext.services`,
`android.ext.shared`, `com.google.android.overlay.modules*`. Android may not boot without them.

### Undo

```bash
TV_HOST=<tv ip> my-tv/clt-t950s/restore.sh
```

---

## 4. The boot fix

This is the change worth keeping. It is commit `fec7831c` on this branch.

### The problem

This board has file-based encryption and **no FallbackHome**. At every cold boot:

1. ~17 s — the firmware (uid 0) asks for HOME, **before the user is unlocked**.
2. The old launcher's `MainActivity` was not direct-boot aware, so the request was refused.
3. The firmware fell back to its own launcher (`com.cvte.tv.launcher.mars`, 7.4 s to draw).
4. ~10 s later it started the new launcher. Total: **34 s**, or 44 s when the stock one won the race.

### The fix — 3 files

| File | Change |
|---|---|
| `AndroidManifest.xml` | `android:directBootAware="true"` on `MainActivity` |
| `MainActivity.java` | `locked` field, `unlockReceiver` for `ACTION_USER_UNLOCKED` → `recreate()`; guards in `onNewIntent`, `onStart`, `onResume`, `onPause`, `onStop`, `onDestroy`, `onWindowFocusChanged`, `onTrimMemory`, `dispatchKeyEvent` |
| `LauncherLocale.java` | `wrap()` returns `base` unread while locked |

The third one is the non-obvious one: **`attachBaseContext()` runs before `onCreate()`**, so lifecycle guards
alone are not enough. `LauncherLocale.wrap()` calls `Config.load()`, which reads credential-protected storage
and throws. That crashed the launcher three times and delayed the first frame by 11 s.

### Result (measured with `logcat -v monotonic`)

| | Before | After |
|---|---|---|
| Firmware asks for Home | 33 s | **17.1 s** |
| Home's first frame | 34 s (44 s worst case) | **20.5 s** |
| User unlock | ~26 s | 22.4 s |
| Stock launcher starts | every boot | **never** |

### Verify it

```bash
adb -s <tv ip>:5555 reboot; sleep 12
until [ "$(adb -s <tv ip>:5555 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 2; done
sleep 10
adb -s <tv ip>:5555 shell 'logcat -v monotonic -d | grep -E "START u0.*MainActivity|Displayed com.gathin|Displayed com.cvte.tv.launcher" | tail -4'
```

Healthy output: `MainActivity` START ~17 s, `Displayed` ~20 s, **no** `com.cvte.tv.launcher` line.

### `PARTIALLY_DIRECT_BOOT_AWARE` is expected

`dumpsys package com.gathin.tvhome` prints `PARTIALLY_DIRECT_BOOT_AWARE`. That describes the **package** —
the input-key service and the screensaver are not aware — not the activity that answers HOME. To check the
activity itself, dump the APK manifest:

```bash
docker run --rm -v "$PWD":/repo cleanyourtv-android-build bash -lc \
  '/opt/android-sdk/build-tools/34.0.0/aapt2 dump xmltree /repo/launcher/app/build/outputs/apk/release/app-release.apk --file AndroidManifest.xml' \
  | grep -A12 MainActivity | grep directBootAware
```

### Upstream

The same fix is **PR #1448** (`luciouskami`, Hisense E5Q-PRO, Android 11). The evidence from this TV was
posted there, and the `LauncherLocale` guard was handed to the author because their branch predates that file.
The PR was still `CONFLICTING` with `main` and waiting on the maintainer's cold boot on a Mi TV 4A.

---

## 5. Launcher build and install

```bash
# build (runs unit tests + lint + release APK)
tools/docker-build.sh launcher testReleaseUnitTest lintRelease assembleRelease

# APK size gate: must be under 589,824 B (576 KB)
stat -c %s launcher/app/build/outputs/apk/release/app-release.apk

# install
SKIP_BUILD=1 TV_HOST=<tv ip> HOME_KEY_SERVICE=1 STOCK_LAUNCHER=none launcher/build-and-install.sh
```

### After every reinstall

Reinstalling **clears the "Always → Home" choice** and can bring back the Home chooser. Fix it without the
remote:

```bash
adb -s <tv ip>:5555 shell 'cmd role add-role-holder android.app.role.HOME com.gathin.tvhome;
  cmd package set-home-activity --user 0 com.gathin.tvhome/.MainActivity;
  input keyevent KEYCODE_BACK'
```

Check: `cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME`
should end in `com.gathin.tvhome/.MainActivity`.

---

## 6. Theme: ambient-glass

Upstream's `dock_apps` are Netflix / Amazon Video / Apple TV, which this TV does not have, so the modified copy
is `theme/config.json` in this folder: ambient-glass visuals, this TV's four dock apps, 5 columns.

| Key | Value |
|---|---|
| `columns` | 5 |
| `dock_apps` | YouTube, JioHotstar, VLC, Play Store |
| `fill_dock` | `true` — the 5th slot takes the first grid app (the USB media app) |
| `wallpaper_rotation_minutes` | 1 |
| `dock_glass` / `dock_opacity` | `true` / 40 |
| `clock_wallpaper` / `clock_wallpaper_dim` | `true` / 25 |

```bash
# stage the folder where theme.sh can read it, then push
mkdir -p /tmp/clt-theme && cp -r my-tv/clt-t950s/theme/* /tmp/clt-theme/
cp -r themes/ambient-glass/wallpapers /tmp/clt-theme/
TV_HOST=<tv ip> tools/theme.sh /tmp/clt-theme

# back to the built-in look
TV_HOST=<tv ip> tools/theme.sh --reset
```

**Wallpaper rotation is minute-granular.** The code is `wallpaperRotationMinutes * 60_000L`, checked on a
once-a-minute tick, so **1 minute is the floor** — there is no seconds setting. More variety means more
pictures: drop 1920×1080 JPEGs into the `wallpapers/` folder and re-push.

Cost: launcher ~111 MB RSS (76 MB without wallpapers), free RAM ~58 MB. Normal for Android — cached memory is
reclaimed on demand. Zero crashes.

---

## 7. Undo, in pieces

**Debloat** — see §3.

**Theme only**:

```bash
TV_HOST=<tv ip> tools/theme.sh --reset
```

**Boot fix only** (back to the stock behaviour):

```bash
git revert --no-edit fec7831c
tools/docker-build.sh launcher assembleRelease
SKIP_BUILD=1 TV_HOST=<tv ip> HOME_KEY_SERVICE=1 STOCK_LAUNCHER=none launcher/build-and-install.sh
```

**Stock launcher as Home again**:

```bash
adb -s <tv ip>:5555 shell \
  'cmd package set-home-activity --user 0 com.cvte.tv.launcher.mars/.ui.home.HomeActivity'
```

**App compilation back to normal**:

```bash
adb -s <tv ip>:5555 shell 'for p in com.google.android.youtube.tv in.startv.hotstar org.videolan.vlc com.cvte.tv.media com.android.vending; do cmd package compile -m verify -f $p; done'
```

---

## 8. Performance work

Five apps AOT-compiled (`-m speed -f`) because they were running interpreted, which is most of the "apps take
ages to open" feeling on a 1 GB box:

`com.google.android.youtube.tv`, `in.startv.hotstar`, `org.videolan.vlc`, `com.cvte.tv.media`
(the USB media browser), `com.android.vending` (Play Store).

Compiling Hotstar and Play Store each takes several minutes on this CPU; `dex2oat32` in `ps` is normal.

### RAM: do not worry about the number

`free -m` showing ~58 MB free is **normal and healthy**. Android keeps apps cached in RAM on purpose. The real
speed signal is how fast an app opens.

### Process state at the time

- `com.gathin.tvhome` ~111 MB RSS, the only Home process running
- Stock launcher `com.cvte.tv.launcher.mars` **enabled but never started** — nothing to gain by disabling it
- `adbd` ran as `uid 2000` (shell), non-root

---

## 9. ADB

ADB was turned off in the CVTE factory menu (**DEBUG → ADB ENABLE → OFF**) on 2026-11-13 after the theme work.

To confirm it is really closed, run this from an ordinary terminal on the same network, with the TV **on**:

```bash
tools/adb-closed.py <tv ip>          # only "closed" counts
```

A timeout proves nothing — only a refused connection does. The TV may be off or asleep, or the machine may be
on another VLAN. If 5555 still answers, USB debugging is still on; turn that off as well. Port 5555 is
plaintext.

---

## 10. Gotchas learned the hard way

- **Boot timeline must come from `logcat -v monotonic`.** Plain wall-clock filters are unreliable: the RTC is
  wrong early in boot, and `logcat` keeps persisted entries from earlier boots (they read as `-48316309`).
- **`adb unroot` matters.** Before it `id -u` said 0; after, 2000 (shell). Both can `pm disable-user`.
- **After a reinstall, re-check HOME.** The chooser returns and the "Always" choice is gone (§5).
- **A screenshot from Live TV, HDMI or some streaming apps can be empty.** That is the TV's secure surface,
  not damage.
- **An injected key is not proof** for a remote button handled by an accessibility helper: press the real
  button. `am force-stop com.gathin.tvhome` switches those helpers off.
- **`tools/tv.py` needs `TV_HOST`.** A bare `tools/tv.py --screenshot` exits 2 with the usage message.
- **This TV's remote is infrared with no number keys**; a phone remote (ZaZa) and a wired mouse were used.

---

## 11. Useful one-liners

```bash
# what is on screen
adb -s <tv ip>:5555 shell 'dumpsys activity activities | grep -m1 mFocusedApp'

# screenshot
TV_HOST=<tv ip> tools/tv.py --screenshot shots/now.png

# what the TV is
TV_HOST=<tv ip> tools/tv.py --probe

# is the Home key helper bound
adb -s <tv ip>:5555 shell 'dumpsys accessibility | grep -i gathin'
```

---

## 12. Open items

- [ ] Confirm ADB is closed from a machine on the same network, with the TV on (§9).
- [ ] Upstream PR #1448 was still conflicting and waiting on the maintainer as of 2026-11-13.
