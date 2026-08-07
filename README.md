# prochot — BD PROCHOT CPU lock fix for MacBooks without a battery

**The problem:** your MacBook's CPU is stuck at minimum frequency (800 MHz) and
nothing you do with governors, `cpupower`, or kernel parameters helps — even
under full load with cool temperatures.

**The cause:** Apple's SMC firmware asserts **BD PROCHOT** (bit 0 of MSR
`0x1FC`) when it doesn't detect a healthy battery. This hard-locks the CPU at
minimum frequency. It happens on Linux **and macOS**, on every boot, and no
cpufreq setting can override it — the firmware wins.

**The fix:** clear bit 0 of MSR `0x1FC` on all cores and cap CPU/GPU
frequencies so the charger (now the *only* power source) isn't overloaded.
`prochot` does this in one command and installs systemd units that re-apply
it at every boot and after suspend/resume.

Verified on: **MacBookPro11,1 (i5-4258U, Iris 5100), Arch Linux, kernel 7.x**.
The CLI works on any Linux distro (pacman/apt/dnf/zypper/apk detected).

---

## Quickstart

```bash
git clone https://github.com/Diplovee/bd-prochot-fix.git
cd bd-prochot-fix
./prochot diagnose        # shows what's wrong (no root needed)
sudo ./prochot install    # installs deps + systemd units + applies the fix
prochot status            # verify caps, MSR bit, temps
prochot verify --load     # measures the REAL core clock under load
```

That's it. After `install`, the fix is permanent: applied at every boot and
after suspend/resume.

## CLI reference

| Command | What it does | Root? |
|---|---|---|
| `prochot diagnose` | Checks battery presence, MSR bit, frequencies, temps, governor and explains the verdict | no |
| `prochot install [--benchmark]` | Installs `msr-tools` + `cpupower` (+ `glmark2`), copies systemd units, enables them, applies the fix | yes |
| `prochot apply` | Clears BD PROCHOT + caps CPU/GPU **right now** (used by the services) | yes |
| `prochot status` | Caps, current frequencies, GPU clock, temps, battery, MSR bit, service state | no* |
| `prochot verify [--load]` | Compiles a tiny RDTSC test and measures the **real** core clock per CPU (catches fake readings); `--load` also spins all cores and samples freqs+temp | no |
| `prochot benchmark [full]` | glmark2 GPU FPS test (quick 2-scene or full suite), results → `/tmp/glmark2.txt` | no |
| `prochot uninstall` | Removes services and CLI | yes |

*MSR readout in `status` needs root.

## Configuration

`/etc/prochot.conf` (created on install):

```ini
CAP=1200000      # kHz - CPU max frequency
GPU_CAP=800      # MHz - GPU max frequency (Intel i915)
```

Edit, then `sudo prochot apply` (no reboot needed).

---

## ⚠️ Power warning — read before raising caps

Without a battery, the charger is the **only** power source. Clearing BD
PROCHOT lets CPU+GPU boost, and combined load can exceed what the charger
supplies → **sudden shutdown with zero warning** (power cut, not heat).

Evidence from this machine (MacBookPro11,1):
- Shutdown occurred at a **cool 72 °C package** during a GPU benchmark at
  CPU 1.5 GHz + GPU turbo 1100 MHz — a power event, not thermal.
- Community data on the same model (AskUbuntu #1424679) stabilizes at a
  **1.2 GHz CPU cap**.
- The default config (CPU 1.2 GHz / GPU 800 MHz) survived the full glmark2
  suite: score 274, peak 98 °C, **no throttling, no shutdown**.

So: 1.2 GHz CPU is the documented sweet spot for battery-less MacBooks.
Raise caps only stepwise (1.3 → 1.4 → 1.5) and re-run the full benchmark
each step. **Shutdown = power ceiling reached → go back down.** Heat is
rarely the binding constraint on this platform.

Also verify your charger: MacBook Pro 13" late-2013 requires the **60 W
MagSafe 2** adapter. A weaker/third-party unit explains both a never-charging
battery and early shutdowns.

## Thermal notes

- The fan is a small blower; ~6200 RPM is its hard max. Pegged fan + high
  temps = cooling saturated, not malfunction.
- Peak ~98 °C under sustained CPU+GPU load is within spec (Tjmax 100 °C,
  chip self-throttles there) but shortens component life. On a 10+ year old
  machine, **replacing the dried thermal paste and cleaning the fan/fins
  typically drops 15–25 °C**. This does *not* raise the power ceiling — it
  adds thermal headroom and comfort.
- **Never use toothpaste as thermal paste.** It dries into an insulator
  within days, is abrasive (permanently scratches the die/heatsink), and is
  corrosive to copper. Real paste is $5–8.

## Reference benchmark (this repo's test machine)

glmark2 full suite, 1280x800, CPU 1.2 GHz / GPU 800 MHz (Mesa 26.1.6,
Iris 5100 GT3): **score 274**. Scene highlights: texture-mipmap 686 FPS,
shading-gouraud 554, desktop-shadow 384, jellyfish 158, refract 79,
terrain 66.

Gaming verdict: everything 2D/indie at 60+ FPS; esports and pre-2016 3D at
1280x800 low/medium 30–60 FPS; no for modern AAA. Vulkan is experimental on
Haswell — prefer native/OpenGL games over Proton/DXVK.

---

## WiFi: BCM4360 (14e4:43a0) — `wl` driver is the ONLY option

Hardware: Broadcom BCM4360 802.11ac (Apple subsystem). Symptom: downloads
slow down then the link cuts off entirely, especially on 2.4 GHz.

**Finding:** on kernel 7.x, the open-source `brcmfmac` driver does **not**
claim this chip — its PCI ID table has no `14e4:43a0` entry (only `bcma` and
`wl` match). We verified via `grep 43a0 /lib/modules/$(uname -r)/modules.alias`
before attempting a switch; the naive attempt loaded `brcmfmac` with no
binding and left the machine with no WiFi until rolled back. **Lesson: always
check `modules.alias` for the PCI ID before switching drivers, and verify the
driver actually bound to the device** (`/sys/bus/pci/devices/0000:03:00.0/driver`),
not just that the module is loaded.

Working mitigations (with `wl`):

1. **Use 5 GHz** — the single biggest fix. `wl` is dramatically more stable
   on 5 GHz than on congested 2.4 GHz; the card is 802.11ac capable.
2. **Lock to your access point** to stop roaming/hunting:
   `nmcli connection modify <ssid> 802-11-wireless.bssid <AP-MAC>`
3. **Power save off** (already off by default in this setup):
   `iw dev wlan0 set power_save off`

`extras/wifi-fix.fish` — checks real chip support, switches drivers only when
supported, and auto-rolls back if the new driver doesn't bind. On this
hardware it correctly reports "wl is the only driver" and restores it.

## Bluetooth: un-blacklisting + manager

Original state: Bluetooth was disabled to stop WiFi interference —
`/etc/modprobe.d/blacklist-bluetooth.conf` blacklisted `btusb`/`bluetooth`,
the service was masked, and `bluez` was not installed.

Restore steps (automated in `extras/bt-restore.fish`):

1. Remove the module blacklist, `modprobe btusb`
2. `pacman -S bluez` (provides `bluetooth.service` + `bluetoothctl`)
3. `systemctl unmask bluetooth && systemctl enable --now bluetooth`
4. `rfkill unblock bluetooth`

Manager + waybar:

- Install `blueman` (GTK manager, handles pairing/PINs); `on-click` on the
  waybar Bluetooth icon launches `blueman-manager`
- waybar module (added to `modules-right` in `~/.config/waybar/config.jsonc`):
  `` on / `` connected / `󰂲` off, tooltip with controller info
- Add `#bluetooth` to the shared module style group in `style.css`
- The interference that motivated disabling BT is 2.4 GHz coexistence —
  solved by putting WiFi on 5 GHz, keeping both radios

## FAQ

**Does this fix the root cause?** No — it's a workaround. The SMC still
asserts BD PROCHOT at every boot; the systemd service keeps clearing it.
The only real cure is a battery the SMC recognizes (removes the lock AND
buffers power spikes).

**Why does my other OS (macOS) also run slow?** Same firmware behavior —
the SMC asserts BD PROCHOT regardless of OS.

**Is my CPU really at 800 MHz?** Run `prochot verify` — it measures the real
clock with an RDTSC dependency chain, immune to sysfs misreporting.

**It worked for years, now it's slow?** Battery died/disconnected → SMC
started asserting BD PROCHOT. Check `/sys/class/power_supply/` for batteries.

## License

MIT — see [LICENSE](LICENSE). Contributions welcome.
