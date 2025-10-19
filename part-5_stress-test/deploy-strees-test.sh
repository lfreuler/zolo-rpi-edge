#!/bin/bash
# deploy-stress-test.sh
# Deployment Script für ZoLo Stress Test

set -e

echo "╔════════════════════════════════════════════╗"
echo "║   ZoLo Cluster Stress Test Deployment     ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# Check if running on Swarm Manager
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "❌ Fehler: Docker Swarm ist nicht aktiv!"
    exit 1
fi

if ! docker node ls &>/dev/null; then
    echo "❌ Fehler: Nicht auf einem Swarm Manager!"
    exit 1
fi

echo "✅ Docker Swarm Manager erkannt"
echo ""

# Nodes anzeigen
echo "=== Verfügbare Nodes ==="
docker node ls
echo ""

# Anzahl Nodes zählen
NODE_COUNT=$(docker node ls -q | wc -l)
echo "📊 Erkannte Nodes: $NODE_COUNT"
echo ""

# Warnung
echo "⚠️  WARNUNG: Dieser Test wird:"
echo "   - Auf ALLEN $NODE_COUNT Nodes gleichzeitig laufen"
echo "   - CPU: ~3-4 Cores pro Node"
echo "   - RAM: ~1-1.5GB pro Node"
echo "   - Disk I/O: ~100MB/s Writes auf GlusterFS"
echo "   - Dauer: 5 Minuten"
echo ""

# Bereite GlusterFS Ordner vor
echo "=== Vorbereitung: Erstelle Test-Ordner ==="
if ! mountpoint -q /mnt/glusterfs-swarm 2>/dev/null; then
    echo "❌ GlusterFS ist nicht gemountet unter /mnt/glusterfs-swarm"
    echo "   Bitte erst GlusterFS mounten!"
    exit 1
fi

sudo mkdir -p /mnt/glusterfs-swarm/stress-test
sudo mkdir -p /mnt/glusterfs-swarm/stress-test-combined
echo "✅ Test-Ordner erstellt"
echo ""

# Bestätigung
read -p "Stress Test starten? (yes/no): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Abbruch."
    exit 0
fi

echo ""
echo "=== Deploying Stack... ==="

# Stack deployen
docker stack deploy -c stress-test-stack.yml stress-test

echo ""
echo "✅ Stack deployed!"
echo ""

# Warte auf Container
echo "=== Warte auf Container Start... ==="
sleep 10

# Status anzeigen
echo ""
echo "=== Initial Status ==="
docker stack ps stress-test --no-trunc

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║        Stress Test läuft jetzt!            ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "📊 Monitoring Commands:"
echo "   watch -n 2 'docker stack ps stress-test'"
echo "   ./monitor-stress-test.sh"
echo ""
echo "🛑 Zum Stoppen:"
echo "   docker stack rm stress-test"
echo ""
echo "⏱️  Test läuft für 5 Minuten..."
echo ""

# Optional: Auto-Monitor starten
read -p "Monitor automatisch starten? (yes/no): " START_MONITOR
if [[ "$START_MONITOR" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Starting monitor..."
    ./monitor-stress-test.sh
fi