#!/bin/bash
# monitor-stress-test.sh
# Monitoring Script für ZoLo Stress Test

set -e

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "╔════════════════════════════════════════════╗"
echo "║      ZoLo Stress Test Monitor              ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# Check if stack is running
if ! docker stack ps stress-test &>/dev/null; then
    echo -e "${RED}❌ Stack 'stress-test' läuft nicht!${NC}"
    exit 1
fi

# Node IPs für SSH
NODES=(
    "192.168.1.101"  # zolo-pi-1
    "192.168.1.102"  # zolo-pi-2
    "192.168.1.103"  # zolo-pi-3
    "192.168.1.104"  # zolo-pi-4
)

# Function: Print separator
separator() {
    echo "════════════════════════════════════════════════════════"
}

# Function: Check node stats via SSH
check_node_stats() {
    local NODE_IP=$1
    local NODE_NAME=$(ssh -o ConnectTimeout=2 pi@$NODE_IP "hostname" 2>/dev/null || echo "unknown")
    
    if [[ "$NODE_NAME" == "unknown" ]]; then
        echo -e "${RED}❌ Node $NODE_IP nicht erreichbar${NC}"
        return
    fi
    
    echo -e "${BLUE}📊 Node: $NODE_NAME ($NODE_IP)${NC}"
    
    # Load Average
    local LOAD=$(ssh pi@$NODE_IP "cat /proc/loadavg" 2>/dev/null | awk '{print $1, $2, $3}')
    echo -e "   Load Average: ${YELLOW}$LOAD${NC}"
    
    # CPU Temp (falls verfügbar)
    local TEMP=$(ssh pi@$NODE_IP "vcgencmd measure_temp 2>/dev/null | cut -d= -f2" || echo "N/A")
    echo -e "   CPU Temp: ${YELLOW}$TEMP${NC}"
    
    # Memory
    local MEM=$(ssh pi@$NODE_IP "free -h" 2>/dev/null | grep Mem)
    echo "   Memory: $MEM"
    
    # Disk I/O (approximiert)
    local DISK_WRITE=$(ssh pi@$NODE_IP "find /mnt/glusterfs-swarm/stress-test* -type f 2>/dev/null | wc -l" || echo "0")
    echo -e "   Files on GlusterFS: ${GREEN}$DISK_WRITE${NC}"
    
    echo ""
}

# Function: Get container stats
get_container_stats() {
    echo -e "${BLUE}🐳 Container Status:${NC}"
    docker stack ps stress-test --format "table {{.Name}}\t{{.Node}}\t{{.CurrentState}}\t{{.Error}}" | head -20
    echo ""
}

# Function: GlusterFS Health
check_gluster_health() {
    echo -e "${BLUE}💾 GlusterFS Status:${NC}"
    
    # Volume Status
    sudo gluster volume status gv0-swarm 2>/dev/null | head -20 || echo "Fehler beim Abrufen"
    echo ""
    
    # Disk Usage
    echo -e "${BLUE}📁 Disk Usage:${NC}"
    df -h /mnt/glusterfs-swarm 2>/dev/null || echo "Nicht gemountet"
    echo ""
    
    # Test Files
    echo -e "${BLUE}📝 Test Files:${NC}"
    sudo find /mnt/glusterfs-swarm/stress-test* -type f 2>/dev/null | wc -l | xargs echo "Total Files:"
    echo ""
}

# Function: Network Stats
check_network() {
    echo -e "${BLUE}🌐 Network Stats (VIP Status):${NC}"
    
    for NODE_IP in "${NODES[@]}"; do
        local NODE_NAME=$(ssh -o ConnectTimeout=2 pi@$NODE_IP "hostname" 2>/dev/null || echo "unknown")
        local VIP_STATUS=$(ssh -o ConnectTimeout=2 pi@$NODE_IP "ip addr show eth0 | grep '192.168.1.121'" 2>/dev/null || echo "")
        
        if [[ -n "$VIP_STATUS" ]]; then
            echo -e "   ${GREEN}✅ VIP 192.168.1.121 aktiv auf $NODE_NAME${NC}"
        fi
    done
    echo ""
}

# Main monitoring loop
echo "Starting continuous monitoring (Ctrl+C to stop)..."
echo "Refresh every 5 seconds"
separator
echo ""

COUNTER=0
while true; do
    clear
    COUNTER=$((COUNTER + 1))
    
    echo "╔════════════════════════════════════════════╗"
    echo "║      ZoLo Stress Test Monitor #$COUNTER        ║"
    echo "╚════════════════════════════════════════════╝"
    echo "$(date '+%Y-%m-%d %H:%M:%S')"
    separator
    echo ""
    
    # Container Status
    get_container_stats
    separator
    echo ""
    
    # Node Stats
    for NODE_IP in "${NODES[@]}"; do
        check_node_stats "$NODE_IP"
    done
    separator
    echo ""
    
    # GlusterFS Health
    check_gluster_health
    separator
    echo ""
    
    # Network
    check_network
    separator
    echo ""
    
    echo "Press Ctrl+C to stop monitoring"
    sleep 5
done