#!/usr/bin/env fish
# Re-enable Bluetooth (it was blacklisted to stop WiFi interference).
# The proper fix for the interference: put WiFi on 5 GHz - no need to
# sacrifice Bluetooth. Usage: fish ~/wifi-fix/bt-restore.fish

set -l BLK /etc/modprobe.d/blacklist-bluetooth.conf

if not test (id -u) -eq 0
    exec sudo fish (status filename)
end

echo "==> 1/4 removing bluetooth module blacklist"
if test -f $BLK
    cp $BLK $BLK.bak
    rm $BLK
    echo "    removed $BLK (backup saved: $BLK.bak)"
else
    echo "    no blacklist file present"
end

echo "==> 2/4 loading btusb"
modprobe btusb
sleep 2
lsmod | grep -E "^btusb|^bluetooth" | head -3

echo "==> 3/4 unmasking + starting bluetooth service"
systemctl unmask bluetooth 2>/dev/null; or true
systemctl enable --now bluetooth
sleep 2

echo "==> 4/4 verification"
rfkill unblock bluetooth 2>/dev/null; or true
printf 'service: %s\n' (systemctl is-active bluetooth)
bluetoothctl list 2>/dev/null | head -2
echo
echo "Done. If no controller shows, reboot - the modules now load at boot."
echo "TIP: keep WiFi on 5 GHz to avoid 2.4 GHz coexistence issues with BT."
