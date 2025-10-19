#!/bin/bash
# 🚀 ZOLO Node Management Automation v3.0 (ZOLO_NMA)
# Enhanced: Docker Swarm + GlusterFS orchestration with proper staging

set -e

# Configuration
declare -A NODES=(
  ["pi1"]="192.168.1.101"
  ["pi2"]="192.168.1.102"
  ["pi3"]="192.168.1.103"
  ["pi4"]="192.168.1.104"
)

# Docker Swarm Manager nodes (update based on your setup)
declare -A MANAGER_NODES=(
  ["pi1"]="192.168.1.101"
)

# Docker Swarm Worker nodes
declare -A WORKER_NODES=(
  ["pi2"]="192.168.1.102"
  ["pi3"]="192.168.1.103"
  ["pi4"]="192.168.1.104"
)

MOUNT_PATH="/mnt/glusterfs-swarm"
GLUSTER_VOLUME="gv0-swarm"
VIP="192.168.1.121"
ACTION=$1
TARGET=$2

# Timeouts and retries
GLUSTER_WAIT_TIMEOUT=60
DOCKER_WAIT_TIMEOUT=30
SWARM_QUORUM_WAIT=45

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper Functions
print_usage() {
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}🚀 ZOLO Node Management Automation v3.0${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "Usage: $0 <action> [target]"
  echo ""
  echo -e "${YELLOW}Actions:${NC}"
  echo "  up        - Start services (keepalived → glusterd → docker)"
  echo "              Uses staged startup: managers first, then workers"
  echo "  down      - Stop services (docker → glusterd → keepalived)"
  echo "  restart   - Restart services with proper orchestration"
  echo "  status    - Show service status"
  echo "  poweroff  - Graceful shutdown (stops all services)"
  echo "  health    - Full health check (all services + mounts)"
  echo ""
  echo -e "${YELLOW}Targets:${NC}"
  echo "  all       - All nodes (default, uses staged startup)"
  echo "  pi1       - Only zolo-pi-1 (192.168.1.101) - MANAGER"
  echo "  pi2       - Only zolo-pi-2 (192.168.1.102)"
  echo "  pi3       - Only zolo-pi-3 (192.168.1.103)"
  echo "  pi4       - Only zolo-pi-4 (192.168.1.104)"
  echo ""
  echo -e "${YELLOW}Examples:${NC}"
  echo "  $0 up all           # Start all nodes (staged: managers → workers)"
  echo "  $0 down pi1         # Stop services on pi1"
  echo "  $0 status           # Status of all nodes"
  echo "  $0 restart pi3      # Restart pi3"
  echo "  $0 health pi2       # Health check pi2"
  echo "  $0 poweroff all     # Shutdown cluster"
  echo ""
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  exit 1
}

# Utility: Check if node is a manager
is_manager_node() {
  local node=$1
  for key in "${!MANAGER_NODES[@]}"; do
    if [ "${MANAGER_NODES[$key]}" == "$node" ]; then
      return 0
    fi
  done
  return 1
}

# Utility: Get node role
get_node_role() {
  local node=$1
  if is_manager_node "$node"; then
    echo "MANAGER"
  else
    echo "WORKER"
  fi
}

get_target_nodes() {
  local target=$1
  
  if [ -z "$target" ] || [ "$target" == "all" ]; then
    echo "${NODES[@]}"
  elif [ -n "${NODES[$target]}" ]; then
    echo "${NODES[$target]}"
  else
    echo -e "${RED}❌ Invalid target: $target${NC}" >&2
    echo -e "${YELLOW}Valid targets: all, pi1, pi2, pi3, pi4${NC}" >&2
    exit 1
  fi
}

# Health Check Functions
check_gluster_peers() {
  local node=$1
  echo -e "${BLUE}  🔍 Checking GlusterFS peer connectivity...${NC}"

  ssh "$node" "
    peer_count=\$(sudo gluster peer status 2>/dev/null | grep -c 'Peer in Cluster' || echo 0)
    if [ \$peer_count -ge 3 ]; then
      echo '  ✅ All peers connected (\$peer_count/3)'
      exit 0
    else
      echo '  ⚠️  Only \$peer_count/3 peers connected'
      exit 1
    fi
  "
}

check_gluster_volume_health() {
  local node=$1
  echo -e "${BLUE}  🔍 Checking GlusterFS volume health...${NC}"

  ssh "$node" "
    if sudo gluster volume status '$GLUSTER_VOLUME' 2>/dev/null | grep -q 'Status: Started'; then
      brick_count=\$(sudo gluster volume status '$GLUSTER_VOLUME' 2>/dev/null | grep -c 'Online : Y')
      echo \"  ✅ Volume started with \$brick_count bricks online\"
      exit 0
    else
      echo '  ❌ Volume not started or unhealthy'
      exit 1
    fi
  "
}

check_docker_swarm_status() {
  local node=$1
  echo -e "${BLUE}  🔍 Checking Docker Swarm status...${NC}"

  ssh "$node" "
    if docker info 2>/dev/null | grep -q 'Swarm: active'; then
      role=\$(docker info 2>/dev/null | grep 'Is Manager:' | awk '{print \$3}')
      echo \"  ✅ Swarm active (Manager: \$role)\"
      exit 0
    else
      echo '  ⚠️  Not part of swarm'
      exit 1
    fi
  "
}

wait_for_gluster_mount() {
  local node=$1
  local timeout=$GLUSTER_WAIT_TIMEOUT
  local elapsed=0

  echo -e "${BLUE}  ⏳ Waiting for GlusterFS mount (timeout: ${timeout}s)...${NC}"

  while [ $elapsed -lt $timeout ]; do
    if ssh "$node" "mountpoint -q '$MOUNT_PATH' 2>/dev/null && [ \$(ls -A '$MOUNT_PATH' 2>/dev/null | wc -l) -gt 0 ]"; then
      echo -e "${GREEN}  ✅ GlusterFS mount ready (${elapsed}s)${NC}"

      # Additional warm-up period for metadata sync
      echo -e "${BLUE}  ⏳ Warm-up period (10s) for GlusterFS metadata sync...${NC}"
      sleep 10
      return 0
    fi

    if [ $((elapsed % 5)) -eq 0 ]; then
      echo "    ...waiting (${elapsed}/${timeout}s)"
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo -e "${RED}  ❌ GlusterFS mount timeout after ${timeout}s${NC}"
  return 1
}

wait_for_docker_ready() {
  local node=$1
  local timeout=$DOCKER_WAIT_TIMEOUT
  local elapsed=0

  echo -e "${BLUE}  ⏳ Waiting for Docker daemon (timeout: ${timeout}s)...${NC}"

  while [ $elapsed -lt $timeout ]; do
    if ssh "$node" "docker info >/dev/null 2>&1"; then
      echo -e "${GREEN}  ✅ Docker daemon ready (${elapsed}s)${NC}"
      return 0
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo -e "${RED}  ❌ Docker daemon timeout after ${timeout}s${NC}"
  return 1
}

wait_for_swarm_quorum() {
  local manager_node=$1
  local timeout=$SWARM_QUORUM_WAIT
  local elapsed=0

  echo -e "${BLUE}  ⏳ Waiting for Swarm quorum (timeout: ${timeout}s)...${NC}"

  while [ $elapsed -lt $timeout ]; do
    if ssh "$manager_node" "docker node ls >/dev/null 2>&1"; then
      managers=$(ssh "$manager_node" "docker node ls --filter role=manager 2>/dev/null | grep -c Ready || echo 0")
      if [ "$managers" -gt 0 ]; then
        echo -e "${GREEN}  ✅ Swarm quorum established (${managers} manager(s) ready)${NC}"
        return 0
      fi
    fi

    if [ $((elapsed % 10)) -eq 0 ]; then
      echo "    ...waiting for quorum (${elapsed}/${timeout}s)"
    fi

    sleep 3
    elapsed=$((elapsed + 3))
  done

  echo -e "${RED}  ❌ Swarm quorum timeout after ${timeout}s${NC}"
  return 1
}

action_up() {
  local node=$1
  local role=$(get_node_role "$node")

  echo -e "${GREEN}▶ Starting services on $node [${role}]${NC}"

  # 1. keepalived first (for VIP)
  echo "  1️⃣  Starting keepalived..."
  ssh -o ConnectTimeout=5 "$node" 'sudo systemctl enable keepalived && sudo systemctl start keepalived' 2>/dev/null || {
    echo -e "${YELLOW}  ⚠️  keepalived not configured or already running${NC}"
  }
  sleep 3

  # 2. GlusterFS
  echo "  2️⃣  Starting glusterd..."
  ssh "$node" 'sudo systemctl enable glusterd && sudo systemctl start glusterd'
  sleep 3

  # 3. Wait for GlusterFS health
  if ! check_gluster_peers "$node"; then
    echo -e "${YELLOW}  ⚠️  Peer connectivity issues, continuing...${NC}"
  fi

  # 4. Wait for mount with proper validation
  if ! wait_for_gluster_mount "$node"; then
    echo -e "${YELLOW}  ⚠️  Attempting manual mount...${NC}"
    ssh "$node" "sudo mount '$MOUNT_PATH' 2>/dev/null || true"

    # Retry wait after manual mount
    if ! wait_for_gluster_mount "$node"; then
      echo -e "${RED}  ❌ Mount failed - Docker may have issues!${NC}"
    fi
  fi

  # 5. Validate volume health before starting Docker
  if ! check_gluster_volume_health "$node"; then
    echo -e "${YELLOW}  ⚠️  Volume health check failed, proceeding with caution...${NC}"
  fi

  # 6. Docker
  echo "  3️⃣  Starting docker..."
  ssh "$node" 'sudo systemctl enable docker && sudo systemctl start docker'

  # 7. Wait for Docker to be ready
  if ! wait_for_docker_ready "$node"; then
    echo -e "${RED}  ❌ Docker failed to start properly!${NC}"
    return 1
  fi

  # 8. For managers: verify swarm status and wait for quorum
  if is_manager_node "$node"; then
    echo "  4️⃣  Checking Swarm manager status..."

    if ! check_docker_swarm_status "$node"; then
      echo -e "${YELLOW}  ⚠️  Node not in swarm, may need to rejoin${NC}"
    else
      if ! wait_for_swarm_quorum "$node"; then
        echo -e "${YELLOW}  ⚠️  Swarm quorum not established, cluster may have issues${NC}"
      fi
    fi
  fi

  # 9. For workers: attempt to rejoin if not in swarm
  if ! is_manager_node "$node"; then
    echo "  4️⃣  Checking worker swarm status..."

    if ! check_docker_swarm_status "$node"; then
      echo -e "${YELLOW}  ⚠️  Worker not in swarm (normal after restart)${NC}"
      echo -e "${YELLOW}  ℹ️  Worker will auto-rejoin on first service deployment${NC}"
    fi
  fi

  echo -e "${GREEN}✅ Services started on $node${NC}\n"
}

action_down() {
  local node=$1
  echo -e "${YELLOW}▼ Stopping services on $node${NC}"
  
  # 1. Docker zuerst (Workloads)
  echo "  1️⃣  Stopping docker..."
  ssh "$node" 'sudo systemctl stop docker.socket docker && sudo systemctl disable docker'
  
  # 2. GlusterFS
  echo "  2️⃣  Stopping glusterd..."
  ssh "$node" 'sudo systemctl stop glusterd && sudo systemctl disable glusterd'
  
  # 3. keepalived zuletzt (VIP Failover)
  echo "  3️⃣  Stopping keepalived..."
  ssh "$node" 'sudo systemctl stop keepalived && sudo systemctl disable keepalived' 2>/dev/null || {
    echo -e "${YELLOW}  ⚠️  keepalived not configured${NC}"
  }
  
  echo -e "${GREEN}✅ Services stopped on $node${NC}\n"
}

action_restart() {
  local node=$1
  echo -e "${BLUE}🔄 Restarting services on $node${NC}"
  action_down "$node"
  sleep 3
  action_up "$node"
}

action_status() {
  local node=$1
  echo -e "${BLUE}📊 Status of $node${NC}"
  
  ssh "$node" '
    echo "  Hostname: $(hostname)"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  keepalived:  $(systemctl is-active keepalived 2>/dev/null || echo N/A)"
    echo "  glusterd:    $(systemctl is-active glusterd)"
    echo "  docker:      $(systemctl is-active docker)"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # VIP Check
    if ip addr show eth0 | grep -q "192.168.1.121"; then
      echo "  🎯 Has VIP: 192.168.1.121 (MASTER)"
    fi
    
    # Mount Check
    if mountpoint -q "'"$MOUNT_PATH"'"; then
      echo "  💾 Gluster Mount: ✅ OK"
    else
      echo "  💾 Gluster Mount: ❌ NOT MOUNTED"
    fi
  '
  echo ""
}

action_health() {
  local node=$1
  echo -e "${BLUE}🏥 Health Check: $node${NC}"
  
  ssh "$node" '
    echo "  Hostname: $(hostname)"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Services
    echo "  📋 Services:"
    for svc in keepalived glusterd docker; do
      status=$(systemctl is-active $svc 2>/dev/null || echo "inactive")
      if [ "$status" == "active" ]; then
        echo "    ✅ $svc: $status"
      else
        echo "    ❌ $svc: $status"
      fi
    done
    
    echo ""
    echo "  💾 Storage:"
    
    # Mount
    if mountpoint -q "'"$MOUNT_PATH"'"; then
      size=$(df -h "'"$MOUNT_PATH"'" | tail -1 | awk "{print \$2}")
      used=$(df -h "'"$MOUNT_PATH"'" | tail -1 | awk "{print \$5}")
      echo "    ✅ Gluster Mount: $size ($used used)"
    else
      echo "    ❌ Gluster Mount: NOT MOUNTED"
    fi
    
    # LVM
    if [ -e /dev/gluster-vg/data ]; then
      echo "    ✅ LVM Volume: present"
    else
      echo "    ❌ LVM Volume: missing"
    fi
    
    echo ""
    echo "  🌐 Network:"
    
    # VIP
    if ip addr show eth0 | grep -q "192.168.1.121"; then
      echo "    🎯 VIP .121: ACTIVE (MASTER)"
    else
      echo "    ⚪ VIP .121: standby"
    fi
    
    if ip addr show eth0 | grep -q "192.168.1.122"; then
      echo "    🎯 VIP .122: ACTIVE (SAMBA MASTER)"
    fi
    
    # Gluster Peers
    echo ""
    echo "  🔗 Gluster Peers:"
    sudo gluster peer status 2>/dev/null | grep -E "(Hostname|State)" | sed "s/^/    /"
    
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  '
  echo ""
}

action_poweroff() {
  local node=$1
  echo -e "${RED}⚠️  POWEROFF: $node${NC}"
  read -p "Are you sure? (yes/no): " confirm
  
  if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}Aborted.${NC}"
    return
  fi
  
  echo -e "${YELLOW}Stopping services gracefully...${NC}"
  action_down "$node"
  
  echo -e "${RED}🔌 Shutting down $node...${NC}"
  ssh "$node" 'sudo shutdown -h now' &
  
  echo -e "${GREEN}✅ Shutdown initiated${NC}\n"
}

# Staged cluster operations
staged_cluster_up() {
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}🚀 STAGED CLUSTER STARTUP${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo ""

  # Stage 1: Start all managers first
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}STAGE 1: Starting Manager Nodes${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  for node in "${MANAGER_NODES[@]}"; do
    action_up "$node"
  done

  echo -e "${GREEN}✅ All managers started${NC}"
  echo ""
  sleep 5

  # Stage 2: Start all workers
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}STAGE 2: Starting Worker Nodes${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  for node in "${WORKER_NODES[@]}"; do
    action_up "$node"
  done

  echo -e "${GREEN}✅ All workers started${NC}"
  echo ""

  # Stage 3: Final cluster validation
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}STAGE 3: Cluster Validation${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  # Get first manager node
  local first_manager="${MANAGER_NODES[pi1]}"

  echo -e "${BLUE}  🔍 Validating cluster state from $first_manager...${NC}"
  ssh "$first_manager" "
    echo '  Docker Swarm Nodes:'
    docker node ls 2>/dev/null || echo '    ❌ Cannot connect to swarm'

    echo ''
    echo '  GlusterFS Volume Status:'
    sudo gluster volume status '$GLUSTER_VOLUME' brief 2>/dev/null || echo '    ❌ Cannot get volume status'
  "

  echo ""
  echo -e "${GREEN}✅ STAGED STARTUP COMPLETE${NC}"
}

staged_cluster_down() {
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}🚀 STAGED CLUSTER SHUTDOWN${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo ""

  # Stage 1: Stop all workers first
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}STAGE 1: Stopping Worker Nodes${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  for node in "${WORKER_NODES[@]}"; do
    action_down "$node"
  done

  echo -e "${GREEN}✅ All workers stopped${NC}"
  echo ""
  sleep 3

  # Stage 2: Stop all managers
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}STAGE 2: Stopping Manager Nodes${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  for node in "${MANAGER_NODES[@]}"; do
    action_down "$node"
  done

  echo -e "${GREEN}✅ All managers stopped${NC}"
  echo ""
  echo -e "${GREEN}✅ STAGED SHUTDOWN COMPLETE${NC}"
}

staged_cluster_restart() {
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}🔄 STAGED CLUSTER RESTART${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo ""

  staged_cluster_down
  echo ""
  echo -e "${BLUE}⏳ Waiting 10 seconds before restart...${NC}"
  sleep 10
  echo ""
  staged_cluster_up
}

# Main Logic
if [ -z "$ACTION" ]; then
  print_usage
fi

# Header
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}🚀 ZOLO Node Management - Action: ${ACTION}${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Check if we should use staged operations for "all" target
if [ -z "$TARGET" ] || [ "$TARGET" == "all" ]; then
  case "$ACTION" in
    up)
      staged_cluster_up
      ;;
    down)
      staged_cluster_down
      ;;
    restart)
      staged_cluster_restart
      ;;
    status|health)
      # For status/health, process all nodes
      TARGET_NODES=$(get_target_nodes "$TARGET")
      for NODE in $TARGET_NODES; do
        case "$ACTION" in
          status)
            action_status "$NODE"
            ;;
          health)
            action_health "$NODE"
            ;;
        esac
      done
      ;;
    poweroff)
      # For poweroff, use staged shutdown then poweroff
      staged_cluster_down
      echo ""
      echo -e "${RED}⚠️  CLUSTER POWEROFF${NC}"
      read -p "Poweroff all nodes? (yes/no): " confirm

      if [ "$confirm" == "yes" ]; then
        echo -e "${RED}🔌 Shutting down all nodes...${NC}"
        for NODE in "${!NODES[@]}"; do
          ssh "${NODES[$NODE]}" 'sudo shutdown -h now' &
        done
        echo -e "${GREEN}✅ Shutdown initiated on all nodes${NC}"
      else
        echo -e "${YELLOW}Poweroff aborted.${NC}"
      fi
      ;;
    *)
      echo -e "${RED}❌ Unknown action: $ACTION${NC}"
      print_usage
      ;;
  esac
else
  # Single node operation
  TARGET_NODES=$(get_target_nodes "$TARGET")

  for NODE in $TARGET_NODES; do
    case "$ACTION" in
      up)
        action_up "$NODE"
        ;;
      down)
        action_down "$NODE"
        ;;
      restart)
        action_restart "$NODE"
        ;;
      status)
        action_status "$NODE"
        ;;
      health)
        action_health "$NODE"
        ;;
      poweroff)
        action_poweroff "$NODE"
        ;;
      *)
        echo -e "${RED}❌ Unknown action: $ACTION${NC}"
        print_usage
        ;;
    esac
  done
fi

# Post-action cluster status (only for single node operations)
if [[ "$ACTION" =~ ^(up|restart)$ ]] && [ "$TARGET" != "all" ] && [ -n "$TARGET" ]; then
  # Only show if we can connect to a manager
  for manager in "${MANAGER_NODES[@]}"; do
    if ssh "$manager" "docker node ls >/dev/null 2>&1"; then
      echo ""
      echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
      echo -e "${GREEN}📊 Docker Swarm Cluster Status (from $manager):${NC}"
      echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
      ssh "$manager" "docker node ls 2>/dev/null"
      break
    fi
  done
fi

echo ""
echo -e "${GREEN}✅ Operation completed!${NC}"