## Voraussetzungen

- Raspberry Pi 5 mit Ubuntu (aktuell laufend)
- NVMe-SSD über M.2 HAT oder USB-zu-NVMe-Adapter angeschlossen
- Root-Berechtigung oder sudo-Zugriff
- Internetverbindung zum Herunterladen der Images

# Anleitung: NVMe direkt flashen auf Raspberry Pi 5 mit Ubuntu 24.04 Server

## Konfigurationswerte für diese Anleitung

Diese Anleitung verwendet folgende vordefinierte Werte:

```bash
USERNAME="pi"
PASSWORD_CLEAR="070576"
HOSTNAME="zolo-pi-1"
IPADDR="192.168.1.101/24"
GATEWAY="192.168.1.1"
DNS="192.168.1.1"
TIMEZONE="Europe/Zurich"
LOCALE="de_CH.UTF-8"
KEYBOARD_LAYOUT="ch"
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJnFXLthUD6WaZWdHB8SsrqpIE0DP1KZQ6hIcpmD4EuE zoloadm@zombie.local"
NVMe_DEVICE="/dev/sda" # Anpassen!
```



- Raspberry Pi 5 mit Ubuntu (aktuell laufend)
- NVMe-SSD über M.2 HAT oder USB-zu-NVMe-Adapter angeschlossen
- Root-Berechtigung oder sudo-Zugriff
- Internetverbindung zum Herunterladen der Images

## Schritt 1: System vorbereiten

```bash
# System aktualisieren
sudo apt update && sudo apt upgrade -y

# Notwendige Tools installieren
sudo apt install -y wget curl unzip pv gdisk parted cloud-init
```

## Schritt 2: Ubuntu 24.04 Server Image herunterladen

```bash
# Verzeichnis für Download erstellen
mkdir -p ~/ubuntu-flash && cd ~/ubuntu-flash

# Ubuntu 24.04 Server für Raspberry Pi herunterladen
wget https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz

# Image entpacken
xz -d ubuntu-24.04.3-preinstalled-server-arm64+raspi.img.xz
```

## Schritt 3: NVMe-Laufwerk identifizieren

```bash
# Alle Speichergeräte anzeigen
lsblk

# Detaillierte Informationen über NVMe
sudo fdisk -l | grep nvme
```

**⚠️ WICHTIG:** Notiere dir den korrekten Pfad deines NVMe-Laufwerks (z.B. `/dev/nvme0n1`). Ein Fehler hier kann zu Datenverlust führen!

## Schritt 4: NVMe-Laufwerk flashen

```bash
# WICHTIG: Ersetze /dev/nvmeXnY mit deinem tatsächlichen NVMe-Pfad!
NVMe_DEVICE="/dev/sda"  # Anpassen!

# Laufwerk unmounten (falls gemountet)
sudo umount ${NVMe_DEVICE}* 2>/dev/null || true

# Image auf NVMe flashen (mit Fortschrittsanzeige)
sudo dd if=ubuntu-24.04.3-preinstalled-server-arm64+raspi.img of=$NVMe_DEVICE bs=4M status=progress

# Sicherstellen, dass alle Daten geschrieben wurden
sync
```

## Schritt 5: Partitionen erweitern (optional aber empfohlen)

```bash
# Partitionstabelle neu einlesen
sudo partprobe $NVMe_DEVICE

# Root-Partition erweitern um gesamten verfügbaren Platz zu nutzen
sudo parted $NVMe_DEVICE resizepart 2 20% # z.B. nur 80 % nutzen

# Dateisystem erweitern
sudo e2fsck -f ${NVMe_DEVICE}2
sudo resize2fs ${NVMe_DEVICE}2

# Zweite (unverwendete) Partition erstellen
sudo parted $NVMe_DEVICE mkpart primary ext4 20% 100%
lsblk $NVMe_DEVICE
# Optional formatieren
sudo mkfs.ext4 ${NVMe_DEVICE}3
```

## Schritt 6: Cloud-Init konfigurieren

```bash
# Boot-Partition mounten
sudo mkdir -p /mnt/nvme-boot
sudo mount ${NVMe_DEVICE}1 /mnt/nvme-boot

# Root-Partition mounten
sudo mkdir -p /mnt/nvme-root  
sudo mount ${NVMe_DEVICE}2 /mnt/nvme-root
```

### User-Data erstellen

```bash
# Cloud-Init User-Data Datei erstellen
sudo tee /mnt/nvme-boot/user-data <<EOF
#cloud-config

locale: ${LOCALE}
keyboard:
layout: ${KEYBOARD_LAYOUT}
timezone: ${TIMEZONE}
hostname: ${HOSTNAME}

users:
  - name: ${USERNAME}
    plain_text_passwd: "${PASSWORD_CLEAR}"
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: [adm, audio, cdrom, dialout, dip, floppy, lxd, netdev, plugdev, sudo, video]
    shell: /bin/bash
    ssh_authorized_keys:
      - ${PUBKEY}
    lock_passwd: false

ssh_pwauth: true
disable_root: true

packages:
  - vim
  - htop
  - git
  - curl
  - wget
  - unattended-upgrades

package_update: true
package_upgrade: true

runcmd:
  - systemctl enable ssh
  - ufw --force enable
  - ufw allow ssh

power_state:
  mode: reboot
  delay: 1
  condition: True

EOF
```

### Network-Config erstellen

```bash
# Netzwerk-Konfiguration für statische IP
sudo tee /mnt/nvme-boot/network-config <<EOF
version: 2
ethernets:
  eth0:
    addresses:
      - ${IPADDR}
    routes:
      - to: default
        via: ${GATEWAY}
    nameservers:
      addresses:
        - ${DNS}
    optional: false
EOF

```

## Schritt 7: Abschluss und Boot-Reihenfolge anpassen

```bash
# Partitionen unmounten
sudo umount /mnt/nvme-boot
sudo umount /mnt/nvme-root

# Mount-Punkte entfernen
sudo rmdir /mnt/nvme-boot /mnt/nvme-root

# Boot-Reihenfolge in der Raspberry Pi Konfiguration anpassen
# (Das machst du nach dem Neustart)
echo "BOOT_ORDER=0xf461" | sudo tee -a /boot/firmware/config.txt
```

## Schritt 8: Von NVMe booten

1. **Neustart des Raspberry Pi:**
   ```bash
   sudo reboot
   ```

2. **Boot-Reihenfolge prüfen/ändern:**
   - Nach dem Reboot prüfen ob von NVMe gebootet wurde: `lsblk`
   - Falls nötig, Boot-Reihenfolge im Bootloader anpassen

3. **Cloud-Init Status prüfen:**
   ```bash
   # Status von Cloud-Init prüfen
   sudo cloud-init status
   
   # Logs ansehen
   sudo cloud-init logs
   ```

## Wichtige Hinweise

### Sicherheit
- **BACKUP:** Erstelle immer ein Backup wichtiger Daten vor dem Flashen
- **Gerät prüfen:** Stelle sicher, dass du das richtige Gerät flashst
- **SSH-Keys:** Konfiguriere SSH-Keys vor dem ersten Boot

### Troubleshooting

**Problem:** NVMe wird nicht erkannt
```bash
# NVMe-Module laden
sudo modprobe nvme
sudo modprobe nvme_core
```

**Problem:** Cloud-Init funktioniert nicht
```bash
# Cloud-Init zurücksetzen und erneut ausführen
sudo cloud-init clean
sudo cloud-init init
```

**Problem:** Boot von NVMe funktioniert nicht
- EEPROM-Update durchführen: `sudo rpi-eeprom-update -a`
- Boot-Reihenfolge prüfen: `vcgencmd bootloader_config`

## Zusätzliche Optimierungen

### Performance-Tuning für NVMe
```bash
# I/O-Scheduler für NVMe optimieren
echo 'none' | sudo tee /sys/block/nvme0n1/queue/scheduler

# Permanent machen
echo 'KERNEL=="nvme*", ATTR{queue/scheduler}="none"' | sudo tee /etc/udev/rules.d/99-nvme-scheduler.rules
```

### Monitoring
```bash
# NVMe-Status überwachen
sudo apt install nvme-cli
sudo nvme smart-log /dev/nvme0n1
```

Deine NVMe-SSD sollte jetzt mit Ubuntu 24.04 Server und Cloud-Init geflasht sein und direkt bootbereit!