# ZoLo Cluster Stress Test Guide

## 🎯 Was macht dieser Test?

Der Stack deployed **3 verschiedene Stress-Test Services** auf **ALLEN 4 Nodes gleichzeitig**:

### 1. **stress-compute** (CPU + RAM)
- **CPU**: 4 Threads pro Node
- **Memory**: 512MB pro Thread (2 Threads = 1GB total)
- **Limits**: Max 3.5 CPUs, 1.5GB RAM
- **Dauer**: 5 Minuten

### 2. **stress-io** (Disk I/O auf GlusterFS)
- **Writes**: ~100MB alle 2 Sekunden pro Node
- **Node-spezifische Ordner**: `/data/stress-test/<hostname>/`
- **Pattern**: Schreiben → Lesen → Cleanup
- **Files**: Rolling 3-File Limit pro Node
- **Dauer**: 5 Minuten

### 3. **stress-combined** (CPU + RAM + I/O)
- **CPU**: 4 parallele bc-Berechnungen (Pi Approximation)
- **Memory**: 256MB Allocation & Read Cycles
- **Disk**: 50MB Writes alle 5 Sekunden
- **Node-spezifische Ordner**: `/data/stress-test-combined/<hostname>/`
- **Dauer**: 5 Minuten

### 4. **monitor** (Monitoring Service)
- Läuft nur auf Manager Node
- Zeigt System Stats alle 30 Sekunden
- Prüft GlusterFS Health

---

## 📋 Voraussetzungen

```bash
# 1. Docker Swarm muss aktiv sein
docker info | grep "Swarm: active"

# 2. GlusterFS muss gemountet sein
mountpoint /mnt/glusterfs-swarm

# 3. Alle 4 Nodes müssen READY sein
docker node ls
```

---

## 🚀 Deployment

### Option A: Mit Script (Empfohlen)

```bash
# 1. Scripts ausführbar machen
chmod +x deploy-stress-test.sh
chmod +x monitor-stress-test.sh

# 2. Deploy starten
./deploy-stress-test.sh

# Das Script:
# - Prüft Prerequisites
# - Erstellt Test-Ordner
# - Zeigt Nodes
# - Fragt nach Bestätigung
# - Deployed den Stack
# - Bietet Auto-Monitor an
```

### Option B: Manuell

```bash
# 1. Test-Ordner vorbereiten
sudo mkdir -p /mnt/glusterfs-swarm/stress-test
sudo mkdir -p /mnt/glusterfs-swarm/stress-test-combined

# 2. Stack deployen
docker stack deploy -c stress-test-stack.yml stress-test

# 3. Status prüfen
docker stack ps stress-test
```

---

## 📊 Monitoring

### Live Monitor (empfohlen)

```bash
./monitor-stress-test.sh

# Zeigt alle 5 Sekunden:
# - Container Status
# - Node Stats (Load, Temp, Memory)
# - GlusterFS Health
# - File Count
# - VIP Status
```

### Manuelle Commands

```bash
# Container Status
watch -n 2 'docker stack ps stress-test'

# Service Logs (pro Service)
docker service logs stress-test_stress-compute -f
docker service logs stress-test_stress-io -f
docker service logs stress-test_stress-combined -f
docker service logs stress-test_monitor -f

# Node-spezifische Stats
ssh pi@192.168.1.101 'top -bn1 | head -20'
ssh pi@192.168.1.101 'free -h'
ssh pi@192.168.1.101 'df -h /mnt/glusterfs-swarm'

# GlusterFS Health
sudo gluster volume status gv0-swarm
sudo gluster volume heal gv0-swarm info

# Files auf GlusterFS
sudo find /mnt/glusterfs-swarm/stress-test* -type f | wc -l
sudo du -sh /mnt/glusterfs-swarm/stress-test*

# CPU Temperature (alle Nodes)
for i in 101 102 103 104; do
    echo "Node 192.168.1.$i:"
    ssh pi@192.168.1.$i "vcgencmd measure_temp"
done
```

---

## 🛑 Test Stoppen

```bash
# Stack entfernen
docker stack rm stress-test

# Test-Files cleanup (optional)
sudo rm -rf /mnt/glusterfs-swarm/stress-test*

# Verifizieren
docker stack ls
docker service ls
```

---

## 🔍 Was zu beobachten

### ✅ Erwartetes Verhalten

1. **CPU Load**
   - Load Average: 3-4 pro Node
   - Normal für den Test

2. **Memory**
   - ~1.5-2GB used pro Node
   - Sollte nicht swappen

3. **Disk I/O**
   - ~100MB/s Writes pro Node
   - Network sollte bei ~400-800Mbit/s sein (4 Nodes schreiben)

4. **GlusterFS**
   - Alle 4 Bricks sollten ONLINE sein
   - Keine Split-Brain Errors
   - Files sollten repliziert werden

5. **Failover**
   - Bei Node-Ausfall sollten Container auf anderen Nodes restarten
   - VIP sollte zu Backup Node wechseln (~3s)

### ⚠️ Probleme erkennen

1. **Container CrashLoopBackOff**
   ```bash
   docker stack ps stress-test | grep -E "Failed|Shutdown"
   ```

2. **OOM (Out of Memory)**
   ```bash
   ssh pi@192.168.1.101 'dmesg | grep -i "out of memory"'
   ```

3. **GlusterFS Split-Brain**
   ```bash
   sudo gluster volume heal gv0-swarm info split-brain
   ```

4. **Network Saturation**
   ```bash
   ssh pi@192.168.1.101 'iftop -t -s 5'
   ```

5. **Throttling**
   ```bash
   ssh pi@192.168.1.101 'vcgencmd get_throttled'
   # 0x0 = OK
   # 0x50000 = Throttling
   ```

---

## 🎓 Test Scenarios

### Scenario 1: Basis Stress Test (5min)

```bash
./deploy-stress-test.sh
# Warte 5 Minuten
docker stack rm stress-test
```

**Erwartung**: Alle Services laufen stabil durch

---

### Scenario 2: Node Failover während Test

```bash
# Terminal 1: Start Test
./deploy-stress-test.sh
./monitor-stress-test.sh

# Terminal 2 (nach 1 min): Stoppe Docker auf einem Node
ssh pi@192.168.1.102 'sudo systemctl stop docker'

# Beobachte:
# - Container werden auf andere Nodes migriert
# - GlusterFS bleibt verfügbar
# - VIP wechselt falls nötig

# Recovery
ssh pi@192.168.1.102 'sudo systemctl start docker'
```

**Erwartung**: 
- Container migration: 10-30s
- Keine Datenverluste
- GlusterFS bleibt online

---

### Scenario 3: GlusterFS Failover während Test

```bash
# Start Test
./deploy-stress-test.sh

# Stoppe GlusterFS auf einem Brick Node
ssh pi@192.168.1.103 'sudo systemctl stop glusterd'

# Beobachte:
# - Volume sollte verfügbar bleiben (Replica!)
# - I/O könnte langsamer werden
# - Keine Errors in Container Logs

# Recovery
ssh pi@192.168.1.103 'sudo systemctl start glusterd'
```

**Erwartung**: 
- Services laufen weiter
- Heal startet automatisch nach Recovery

---

### Scenario 4: Extended Stress Test (30min+)

```bash
# Editiere stack: timeout 300s → timeout 1800s (30min)
nano stress-test-stack.yml

# Deploy
docker stack deploy -c stress-test-stack.yml stress-test

# Monitor CPU Temps
watch -n 10 'for i in 101 102 103 104; do ssh pi@192.168.1.$i "echo Node $i: \$(vcgencmd measure_temp)"; done'
```

**Erwartung**: 
- CPU Temp: <80°C (mit Fan)
- Keine Throttling Events

---

## 📈 Performance Baselines

### Normal Values (ohne Stress)

```yaml
CPU Load: 0.5-1.0 pro Node
Memory Used: 500-800MB pro Node
Disk I/O: <10MB/s
Network: <50Mbit/s
CPU Temp: 40-50°C
```

### Under Stress Test

```yaml
CPU Load: 3.0-4.0 pro Node
Memory Used: 1.5-2.0GB pro Node
Disk I/O: 80-120MB/s pro Node
Network: 400-800Mbit/s (gesamt)
CPU Temp: 60-75°C
```

### Critical Thresholds

```yaml
CPU Load: >6.0 → Problem
Memory Used: >90% → OOM Risk
Disk I/O: Stalls → Storage Issue
Network: >900Mbit/s → Saturation
CPU Temp: >85°C → Throttling
```

---

## 🐛 Troubleshooting

### Problem: Container starten nicht

```bash
# Check logs
docker service logs stress-test_stress-io --tail 50

# Check GlusterFS mount
mountpoint /mnt/glusterfs-swarm

# Remount if needed
sudo umount /mnt/glusterfs-swarm
sudo mount /mnt/glusterfs-swarm
```

### Problem: OOM Kills

```bash
# Reduce memory in stack
nano stress-test-stack.yml
# --vm-bytes 512M → --vm-bytes 256M

# Redeploy
docker stack deploy -c stress-test-stack.yml stress-test
```

### Problem: GlusterFS Performance schlecht

```bash
# Check Heal
sudo gluster volume heal gv0-swarm info

# Check Brick Status
sudo gluster volume status gv0-swarm

# Check Network
ping 192.168.1.102
iperf3 -c 192.168.1.102
```

### Problem: CPU Throttling

```bash
# Check throttling status
vcgencmd get_throttled

# Check temps
vcgencmd measure_temp

# Solution:
# - Verbessere Cooling
# - Reduce CPU stress (--cpu 2 statt --cpu 4)
```

---

## 📊 Results Interpretation

Nach dem Test kannst du checken:

```bash
# 1. Files pro Node
for node in zolo-pi-1 zolo-pi-2 zolo-pi-3 zolo-pi-4; do
    echo "$node:"
    sudo find /mnt/glusterfs-swarm/stress-test/$node -type f | wc -l
done

# 2. Total geschriebene Daten
sudo du -sh /mnt/glusterfs-swarm/stress-test*

# 3. GlusterFS Heal Status (sollte leer sein)
sudo gluster volume heal gv0-swarm info

# 4. Split-Brain Check (sollte leer sein)
sudo gluster volume heal gv0-swarm info split-brain

# 5. Performance Stats
# - Durchschnittliche Write Speed
# - Spitzen Load
# - Max Memory Usage
# - Failover Zeit (falls getestet)
```

---

## ✅ Success Criteria

Test ist erfolgreich wenn:

- ✅ Alle 12 Container laufen (3 Services × 4 Nodes)
- ✅ Keine OOM Kills
- ✅ GlusterFS bleibt verfügbar
- ✅ Keine Split-Brain Errors
- ✅ CPU Temp <80°C
- ✅ Failover funktioniert (<30s)
- ✅ Daten sind repliziert (check auf 2 Nodes)

---

## 🎉 Next Steps

Nach erfolgreichem Test:

1. **Production Workloads deployen**
   - Du weißt jetzt die Limits
   - GlusterFS ist stabil getestet
   - Failover funktioniert

2. **Monitoring Setup**
   - Prometheus + Grafana
   - Alert Rules based on test results
   - Temperature Monitoring

3. **Optimization**
   - Tune GlusterFS basierend auf Test
   - Adjust Resource Limits
   - Network Optimization

---

## 📝 Notes

- **GlusterFS + Parallel Writes**: Mit Node-spezifischen Ordnern ist es safe!
- **Replica 2**: Bedeutet 2× Traffic, aber du hast Redundanz
- **Network**: 1GBit ist der Bottleneck bei 4 Nodes parallel writing
- **PoE Limit**: 65W total - achte auf CPU temps unter Last!