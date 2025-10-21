# ZoLo Image Converter - Production Ready

Automatischer Batch Image Converter für ZoLo Cluster mit Private Docker Registry.

---

## 🚀 Quick Start

### Erste Installation

```bash
# 1. Auf zolo-pi-1 (Manager Node)
cd /mnt/glusterfs-swarm/apps/image-converter

# 2. Deploy alles (Labels, Directories, Build, Push, Deploy)
./deploy-image-converter-complete.sh

# 3. Status prüfen
docker service ps imageconv_image-converter
docker service logs -f imageconv_image-converter
```

---

## 📂 File Locations

```
GlusterFS (/mnt/glusterfs-swarm/):
├── apps/image-converter/
│   ├── image-converter-stack.yml          ← Stack Config
│   └── deploy-image-converter-complete.sh ← Deploy Script
│
├── repo/image-converter/
│   ├── Dockerfile                         ← Image Build
│   └── image-converter.py                 ← Python Script
│
└── logs/image-converter/
    └── image-converter.log                ← Runtime Logs

USB NAS (/mnt/usb-nas-master/data/luggie/BACKUP/):
├── photos/                                ← Original Photos (Source)
└── photos-resized/                        ← Resized Photos (Destination)

Registry:
└── localhost:5000/image-converter:latest  ← Docker Image
```

---

## ⚠️ Important: Samba MASTER Node Dependency

**Der Image Converter MUSS auf dem Samba MASTER Node laufen!**

**Grund:**
- USB NAS ist lokal pro Node (nicht shared)
- rsync repliziert nur vom Node wo Samba VIP aktiv ist
- Resized Photos müssen dort liegen wo rsync läuft

**Bei Samba Failover (pi-3 → pi-4):**

```bash
# 1. Check wo Samba VIP aktiv ist
ip addr show | grep 192.168.1.122

# 2. Update Image Converter placement
nano /mnt/glusterfs-swarm/apps/image-converter/image-converter-stack.yml

# Change constraint to:
# - node.hostname == zolo-pi-4  (statt pi-3)

# 3. Redeploy
docker stack deploy -c image-converter-stack.yml imageconv
```

**Aktuell:** Fixiert auf `zolo-pi-3` (Samba MASTER)

---

## 🔄 Update Workflow

### Code ändern und neu deployen:

```bash
# 1. Edit Python Script
nano /mnt/glusterfs-swarm/repo/image-converter/image-converter.py

# 2. Rebuild & Push
cd /mnt/glusterfs-swarm/repo/image-converter
docker build -t localhost:5000/image-converter:latest .
docker push localhost:5000/image-converter:latest

# 3. Update Service (pullt automatisch neues Image)
docker service update --image localhost:5000/image-converter:latest imageconv_image-converter

# 4. Check
docker service ps imageconv_image-converter
```

### Settings ändern:

```bash
# 1. Edit Stack File
nano /mnt/glusterfs-swarm/apps/image-converter/image-converter-stack.yml

# 2. Redeploy
cd /mnt/glusterfs-swarm/apps/image-converter
docker stack deploy -c image-converter-stack.yml imageconv

# 3. Check
docker service ps imageconv_image-converter
```

---

## 📊 Monitoring

```bash
# Live Logs
docker service logs -f imageconv_image-converter

# Service Status
docker service ps imageconv_image-converter

# Wo läuft der Container?
docker service ps imageconv_image-converter --format "{{.Node}}"

# Resource Usage
docker stats $(docker ps -q -f name=imageconv)

# Log File direkt
tail -f /mnt/glusterfs-swarm/logs/image-converter/image-converter.log
```

---

## 🎯 Configuration

### Environment Variables (im Stack File):

```yaml
environment:
  MAX_WIDTH: "1920"      # Max width in pixels
  MAX_HEIGHT: "1080"     # Max height in pixels
  QUALITY: "85"          # JPEG quality (1-100)
  FORMATS: jpg,jpeg,png,webp
  LOG_LEVEL: INFO        # DEBUG, INFO, WARNING, ERROR
```

### Schedule (im Dockerfile):

```dockerfile
# Default: Daily at 2 AM
RUN echo "0 2 * * * /usr/local/bin/python3 /app/image-converter.py >> /var/log/cron.log 2>&1"
```

---

## 🔧 Troubleshooting

### Service startet nicht

```bash
# Detaillierter Error
docker service ps imageconv_image-converter --no-trunc

# Check Mounts auf Node
NODE=$(docker service ps imageconv_image-converter --format "{{.Node}}" | head -1)
ssh pi@$NODE "ls -la /mnt/usb-nas-master/data/luggie/BACKUP/"
ssh pi@$NODE "ls -la /mnt/glusterfs-swarm/logs/image-converter/"
```

### Image nicht gefunden

```bash
# Check Registry
curl http://localhost:5000/v2/_catalog

# Rebuild & Push
cd /mnt/glusterfs-swarm/repo/image-converter
docker build -t localhost:5000/image-converter:latest .
docker push localhost:5000/image-converter:latest
docker service update --force imageconv_image-converter
```

### Keine Photos werden verarbeitet

```bash
# Check Source Directory
ls -lR /mnt/usb-nas-master/data/luggie/BACKUP/photos/

# Manual Trigger
docker exec $(docker ps -q -f name=imageconv) python3 /app/image-converter.py

# Check Permissions
ssh pi@zolo-pi-4 "ls -la /mnt/usb-nas-master/data/luggie/BACKUP/"
```

---

## 🎯 Summary

```
Architecture:
  Placement:  pi-3 ONLY (Samba MASTER - wo rsync läuft!)
  Registry:   localhost:5000 (private)
  Schedule:   Daily 2:00 AM
  Resolution: 1920x1080 @ 85%

Why pi-3?
  ✓ Samba VIP 192.168.1.122 aktiv auf pi-3
  ✓ rsync repliziert vom pi-3 USB
  ✓ Resized Photos MÜSSEN auf pi-3 liegen
  ✓ Sonst werden sie nicht ins Backup repliziert!

Storage:
  Source:      USB NAS pi-3 (originals)
  Destination: USB NAS pi-3 (resized) → rsync replication
  Logs:        GlusterFS (HA)
  Registry:    GlusterFS (HA)

Deployment:
  Deploy:  ./deploy-image-converter-complete.sh
  Update:  docker service update --image localhost:5000/image-converter:latest imageconv_image-converter
  Logs:    docker service logs -f imageconv_image-converter
```

---

## 📚 Related Files

**Essential (keep these):**
- `deploy-image-converter-complete.sh` - Main deployment script
- `image-converter-stack.yml` - Stack configuration
- `image-converter.py` - Python script
- `Dockerfile` - Container build

**Optional (for reference):**
- `FINAL-README.md` - This file
- `GLUSTERFS-STRUCTURE.md` - Storage architecture

---

**Status:** ✅ Production Ready  
**Last Updated:** 2025-10-20  
**Cluster:** ZoLo (4x RPi5 + NVMe + USB NAS)