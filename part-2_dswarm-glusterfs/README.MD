# ZoLo Hybrid Dual-Tier Storage Guide
*GlusterFS + NFS Performance auf Raspberry Pi 5 Cluster mit NVMe*

---

## Hardware Übersicht

### ZoLo Cluster Setup

```yaml
Compute & Primary Storage (All 4 Nodes):
  - 4x Raspberry Pi 5 (8GB RAM)
  - 4x Waveshare PCIe M.2 NVMe Base (PoE + Fan)
  - 4x Raspberry Pi NVMe SSD SC1440 (512GB, 2242)
  - 1x TP-Link TL-SG105PE (1GBit PoE+ Switch, 65W)

Network Configuration:
  - Network: 192.168.1.0/24
  - zolo-pi-1: 192.168.1.101
  - zolo-pi-2: 192.168.1.102
  - zolo-pi-3: 192.168.1.103
  - zolo-pi-4: 192.168.1.104
  
  VIP (keepalived):
  - Storage VIP: 192.168.1.121
```

---

## Storage Architektur

### NVMe Storage Layout

```
Jeder Node (zolo-pi-1 bis zolo-pi-4):
├─ nvme0n1p3 (381.6G)
│  └─ gluster-vg/data (LVM)
│     └─ /data/gluster/swarm (ext4)
│        └─ brick/ (GlusterFS Brick)
└─ Total: ~381.5G pro Node
```

### GlusterFS Volume

```
gv0-swarm (Replica 2):
┌────────────────────────────────────────────────────┐
│ Volume: gv0-swarm                                  │
│ Type: Distributed Replicate                       │
│ Replica Count: 2                                   │
│                                                    │
│ ┌─────────────┐        ┌─────────────┐           │
│ │ zolo-pi-1   │◄──────►│ zolo-pi-2   │ Replica 1 │
│ │ NVMe 381GB  │        │ NVMe 381GB  │           │
│ └─────────────┘        └─────────────┘           │
│                                                    │
│ ┌─────────────┐        ┌─────────────┐           │
│ │ zolo-pi-3   │◄──────►│ zolo-pi-4   │ Replica 2 │
│ │ NVMe 381GB  │        │ NVMe 381GB  │           │
│ └─────────────┘        └─────────────┘           │
│                                                    │
│ Capacity: ~760GB usable (mit Replica 2)           │
│ Performance: 100-110 MB/s @ 1GBit                 │
└────────────────────────────────────────────────────┘
```

---

## Installation & Setup

### Phase 1: Storage Setup (AUF ALLEN 4 NODES)

```bash
#!/bin/bash
# 01-setup-storage.sh
# Auf ALLEN 4 Nodes ausführen

set -e

echo "=== GlusterFS Storage Setup auf nvme0n1p3 (381.6G) ==="
echo "Node: $(hostname)"
echo ""

# 1. GlusterFS + NFS Server installieren
echo "1. Installiere GlusterFS und NFS Server..."
sudo apt update
sudo apt install -y glusterfs-server nfs-kernel-server

# 2. Services aktivieren
echo "2. Aktiviere Services..."
sudo systemctl enable glusterd nfs-kernel-server
sudo systemctl start glusterd nfs-kernel-server

# 3. Firewall Regeln
echo "3. Konfiguriere Firewall..."
sudo ufw allow 24007:24008/tcp  # GlusterFS daemon
sudo ufw allow 49152:49664/tcp  # GlusterFS bricks
sudo ufw allow 2049/tcp         # NFS
sudo ufw allow 111/tcp          # RPC portmapper

# 4. Partition prüfen
echo ""
echo "4. Aktuelle Partition:"
lsblk /dev/nvme0n1p3

# 5. LVM Setup für GlusterFS
echo ""
echo "5. Erstelle LVM auf nvme0n1p3..."
sudo pvcreate /dev/nvme0n1p3
sudo vgcreate gluster-vg /dev/nvme0n1p3

# Komplette Partition nutzen
echo "Erstelle Logical Volume mit gesamter Grösse..."
sudo lvcreate -n data -l 100%FREE gluster-vg

# 6. Filesystem erstellen
echo ""
echo "6. Erstelle ext4 Filesystem..."
sudo mkfs.ext4 /dev/gluster-vg/data

# 7. Mount-Point vorbereiten
echo "7. Erstelle Mount-Point..."
sudo mkdir -p /data/gluster/swarm

# 8. Mounten
echo "8. Mounte Filesystem..."
sudo mount /dev/gluster-vg/data /data/gluster/swarm

# 9. Permanent Mount in /etc/fstab
echo "9. Füge zu /etc/fstab hinzu..."
echo "/dev/gluster-vg/data /data/gluster/swarm ext4 defaults 0 0" | \
  sudo tee -a /etc/fstab

# 10. Brick-Verzeichnis erstellen
echo "10. Erstelle Brick-Verzeichnis..."
sudo mkdir -p /data/gluster/swarm/brick
sudo chown root:root /data/gluster/swarm/brick

# 11. Status anzeigen
echo ""
echo "=== Setup abgeschlossen ==="
echo ""
echo "LVM Status:"
sudo pvs
sudo vgs
sudo lvs
echo ""
echo "Mount Status:"
df -h /data/gluster/swarm
echo ""
echo "Brick Verzeichnis:"
ls -la /data/gluster/swarm/
echo ""
echo "Services:"
sudo systemctl status glusterd --no-pager | head -3
sudo systemctl status nfs-kernel-server --no-pager | head -3

echo ""
echo "✅ GlusterFS Storage bereit auf nvme0n1p3!"
echo ""
echo "Nächster Schritt:"
echo "- Dieses Script auf allen 4 Nodes ausführen"
echo "- Dann auf dem Master: 02-setup-cluster.sh ausführen"
echo ""
```

### Phase 2: Cluster Setup (NUR AUF MASTER - zolo-pi-1)

```bash
#!/bin/bash
# 02-setup-cluster.sh
# NUR auf zolo-pi-1 ausführen

set -e

echo "=== GlusterFS Cluster Setup (Master Node) ==="
echo ""
echo "⚠️  Nur auf dem Swarm Leader ausführen!"
echo "⚠️  Stelle sicher, dass 01-setup-storage.sh auf ALLEN Nodes läuft!"
echo ""

# Node IPs
NODE1="192.168.1.101"  # zolo-pi-1 (Master)
NODE2="192.168.1.102"  # zolo-pi-2
NODE3="192.168.1.103"  # zolo-pi-3
NODE4="192.168.1.104"  # zolo-pi-4

echo "1. Füge Peers zum GlusterFS Cluster hinzu..."
sudo gluster peer probe $NODE2
sudo gluster peer probe $NODE3
sudo gluster peer probe $NODE4

echo ""
echo "2. Prüfe Peer Status..."
sudo gluster peer status

echo ""
echo "3. Erstelle GlusterFS Volume (Replica 2)..."
echo "   - 4 Bricks auf 4 Nodes"
echo "   - Replica 2 = jedes File auf 2 Nodes"
echo "   - Redundanz bei Node-Ausfall"

sudo gluster volume create gv0-swarm \
    replica 2 \
    $NODE1:/data/gluster/swarm/brick \
    $NODE2:/data/gluster/swarm/brick \
    $NODE3:/data/gluster/swarm/brick \
    $NODE4:/data/gluster/swarm/brick \
    force

echo ""
echo "4. Starte Volume..."
sudo gluster volume start gv0-swarm

echo ""
echo "5. Performance Tuning..."
sudo gluster volume set gv0-swarm performance.cache-size 256MB
sudo gluster volume set gv0-swarm performance.write-behind-window-size 4MB
sudo gluster volume set gv0-swarm performance.io-thread-count 32
sudo gluster volume set gv0-swarm network.ping-timeout 10

echo ""
echo "6. Volume Info:"
sudo gluster volume info gv0-swarm

echo ""
echo "8. Volume Status:"
sudo gluster volume status gv0-swarm

echo ""
echo "✅ GlusterFS Cluster erstellt!"
echo ""
echo "Hinweis: Gluster NFS ist deprecated - wir nutzen Kernel NFS"
echo ""
echo "Nächster Schritt:"
echo "- Auf allen Nodes: 03-test-nfs.sh ausführen"
echo ""
```

### Phase 3: NFS Test (AUF ALLEN NODES)

```bash
#!/bin/bash
# 03-test-nfs.sh
# Auf allen Nodes ausführen

set -e

echo "=== NFS Mount Test ==="
echo "Node: $(hostname)"
echo ""

# Lokale IP ermitteln
LOCAL_IP=$(hostname -I | awk '{print $1}')

echo "1. Erstelle Test Mount-Point..."
sudo mkdir -p /mnt/swarm-storage

echo ""
echo "2. Mounte GlusterFS via NFS..."
echo "   Mount: $LOCAL_IP:/gv0-swarm -> /mnt/swarm-storage"

sudo mount -t nfs -o vers=3 $LOCAL_IP:/gv0-swarm /mnt/swarm-storage

echo ""
echo "3. Mount Status:"
df -h /mnt/swarm-storage

echo ""
echo "4. Test: Schreibe Datei..."
TEST_FILE="/mnt/swarm-storage/test-$(hostname).txt"
echo "Test von $(hostname) um $(date)" | sudo tee $TEST_FILE

echo ""
echo "5. Test: Lese alle Dateien..."
ls -lh /mnt/swarm-storage/

echo ""
echo "6. Unmount..."
sudo umount /mnt/swarm-storage

echo ""
echo "✅ NFS Mount Test erfolgreich!"
echo ""
echo "Nächster Schritt:"
echo "- Auf Master: 04-setup-docker.sh ausführen"
echo ""
```

### Phase 4: Docker Volume Setup (NUR AUF MASTER)

```bash
#!/bin/bash
# 04-setup-docker.sh
# NUR auf zolo-pi-1 ausführen

set -e

echo "=== Docker NFS Volume Setup (Master Node) ==="
echo ""

NODE1="192.168.1.101"

echo "1. Erstelle Docker Volume mit NFS Driver..."
docker volume create \
    --driver local \
    --opt type=nfs \
    --opt o=addr=192.168.1.121,vers=3,soft,timeo=180 \
    --opt device=:/gv0-swarm \
    swarm-storage

echo ""
echo "2. Volume Info:"
docker volume inspect swarm-storage

echo ""
echo "3. Deploy Test-Container..."
cat << 'EOF' > /tmp/test-stack.yml
version: '3.8'

services:
  test:
    image: nginx:alpine
    deploy:
      replicas: 2
      placement:
        max_replicas_per_node: 1
    volumes:
      - swarm-storage:/usr/share/nginx/html:rw
    ports:
      - "8080:80"

volumes:
  swarm-storage:
    external: true
EOF

docker stack deploy -c /tmp/test-stack.yml test-stack

echo ""
echo "4. Warte auf Container..."
sleep 10

echo ""
echo "5. Stack Status:"
docker stack ps test-stack

echo ""
echo "6. Test HTML schreiben..."
echo "<h1>GlusterFS Test - $(date)</h1>" | \
    docker exec $(docker ps -q -f name=test-stack_test | head -1) \
    tee /usr/share/nginx/html/index.html

echo ""
echo "✅ Docker Volume Setup abgeschlossen!"
echo ""
echo "Test URL: http://any-node-ip:8080"
echo ""
echo "Cleanup: docker stack rm test-stack"
echo ""
```

---

## High Availability mit keepalived

### VIP Architektur

```yaml
VIP Zuweisung:
  192.168.1.121 → NFS Storage (alle 4 Nodes)
  192.168.1.122 → Samba NAS (nur pi-3, pi-4)

Failover Prioritäten:
  NFS (VIP .121):
    pi-1: 100 (MASTER)
    pi-2: 90
    pi-3: 80
    pi-4: 70
  
  Samba (VIP .122):
    pi-3: 100 (MASTER)
    pi-4: 90
```

### keepalived Config - zolo-pi-1

```bash
# Nur NFS VIP - kein Samba
sudo tee /etc/keepalived/keepalived.conf << 'EOF'
global_defs {
    router_id ZOLO_PI1
    enable_script_security
    script_user root
}

vrrp_script check_nfs {
    script "/usr/bin/systemctl is-active nfs-kernel-server"
    interval 2
    timeout 3
    weight -20
    fall 2
    rise 2
}

vrrp_script check_gluster_mount {
    script "/bin/mountpoint -q /mnt/glusterfs-swarm"
    interval 3
    timeout 3
    weight -20
    fall 2
    rise 2
}

vrrp_instance VI_SWARM {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass zolo_swarm_2024
    }
    
    virtual_ipaddress {
        192.168.1.121/24 dev eth0
    }
    
    track_script {
        check_nfs
        check_gluster_mount
    }
}
EOF

sudo systemctl restart keepalived
```

### keepalived Config - zolo-pi-2

```bash
# Nur NFS VIP - kein Samba
sudo tee /etc/keepalived/keepalived.conf << 'EOF'
global_defs {
    router_id ZOLO_PI2
    enable_script_security
    script_user root
}

vrrp_script check_nfs {
    script "/usr/bin/systemctl is-active nfs-kernel-server"
    interval 2
    timeout 3
    weight -20
    fall 2
    rise 2
}

vrrp_script check_gluster_mount {
    script "/bin/mountpoint -q /mnt/glusterfs-swarm"
    interval 3
    timeout 3
    weight -20
    fall 2
    rise 2
}

vrrp_instance VI_SWARM {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 90
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass zolo_swarm_2024
    }
    
    virtual_ipaddress {
        192.168.1.121/24 dev eth0
    }
    
    track_script {
        check_nfs
        check_gluster_mount
    }
}
EOF

sudo systemctl restart keepalived
```

### keepalived Config - zolo-pi-3

```bash
# Beide VIPs - MASTER für Samba
sudo tee /etc/keepalived/keepalived.conf << 'EOF'
global_defs {
    router_id ZOLO_PI3
    enable_script_security
    script_user root
}

vrrp_script check_nfs {
    script "/usr/bin/systemctl is-active nfs-kernel-server"
    interval 2
    timeout 3
    weight -20
    fall 2
    rise 2
}

vrrp_script check_gluster_mount {
    script "/bin/mountpoint -q /mnt/glusterfs-swarm"
    interval 3
    timeout 3
    weight -20
    fall 2
    rise 2
}

vrrp_script check_samba {
    script "/usr/bin/systemctl is-active smbd"
    interval 5
    timeout 3
    weight -20
    fall 2
    rise 2
}

vrrp_instance VI_SWARM {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 80
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass zolo_swarm_2024
    }
    
    virtual_ipaddress {
        192.168.1.121/24 dev eth0
    }
    
    track_script {
        check_nfs
        check_gluster_mount
    }
}

vrrp_instance VI_SAMBA {
    state MASTER
    interface eth0
    virtual_router_id 52
    priority 100
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass zolo_samba_2024
    }
    
    virtual_ipaddress {
        192.168.1.122/24 dev eth0
    }
    
    track_script {
        check_samba
    }
}
EOF

sudo systemctl restart keepalived
```

### keepalived Config - zolo-pi-4

```bash
# Beide VIPs - BACKUP für Samba
sudo tee /etc/keepalived/keepalived.conf << 'EOF'
global_defs {
    router_id ZOLO_PI4
    enable_script_security
    script_user root
}

vrrp_script check_nfs {
    script "/usr/bin/systemctl is-active nfs-kernel-server"
    interval 2
    timeout 3
    weight -20
    fall 2
    rise 2
}

vrrp_script check_gluster_mount {
    script "/bin/mountpoint -q /mnt/glusterfs-swarm"
    interval 3
    timeout 3
    weight -20
    fall 2
    rise 2
}

vrrp_script check_samba {
    script "/usr/bin/systemctl is-active smbd"
    interval 5
    timeout 3
    weight -20
    fall 2
    rise 2
}

vrrp_instance VI_SWARM {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 70
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass zolo_swarm_2024
    }
    
    virtual_ipaddress {
        192.168.1.121/24 dev eth0
    }
    
    track_script {
        check_nfs
        check_gluster_mount
    }
}

vrrp_instance VI_SAMBA {
    state BACKUP
    interface eth0
    virtual_router_id 52
    priority 90
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass zolo_samba_2024
    }
    
    virtual_ipaddress {
        192.168.1.122/24 dev eth0
    }
    
    track_script {
        check_samba
    }
}
EOF

sudo systemctl restart keepalived
```

---

## Samba NAS Setup

### Samba Installation (nur pi-3, pi-4)

```bash
#!/bin/bash
# Nur auf zolo-pi-3 und zolo-pi-4 ausführen

# 1. Samba installieren
sudo apt update
sudo apt install -y samba smbclient

# 2. Linux User für Samba erstellen
sudo useradd -M -s /usr/sbin/nologin nasadm

# 3. Samba Config
sudo tee /etc/samba/smb.conf << 'EOF'
[global]
workgroup = WORKGROUP
server string = ZoLo NAS
security = user
map to guest = never
server min protocol = SMB2
log file = /var/log/samba/log.%m
max log size = 50

[storage]
comment = ZoLo Shared Storage
path = /mnt/storage-swarm
browseable = yes
writable = yes
valid users = nasadm
create mask = 0644
directory mask = 0755
force user = root
force group = root
EOF

# 4. Samba Passwort für nasadm setzen
sudo smbpasswd -a nasadm
# Passwort eingeben (z.B. dein sicheres Passwort)
# Passwort bestätigen

# 5. Services starten
sudo systemctl enable smbd nmbd
sudo systemctl restart smbd nmbd

# 6. Status prüfen
sudo systemctl status smbd --no-pager | head -5
sudo systemctl status nmbd --no-pager | head -5

# 7. Test
smbclient -L localhost -U nasadm%DEIN_PASSWORT

echo "✅ Samba NAS configured!"
```

**Wichtig:** Nutze **identisches Passwort** auf pi-3 und pi-4 für nahtlosen Failover!

### Windows Client Setup

```cmd
# In Windows CMD oder PowerShell
net use Z: \\192.168.1.122\storage /user:admin ZoloNAS2024!

# Oder im Windows Explorer:
# \\192.168.1.122 eingeben
# Share "storage" auswählen
# User: admin
# Passwort: ZoloNAS2024!
```

### Linux Client Setup

```bash
# Samba Client installieren
sudo apt install -y cifs-utils

# Mount
sudo mkdir -p /mnt/nas

sudo mount -t cifs //192.168.1.122/storage /mnt/nas \
  -o username=admin,password=ZoloNAS2024!,vers=3.0

# Persistent in /etc/fstab
echo "//192.168.1.122/storage /mnt/nas cifs username=admin,password=ZoloNAS2024!,vers=3.0,_netdev 0 0" | \
  sudo tee -a /etc/fstab
```

---

## High Availability mit keepalived

### keepalived Installation (AUF ALLEN NODES)

```bash
#!/bin/bash
# 05-install-keepalived.sh
# Auf allen 4 Nodes ausführen

sudo apt update
sudo apt install -y keepalived

# IP Forwarding aktivieren
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Service zunächst disabled
sudo systemctl stop keepalived
sudo systemctl disable keepalived

echo "✅ keepalived installed!"
```

### keepalived Config - MASTER (zolo-pi-1)

```bash
#!/bin/bash
# 06-config-keepalived-master.sh
# NUR auf zolo-pi-1

sudo tee /etc/keepalived/keepalived.conf << 'EOF'
global_defs {
    router_id ZOLO_SWARM_MASTER
    enable_script_security
    script_user root
}

vrrp_script check_nfs {
    script "/usr/bin/systemctl is-active nfs-kernel-server"
    interval 2
    timeout 3
    weight -20
    fall 2
    rise 2
}

vrrp_script check_gluster_mount {
    script "/bin/mountpoint -q /data/gluster/swarm"
    interval 3
    timeout 3
    weight -20
    fall 2
    rise 2
}

vrrp_instance VI_SWARM {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass zolo_swarm_2024
    }
    
    virtual_ipaddress {
        192.168.1.121/24 dev eth0
    }
    
    track_script {
        check_nfs
        check_gluster_mount
    }
}
EOF

echo "✅ MASTER config erstellt (zolo-pi-1)"
```

### keepalived Config - BACKUP (zolo-pi-2)

```bash
#!/bin/bash
# 06-config-keepalived-backup.sh
# NUR auf zolo-pi-2

sudo tee /etc/keepalived/keepalived.conf << 'EOF'
global_defs {
    router_id ZOLO_SWARM_BACKUP
    enable_script_security
    script_user root
}

vrrp_script check_nfs {
    script "/usr/bin/systemctl is-active nfs-kernel-server"
    interval 2
    timeout 3
    weight -20
    fall 2
    rise 2
}

vrrp_script check_gluster_mount {
    script "/bin/mountpoint -q /data/gluster/swarm"
    interval 3
    timeout 3
    weight -20
    fall 2
    rise 2
}

vrrp_instance VI_SWARM {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 90
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass zolo_swarm_2024
    }
    
    virtual_ipaddress {
        192.168.1.100/24 dev eth0
    }
    
    track_script {
        check_nfs
        check_gluster_mount
    }
}
EOF

echo "✅ BACKUP config erstellt (zolo-pi-2)"
```

### NFS Server Setup (AUF ALLEN NODES)

```bash
#!/bin/bash
# 07-setup-nfs-server.sh
# Auf allen 4 Nodes ausführen

# 1. Lokal mounten (FUSE - Server-side)
sudo mkdir -p /mnt/glusterfs-swarm

sudo mount -t glusterfs localhost:gv0-swarm /mnt/glusterfs-swarm

# Persistent mount
echo "localhost:gv0-swarm /mnt/glusterfs-swarm glusterfs defaults,_netdev 0 0" | \
  sudo tee -a /etc/fstab

# 2. NFS Exports konfigurieren
sudo tee -a /etc/exports << 'EOF'
/mnt/glusterfs-swarm 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=1)
EOF

sudo exportfs -ra

# 3. NFS Server Config
sudo tee /etc/nfs.conf << 'EOF'
[nfsd]
threads=32
udp=n
tcp=y
vers3=y
vers4=n
EOF

# 4. Kernel Tuning
sudo tee /etc/sysctl.d/99-nfs-server.conf << 'EOF'
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
sunrpc.tcp_slot_table_entries = 128
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr
EOF

sudo sysctl -p /etc/sysctl.d/99-nfs-server.conf

# 5. NFS restart
sudo systemctl restart nfs-kernel-server
sudo systemctl enable nfs-kernel-server

echo "✅ NFS Server ready!"
```

### NFS Client Setup mit VIP (AUF ALLEN NODES)

```bash
#!/bin/bash
# 08-setup-nfs-clients.sh
# Auf allen Nodes ausführen

# 1. NFS Client installieren
sudo apt install -y nfs-common

# 2. Mount Point
sudo mkdir -p /mnt/storage-swarm

# 3. Mount mit VIP
sudo mount -t nfs -o \
    vers=3,\
    rsize=1048576,\
    wsize=1048576,\
    hard,\
    timeo=600,\
    retrans=2,\
    actimeo=30 \
    192.168.1.21:/mnt/glusterfs-swarm /mnt/storage-swarm

# 4. Persistent in /etc/fstab
cat >> /etc/fstab << 'EOF'
192.168.1.21:/mnt/glusterfs-swarm /mnt/storage-swarm nfs vers=3,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,actimeo=30,_netdev 0 0
EOF

echo "✅ NFS Client mit VIP gemountet!"
```

### keepalived starten

```bash
#!/bin/bash
# 09-start-keepalived.sh
# Sequentiell auf allen Nodes

# 1. Start auf zolo-pi-1 (MASTER)
ssh pi@192.168.1.101 'sudo systemctl enable keepalived && sudo systemctl start keepalived'
sleep 5

# 2. Start auf zolo-pi-2 (BACKUP)
ssh pi@192.168.1.102 'sudo systemctl enable keepalived && sudo systemctl start keepalived'
sleep 5

# 3. Optional: Start auf zolo-pi-3, zolo-pi-4 (falls auch HA)
# ssh pi@192.168.1.103 'sudo systemctl enable keepalived && sudo systemctl start keepalived'
# ssh pi@192.168.1.104 'sudo systemctl enable keepalived && sudo systemctl start keepalived'

echo "✅ keepalived gestartet!"
```

---

## Docker Swarm Integration

### Docker Swarm Setup

```bash
#!/bin/bash
# 10-setup-docker-swarm.sh

# Docker installieren (auf allen 4 Nodes)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Swarm initialisieren (auf zolo-pi-1)
docker swarm init --advertise-addr 192.168.1.101

# Worker joinen (auf zolo-pi-2, zolo-pi-3, zolo-pi-4)
# Token vom Manager kopieren und ausführen:
# docker swarm join --token SWMTKN-1-xxx 192.168.1.101:2377

# Node Labels setzen
docker node update --label-add storage.tier=swarm zolo-pi-1
docker node update --label-add storage.tier=swarm zolo-pi-2
docker node update --label-add storage.tier=swarm zolo-pi-3
docker node update --label-add storage.tier=swarm zolo-pi-4

docker node update --label-add role=manager zolo-pi-1

echo "✅ Docker Swarm ready!"
```

### Docker Volume mit VIP

```bash
#!/bin/bash
# 11-create-docker-volume.sh
# Auf allen Nodes ausführen

docker volume create \
  --driver local \
  --opt type=nfs \
  --opt o=addr=192.168.1.121,vers=3,rw,rsize=1048576,wsize=1048576 \
  --opt device=:/mnt/glusterfs-swarm \
  gluster-swarm

docker volume inspect gluster-swarm
```

### Example Docker Stack

```yaml
# webapp-stack.yml
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
      update_config:
        parallelism: 1
        delay: 10s
    ports:
      - "80:80"
    volumes:
      - swarm-webapp:/usr/share/nginx/html:ro

volumes:
  swarm-webapp:
    driver: local
    driver_opts:
      type: nfs
      o: addr=192.168.1.121,vers=3,ro
      device: ":/mnt/glusterfs-swarm/webapp"
```

```bash
# Deploy
docker stack deploy -c webapp-stack.yml webapp

# Check which node is running
docker service ps webapp_nginx

# Update content
echo "<h1>Hello from GlusterFS HA!</h1>" | sudo tee /mnt/storage-swarm/webapp/index.html

# Failover test: Stop docker on active node
# Swarm will reschedule to another node automatically

# Remove
docker stack rm webapp
```

---

## Monitoring & Testing

### Health Check Script

```bash
#!/bin/bash
# health-check.sh

echo "=== ZoLo Storage Health Check ==="

# 1. GlusterFS Peer Status
echo "Peer Status:"
sudo gluster peer status

# 2. Volume Health
echo -e "\nVolume Status:"
sudo gluster volume status gv0-swarm

echo -e "\nVolume Heal Info:"
sudo gluster volume heal gv0-swarm info

# 3. Disk Space
echo -e "\nDisk Usage:"
df -h | grep -E 'gluster|swarm'

# 4. NFS Exports
echo -e "\nNFS Exports:"
sudo showmount -e localhost

# 5. VIP Status
echo -e "\nVIP Status:"
ip addr show eth0 | grep 192.168.1.100

# 6. keepalived Status
echo -e "\nkeepalived Status:"
sudo systemctl status keepalived --no-pager | head -5

echo -e "\n✅ Health check complete!"
```

### Performance Test

```bash
#!/bin/bash
# performance-test.sh

echo "=== GlusterFS Performance Test ==="

TEST_PATH="/mnt/storage-swarm"

# Sequential Write
echo "1. Sequential Write Test..."
sudo dd if=/dev/zero of=$TEST_PATH/test bs=1M count=1000 oflag=direct

# Sequential Read (Cold)
echo "2. Sequential Read Test (Cold)..."
sudo dd if=$TEST_PATH/test of=/dev/null bs=1M

# Clear cache
sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"

# Sequential Read (Warm)
echo "3. Sequential Read Test (Warm)..."
sudo dd if=$TEST_PATH/test of=/dev/null bs=1M

# Cleanup
sudo rm -f $TEST_PATH/test

echo "✅ Performance test complete!"
```

### Failover Test

```bash
#!/bin/bash
# failover-test.sh

echo "=== Testing NFS HA Failover ==="

# Terminal 1: Monitor
watch -n 1 'df -h | grep storage-swarm'

# Terminal 2 (auf zolo-pi-1): Simulate failure
sudo systemctl stop nfs-kernel-server

# Erwartung:
# - VIP wechselt zu zolo-pi-2 (~3s)
# - NFS Clients reconnecten automatisch
# - Kurze Pause, dann normal weiter

# Recovery
sudo systemctl start nfs-kernel-server
```

---

## Troubleshooting

### Problem: Volume nicht erreichbar

```bash
# Check GlusterFS Status
sudo gluster volume status gv0-swarm

# Check Mount
mountpoint /mnt/glusterfs-swarm

# Remount
sudo umount /mnt/glusterfs-swarm
sudo mount /mnt/glusterfs-swarm
```

### Problem: NFS stale file handle

```bash
# Force unmount
sudo umount -f /mnt/storage-swarm

# Remount
sudo mount /mnt/storage-swarm

# Check
df -h /mnt/storage-swarm
```

### Problem: Peer nicht erreichbar

```bash
# Check Peer Status
sudo gluster peer status

# Detach und neu proben
sudo gluster peer detach 192.168.1.102
sudo gluster peer probe 192.168.1.102
```

---

## Quick Reference

### Wichtige Pfade

```
/dev/gluster-vg/data                # LVM Volume
/data/gluster/swarm                 # Mount Point (LVM)
/data/gluster/swarm/brick           # Brick Directory
/mnt/glusterfs-swarm                # NFS Export Source (FUSE)
/mnt/storage-swarm                  # NFS Client Mount
192.168.1.121                       # VIP
```

### Wichtige Commands

```bash
# GlusterFS Volume
sudo gluster volume info gv0-swarm
sudo gluster volume status gv0-swarm
sudo gluster volume heal gv0-swarm info

# NFS
sudo showmount -e localhost
sudo exportfs -v
nfsstat -s

# keepalived
sudo systemctl status keepalived
ip addr show eth0 | grep 192.168.1.100

# Docker
docker volume ls
docker service ls
docker stack ps <stack-name>
```

---

## Deployment Checklist

```
Storage Setup:
□ LVM auf allen Nodes erstellt (gluster-vg/data)
□ Gemountet auf /data/gluster/swarm
□ Brick Verzeichnis erstellt
□ GlusterFS installiert und gestartet

Cluster Setup:
□ Peer probe erfolgreich (4 Nodes)
□ Volume gv0-swarm erstellt (Replica 2)
□ Volume gestartet
□ Performance Tuning angewendet

NFS Server:
□ GlusterFS lokal gemountet (/mnt/glusterfs-swarm)
□ NFS Exports konfiguriert
□ NFS Server neugestartet
□ Kernel Tuning angewendet

High Availability:
□ keepalived auf allen Nodes installiert
□ MASTER config (zolo-pi-1)
□ BACKUP config (zolo-pi-2)
□ VIP 192.168.1.100 konfiguriert
□ keepalived gestartet
□ Failover getestet

NFS Clients:
□ NFS mit VIP gemountet
□ Persistent in /etc/fstab
□ Mount Test erfolgreich

Docker Swarm:
□ Swarm initialisiert
□ Worker gejoint
□ Volume mit VIP erstellt
□ Test Stack deployed

Testing:
□ Performance Test (100+ MB/s)
□ Failover Test erfolgreich
□ Health Check OK
```

---

## Summary

### Was du jetzt hast

```
ZoLo GlusterFS Storage Cluster

Capacity: ~760GB usable (mit Replica 2)
Performance: 100-110 MB/s @ 1GBit
Nodes: 4x Raspberry Pi 5 mit NVMe
Redundancy: Replica 2 (jedes File auf 2 Nodes)
High Availability: keepalived mit VIP
Access: NFS v3 über VIP 192.168.1.100

Benefits:
✅ Automatisches Failover (3s)
✅ Keine Single Point of Failure
✅ Docker Swarm ready
✅ Kubernetes compatible
✅ Production ready
```