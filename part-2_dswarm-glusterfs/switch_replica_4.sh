Gute Entscheidung! Bei deinem Setup macht **Replica 4** absolut Sinn. Hier der Vergleich:

## **Performance-Auswirkungen bei Replica 4**

### **Schreiben** 📝
- **Replica 2:** ~100-110 MB/s (2 Kopien)
- **Replica 4:** ~80-100 MB/s (4 Kopien)
- **Impact:** ~10-20% langsamer

### **Lesen** 📖
- **Replica 4:** **BESSER!** Load-Balancing über alle 4 Nodes
- Mehr Nodes = mehr parallele Lesezugriffe

### **Dein Bottleneck**
Bei 1GBit Netzwerk (~125 MB/s theoretisch):
- Replica 2 schafft ~100-110 MB/s
- Replica 4 schafft ~80-100 MB/s
- **Beide sind durch 1GBit limitiert**, nicht durch GlusterFS!

## **Replica 4 Vorteile für dich**

```
Ausfallsicherheit:
✅ Bis zu 3 Nodes können ausfallen
✅ 75% Ausfalltoleranz statt 25%
✅ Wartung ohne Risiko möglich
✅ Alle Daten auf allen Nodes

Kapazität:
❌ Nur ~380GB nutzbar (statt 760GB)
   - Aber: Für Docker Swarm oft ausreichend!
```

## **Migration auf Replica 4**

### **Option 1: Neu erstellen (Empfohlen)**

```bash
#!/bin/bash
# migrate-to-replica4.sh - AUF ZOLO-PI-1

echo "=== Migration zu Replica 4 ==="

# 1. Backup machen (wichtig!)
echo "1. Erstelle Backup..."
sudo rsync -av /mnt/glusterfs-swarm/ /backup/glusterfs-backup/

# 2. Altes Volume stoppen
echo "2. Stoppe altes Volume..."
sudo gluster volume stop gv0-swarm
sudo gluster volume delete gv0-swarm

# 3. Bricks aufräumen (auf ALLEN Nodes via SSH)
echo "3. Räume Bricks auf..."
for i in {1..4}; do
    ssh pi@192.168.1.10$i "sudo rm -rf /data/gluster/swarm/brick/*"
done

# 4. Neues Volume mit Replica 4 erstellen
echo "4. Erstelle neues Volume (Replica 4)..."
sudo gluster volume create gv0-swarm \
    replica 4 \
    192.168.1.101:/data/gluster/swarm/brick \
    192.168.1.102:/data/gluster/swarm/brick \
    192.168.1.103:/data/gluster/swarm/brick \
    192.168.1.104:/data/gluster/swarm/brick \
    force

# 5. Performance Tuning
echo "5. Performance Tuning..."
sudo gluster volume set gv0-swarm performance.cache-size 256MB
sudo gluster volume set gv0-swarm performance.write-behind-window-size 4MB
sudo gluster volume set gv0-swarm performance.io-thread-count 32
sudo gluster volume set gv0-swarm network.ping-timeout 10
sudo gluster volume set gv0-swarm cluster.quorum-type auto
sudo gluster volume set gv0-swarm cluster.server-quorum-ratio 51%

# 6. Volume starten
echo "6. Starte Volume..."
sudo gluster volume start gv0-swarm

# 7. Remount auf allen Nodes
echo "7. Remount auf allen Nodes..."
for i in {1..4}; do
    echo "Remounting on pi-$i..."
    ssh pi@192.168.1.10$i "sudo umount /mnt/glusterfs-swarm && sudo mount /mnt/glusterfs-swarm"
done

# 8. Daten zurückspielen
echo "8. Restore Daten..."
sudo rsync -av /backup/glusterfs-backup/ /mnt/glusterfs-swarm/

# 9. Volume Info
echo "9. Volume Info:"
sudo gluster volume info gv0-swarm
sudo gluster volume status gv0-swarm

echo ""
echo "✅ Migration zu Replica 4 abgeschlossen!"
echo ""
echo "Nutzbarer Speicher: ~380GB (statt 760GB)"
echo "Ausfallsicherheit: Bis zu 3 Nodes"
echo ""
```

### **Wichtige Änderungen**

**Performance Tuning für Replica 4:**
```bash
# Quorum aktivieren (wichtig bei Replica 4!)
sudo gluster volume set gv0-swarm cluster.quorum-type auto
sudo gluster volume set gv0-swarm cluster.server-quorum-ratio 51%

# Write-Behind für bessere Schreibperformance
sudo gluster volume set gv0-swarm performance.write-behind on
sudo gluster volume set gv0-swarm performance.flush-behind on
```

**NFS Export bleibt gleich** - keine Änderung nötig!

## **Performance-Test nach Migration**

```bash
#!/bin/bash
# test-replica4-performance.sh

TEST_PATH="/mnt/glusterfs-swarm"

echo "=== Replica 4 Performance Test ==="

# Write Test
echo "1. Write Test (1GB)..."
time sudo dd if=/dev/zero of=$TEST_PATH/test bs=1M count=1000 oflag=direct

# Read Test
echo "2. Read Test..."
sudo sh -c "echo 3 > /proc/sys/vm/drop_caches"
time sudo dd if=$TEST_PATH/test of=/dev/null bs=1M

# Cleanup
sudo rm -f $TEST_PATH/test

echo ""
echo "Erwartete Werte:"
echo "Write: ~80-100 MB/s (bei 1GBit)"
echo "Read: ~100-120 MB/s (Load-Balancing über 4 Nodes)"
```

## **Meine Empfehlung für dich**

✅ **JA, wechsle zu Replica 4!**

**Gründe:**
1. **Wartungsfreundlich**: Du kannst 1-2 Nodes offline nehmen ohne Risiko
2. **Production-ready**: 3-Node Ausfall ist extrem unwahrscheinlich
3. **Performance**: 80-100 MB/s ist für Docker Swarm mehr als ausreichend
4. **380GB**: Für Config, Logs, kleine DBs völlig genug

**Wann NICHT wechseln:**
- Wenn du wirklich 760GB Storage brauchst
- Für Media-Storage (Videos, Backups) → dann eher externes NAS

## **Speicher-Check**

```bash
# Was brauchst du wirklich?
docker system df  # Zeigt Docker Speichernutzung

# Typischer Docker Swarm:
# - Container Images: 5-20 GB
# - Volumes/Configs: 10-50 GB
# - Logs: 5-10 GB
# = ~50-100 GB realistisch
```

Mit **380GB nutzbarem Speicher** bei Replica 4 hast du noch **300GB+ Reserve**!

Soll ich dir das Migration-Script noch detaillierter ausarbeiten? 🚀