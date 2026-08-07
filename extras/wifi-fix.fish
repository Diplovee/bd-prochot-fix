#!/usr/bin/env fish
# WiFi driver manager for the Apple BCM4360 (14e4:43a0) on MacBooks.
# Determines whether brcmfmac actually supports this chip; if not (the case
# on kernel 7.x), safely restores the proprietary wl driver.
# Usage: fish ~/wifi-fix/wifi-fix.fish

set -l BWL /etc/modprobe.d/broadcom-wl.conf
set -l BACKUP $BWL.bak
set -l OVERRIDE /etc/modprobe.d/brcmfmac-over-wl.conf
set -l DEVICE "0000:03:00.0"

if not test (id -u) -eq 0
    exec sudo fish (status filename)
end

# --- does brcmfmac claim this PCI id at all? ---
set -l BRCM_MATCH (grep -i "brcmfmac" /lib/modules/(uname -r)/modules.alias | grep -ci "43a0")
if test "$BRCM_MATCH" -eq 0
    echo "❌ brcmfmac does NOT support 14e4:43a0 on this kernel - wl is the only driver."
    echo "==> Restoring wl..."
    rm -f $OVERRIDE
    if test -f $BACKUP; cp $BACKUP $BWL; end
    modprobe -r brcmfmac 2>/dev/null; or true
    modprobe wl
    sleep 3
    echo
    if lsmod | grep -q "^wl"
        echo "✅ wl driver loaded. Interfaces:"
        iw dev 2>/dev/null
        echo "NetworkManager should auto-reconnect shortly."
        echo "TIP: connect to a 5 GHz SSID if your router has one - the wl driver is"
        echo "far more stable on 5 GHz than on congested 2.4 GHz."
    else
        echo "❌ wl failed to load - reboot the machine."
    end
    exit 0
end

# --- brcmfmac supports it: do the switch, with a REAL binding check ---
echo "brcmfmac supports this chip - switching drivers (WiFi will blip)..."
if not test -f $BACKUP; cp $BWL $BACKUP; end
grep -v "^blacklist brcmfmac" $BWL > /tmp/bwl.conf
cp /tmp/bwl.conf $BWL
echo "blacklist wl" > $OVERRIDE
modprobe -r wl 2>/dev/null; or true
modprobe brcmfmac
sleep 4
if test -e /sys/bus/pci/devices/$DEVICE/driver; and test (basename (readlink /sys/bus/pci/devices/$DEVICE/driver)) = brcmfmac
    echo "✅ brcmfmac bound to the device. Interfaces:"
    iw dev 2>/dev/null
else
    echo "❌ brcmfmac did NOT bind - rolling back to wl"
    rm -f $OVERRIDE
    cp $BACKUP $BWL
    modprobe -r brcmfmac 2>/dev/null; or true
    modprobe wl
    sleep 3
    iw dev 2>/dev/null
end
