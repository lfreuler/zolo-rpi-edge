#!/bin/bash
# setup-node-labels.sh
# Auf zolo-pi-1 ausführen

echo "=== Setting up ZoLo Cluster Node Labels ==="
echo ""

# Check if we're on manager
if ! docker node ls &> /dev/null; then
    echo "❌ Fehler: Muss auf einem Swarm Manager ausgeführt werden!"
    exit 1
fi

echo "Current Nodes:"
docker node ls
echo ""

# ============================================
# zolo-pi-1 (Manager + Storage)
# ============================================
echo "Labeling zolo-pi-1 (Manager + Storage)..."
docker node update \
  --label-add role=manager \
  --label-add storage.tier=swarm \
  --label-add storage.type=nvme \
  --label-add zone=1 \
  --label-add compute.class=standard \
  --label-add hardware=rpi5 \
  zolo-pi-1

# ============================================
# zolo-pi-2 (Worker + Storage)
# ============================================
echo "Labeling zolo-pi-2 (Worker + Storage)..."
docker node update \
  --label-add role=worker \
  --label-add storage.tier=swarm \
  --label-add storage.type=nvme \
  --label-add zone=2 \
  --label-add compute.class=standard \
  --label-add hardware=rpi5 \
  zolo-pi-2

# ============================================
# zolo-pi-3 (Worker + Storage + Samba)
# ============================================
echo "Labeling zolo-pi-3 (Worker + Storage + Samba)..."
docker node update \
  --label-add role=worker \
  --label-add storage.tier=both \
  --label-add storage.type=nvme \
  --label-add zone=3 \
  --label-add samba=true \
  --label-add compute.class=standard \
  --label-add hardware=rpi5 \
  zolo-pi-3

# ============================================
# zolo-pi-4 (Worker + Storage + Samba)
# ============================================
echo "Labeling zolo-pi-4 (Worker + Storage + Samba)..."
docker node update \
  --label-add role=worker \
  --label-add storage.tier=both \
  --label-add storage.type=nvme \
  --label-add zone=4 \
  --label-add samba=true \
  --label-add compute.class=standard \
  --label-add hardware=rpi5 \
  zolo-pi-4

echo ""
echo "✅ Labels gesetzt!"
echo ""

# ============================================
# Verification
# ============================================
echo "=== Label Verification ==="
echo ""

for node in zolo-pi-1 zolo-pi-2 zolo-pi-3 zolo-pi-4; do
    echo "Node: $node"
    docker node inspect $node --format '{{ .Spec.Labels }}' | tr ',' '\n' | sed 's/map\[//;s/\]//'
    echo ""
done

echo "=== Summary ==="
echo "Manager Nodes (role=manager):"
docker node ls --filter "node.label=role=manager" --format "table {{.Hostname}}\t{{.Status}}\t{{.Availability}}"

echo ""
echo "Storage Nodes (storage.tier=swarm):"
docker node ls --filter "node.label=storage.tier=swarm" --format "table {{.Hostname}}\t{{.Status}}\t{{.Availability}}"

echo ""
echo "Samba Nodes (samba=true):"
docker node ls --filter "node.label=samba=true" --format "table {{.Hostname}}\t{{.Status}}\t{{.Availability}}"

echo ""
echo "🎉 Cluster Labeling complete!"