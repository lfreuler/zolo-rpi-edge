#!/bin/bash
# zolo-dashboard.sh - ENHANCED VERSION
# Generiert ein HTML Monitoring Dashboard für ZoLo Cluster

OUTPUT="/mnt/glusterfs-swarm/webapp/index.html"
TEMP_OUTPUT="/tmp/zolo-dashboard-$$.html"
REFRESH=10
SSH_OPTS="-o ConnectTimeout=1 -o StrictHostKeyChecking=no -o BatchMode=yes -o ControlMaster=auto -o ControlPath=/tmp/ssh-%r@%h:%p -o ControlPersist=60"

echo "Generating ZoLo Cluster Dashboard..."

# HTML Header
cat > "$TEMP_OUTPUT" << 'HTMLHEAD'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta http-equiv="refresh" content="10">
    <title>ZoLo Cluster Monitor</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #0f172a;
            color: #e2e8f0;
            padding: 20px;
        }
        .header {
            background: linear-gradient(135deg, #1e293b 0%, #334155 100%);
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.3);
        }
        .header h1 { font-size: 24px; margin-bottom: 5px; }
        .header .time { color: #94a3b8; font-size: 14px; }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        .card {
            background: #1e293b;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.3);
            border: 1px solid #334155;
        }
        .card h2 {
            font-size: 16px;
            margin-bottom: 15px;
            color: #60a5fa;
            border-bottom: 2px solid #334155;
            padding-bottom: 10px;
        }
        .node {
            background: #0f172a;
            padding: 15px;
            margin-bottom: 12px;
            border-radius: 8px;
            border-left: 4px solid;
        }
        .node.online { border-color: #10b981; }
        .node.offline { border-color: #ef4444; }
        .node-name {
            font-weight: bold;
            font-size: 15px;
            margin-bottom: 8px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .node-metrics {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 8px;
            margin-top: 10px;
            font-size: 12px;
        }
        .metric-item {
            background: rgba(0,0,0,0.2);
            padding: 6px 10px;
            border-radius: 4px;
            display: flex;
            justify-content: space-between;
        }
        .metric-label { color: #94a3b8; }
        .metric-val { font-weight: bold; color: #e2e8f0; }
        .metric-val.good { color: #10b981; }
        .metric-val.warning { color: #f59e0b; }
        .metric-val.critical { color: #ef4444; }
        .badge {
            display: inline-block;
            padding: 3px 8px;
            border-radius: 4px;
            font-size: 11px;
            font-weight: bold;
            margin-right: 5px;
            margin-bottom: 3px;
        }
        .badge.success { background: #10b981; color: white; }
        .badge.danger { background: #ef4444; color: white; }
        .badge.warning { background: #f59e0b; color: white; }
        .badge.info { background: #60a5fa; color: white; }
        .badge.gray { background: #6b7280; color: white; }
        .metric {
            display: flex;
            justify-content: space-between;
            padding: 8px 0;
            border-bottom: 1px solid #334155;
        }
        .metric:last-child { border-bottom: none; }
        .metric-label-inline { color: #94a3b8; font-size: 13px; }
        .metric-value { font-weight: bold; font-size: 13px; }
        .vip-box {
            background: #0f172a;
            padding: 12px;
            margin-bottom: 10px;
            border-radius: 6px;
            border-left: 3px solid #60a5fa;
        }
        .service-box {
            background: #0f172a;
            padding: 12px;
            margin-bottom: 8px;
            border-radius: 6px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .progress-bar {
            width: 100%;
            height: 10px;
            background: #334155;
            border-radius: 5px;
            overflow: hidden;
            margin-top: 5px;
        }
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #10b981, #22c55e);
            transition: width 0.3s;
        }
        .progress-fill.warning { background: linear-gradient(90deg, #f59e0b, #fbbf24); }
        .progress-fill.danger { background: linear-gradient(90deg, #ef4444, #f87171); }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 ZoLo Cluster Monitor</h1>
HTMLHEAD

# Timestamp with hostname
echo "        <div class=\"time\">Last Update: $(date '+%Y-%m-%d %H:%M:%S') | Generated on: $(hostname)</div>" >> "$TEMP_OUTPUT"

echo "    </div>" >> "$TEMP_OUTPUT"
echo "    <div class=\"grid\">" >> "$TEMP_OUTPUT"
echo "        <div class=\"card\">" >> "$TEMP_OUTPUT"
echo "            <h2>📡 Cluster Nodes</h2>" >> "$TEMP_OUTPUT"

# Nodes checken
for i in 1 2 3 4; do
    NODE="zolo-pi-$i"
    IP="192.168.1.10$i"

    if ping -c 1 -W 1 "$IP" &> /dev/null; then
        STATUS="online"
        STATUS_TEXT="Online"

        SSH_DATA=$(ssh $SSH_OPTS pi@"$IP" 'CPU=$(top -bn1 | grep "Cpu(s)" | awk "{print \$2}" | cut -d"%" -f1); MEM=$(free | grep Mem | awk "{printf \"%.0f\", \$3/\$2 * 100}"); UPTIME=$(uptime -p | sed "s/up //"); CPU_TEMP=$(vcgencmd measure_temp 2>/dev/null | cut -d= -f2 | cut -d"'"'"'" -f1); [ -z "$CPU_TEMP" ] && CPU_TEMP="N/A"; NVME_TEMP=$(sudo nvme smart-log /dev/nvme0 2>/dev/null | grep "temperature" | head -1 | awk "{print \$3}" | cut -d. -f1); [ -z "$NVME_TEMP" ] && NVME_TEMP="N/A"; FAN_STATE=$(cat /sys/class/thermal/cooling_device0/cur_state 2>/dev/null); [ -z "$FAN_STATE" ] && FAN_STATE="N/A"; DISK_PERCENT=$(df /data/gluster/swarm 2>/dev/null | tail -1 | awk "{print \$5}" | tr -d "%"); [ -z "$DISK_PERCENT" ] && DISK_PERCENT="N/A"; VIP_121=$(ip addr show eth0 | grep -q 192.168.1.121 && echo "yes" || echo "no"); VIP_122=$(ip addr show eth0 | grep -q 192.168.1.122 && echo "yes" || echo "no"); NFS=$(systemctl is-active nfs-kernel-server); GLUSTER=$(systemctl is-active glusterd); echo "$CPU|$MEM|$UPTIME|$CPU_TEMP|$NVME_TEMP|$FAN_STATE|$DISK_PERCENT|$VIP_121|$VIP_122|$NFS|$GLUSTER"' 2>/dev/null)

        IFS='|' read -r CPU MEM UPTIME CPU_TEMP NVME_TEMP FAN_STATE DISK_PERCENT VIP_121 VIP_122 NFS GLUSTER <<< "$SSH_DATA"

        CPU=${CPU:-"N/A"}
        MEM=${MEM:-"N/A"}
        UPTIME=${UPTIME:-"unknown"}
        CPU_TEMP=${CPU_TEMP:-"N/A"}
        NVME_TEMP=${NVME_TEMP:-"N/A"}
        FAN_STATE=${FAN_STATE:-"N/A"}
        DISK_PERCENT=${DISK_PERCENT:-"N/A"}
        VIP_121=${VIP_121:-"no"}
        VIP_122=${VIP_122:-"no"}
        NFS=${NFS:-"inactive"}
        GLUSTER=${GLUSTER:-"inactive"}

        CPU_TEMP_CLASS="good"
        if [ "$CPU_TEMP" != "N/A" ]; then
            CPU_TEMP_NUM=$(echo "$CPU_TEMP" | cut -d. -f1)
            [ "$CPU_TEMP_NUM" -gt 60 ] && CPU_TEMP_CLASS="warning"
            [ "$CPU_TEMP_NUM" -gt 75 ] && CPU_TEMP_CLASS="critical"
        fi

        NVME_TEMP_CLASS="good"
        if [ "$NVME_TEMP" != "N/A" ]; then
            [ "$NVME_TEMP" -gt 50 ] && NVME_TEMP_CLASS="warning"
            [ "$NVME_TEMP" -gt 70 ] && NVME_TEMP_CLASS="critical"
        fi

        DISK_CLASS="good"
        if [ "$DISK_PERCENT" != "N/A" ]; then
            [ "$DISK_PERCENT" -gt 60 ] && DISK_CLASS="warning"
            [ "$DISK_PERCENT" -gt 80 ] && DISK_CLASS="critical"
        fi
    else
        STATUS="offline"
        STATUS_TEXT="Offline"
        CPU="N/A"; MEM="N/A"; UPTIME="N/A"; CPU_TEMP="N/A"; NVME_TEMP="N/A"
        FAN_STATE="N/A"; DISK_PERCENT="N/A"; VIP_121="no"; VIP_122="no"
        NFS="inactive"; GLUSTER="inactive"
        CPU_TEMP_CLASS="good"; NVME_TEMP_CLASS="good"; DISK_CLASS="good"
    fi

    # Node HTML
    echo "            <div class=\"node $STATUS\">" >> "$TEMP_OUTPUT"
    echo "                <div class=\"node-name\">" >> "$TEMP_OUTPUT"
    echo "                    <span>$NODE ($IP)</span>" >> "$TEMP_OUTPUT"
    echo "                    <div>" >> "$TEMP_OUTPUT"
    [ "$VIP_121" = "yes" ] && echo "                        <span class=\"badge info\">VIP .121</span>" >> "$TEMP_OUTPUT"
    [ "$VIP_122" = "yes" ] && echo "                        <span class=\"badge info\">VIP .122</span>" >> "$TEMP_OUTPUT"
    [ "$STATUS" = "online" ] && echo "                        <span class=\"badge success\">$STATUS_TEXT</span>" >> "$TEMP_OUTPUT" || echo "                        <span class=\"badge danger\">$STATUS_TEXT</span>" >> "$TEMP_OUTPUT"
    echo "                    </div>" >> "$TEMP_OUTPUT"
    echo "                </div>" >> "$TEMP_OUTPUT"
    echo "                <div style=\"margin: 8px 0;\">" >> "$TEMP_OUTPUT"
    [ "$NFS" = "active" ] && echo "                    <span class=\"badge success\">NFS</span>" >> "$TEMP_OUTPUT" || echo "                    <span class=\"badge gray\">NFS</span>" >> "$TEMP_OUTPUT"
    [ "$GLUSTER" = "active" ] && echo "                    <span class=\"badge success\">Gluster</span>" >> "$TEMP_OUTPUT" || echo "                    <span class=\"badge gray\">Gluster</span>" >> "$TEMP_OUTPUT"
    echo "                </div>" >> "$TEMP_OUTPUT"
    echo "                <div class=\"node-metrics\">" >> "$TEMP_OUTPUT"
    echo "                    <div class=\"metric-item\">" >> "$TEMP_OUTPUT"
    echo "                        <span class=\"metric-label\">🌡️ CPU Temp</span>" >> "$TEMP_OUTPUT"
    echo "                        <span class=\"metric-val $CPU_TEMP_CLASS\">$CPU_TEMP°C</span>" >> "$TEMP_OUTPUT"
    echo "                    </div>" >> "$TEMP_OUTPUT"
    echo "                    <div class=\"metric-item\">" >> "$TEMP_OUTPUT"
    echo "                        <span class=\"metric-label\">💾 NVMe Temp</span>" >> "$TEMP_OUTPUT"
    echo "                        <span class=\"metric-val $NVME_TEMP_CLASS\">$NVME_TEMP°C</span>" >> "$TEMP_OUTPUT"
    echo "                    </div>" >> "$TEMP_OUTPUT"
    echo "                    <div class=\"metric-item\">" >> "$TEMP_OUTPUT"
    echo "                        <span class=\"metric-label\">⚡ CPU Usage</span>" >> "$TEMP_OUTPUT"
    echo "                        <span class=\"metric-val\">$CPU%</span>" >> "$TEMP_OUTPUT"
    echo "                    </div>" >> "$TEMP_OUTPUT"
    echo "                    <div class=\"metric-item\">" >> "$TEMP_OUTPUT"
    echo "                        <span class=\"metric-label\">🧠 RAM Usage</span>" >> "$TEMP_OUTPUT"
    echo "                        <span class=\"metric-val\">$MEM%</span>" >> "$TEMP_OUTPUT"
    echo "                    </div>" >> "$TEMP_OUTPUT"
    echo "                    <div class=\"metric-item\">" >> "$TEMP_OUTPUT"
    echo "                        <span class=\"metric-label\">🌀 Fan Level</span>" >> "$TEMP_OUTPUT"
    echo "                        <span class=\"metric-val\">$FAN_STATE</span>" >> "$TEMP_OUTPUT"
    echo "                    </div>" >> "$TEMP_OUTPUT"
    echo "                    <div class=\"metric-item\">" >> "$TEMP_OUTPUT"
    echo "                        <span class=\"metric-label\">💿 Disk Used</span>" >> "$TEMP_OUTPUT"
    echo "                        <span class=\"metric-val $DISK_CLASS\">$DISK_PERCENT%</span>" >> "$TEMP_OUTPUT"
    echo "                    </div>" >> "$TEMP_OUTPUT"
    echo "                    <div class=\"metric-item\" style=\"grid-column: 1 / -1;\">" >> "$TEMP_OUTPUT"
    echo "                        <span class=\"metric-label\">⏱️ Uptime</span>" >> "$TEMP_OUTPUT"
    echo "                        <span class=\"metric-val\">$UPTIME</span>" >> "$TEMP_OUTPUT"
    echo "                    </div>" >> "$TEMP_OUTPUT"
    echo "                </div>" >> "$TEMP_OUTPUT"
    echo "            </div>" >> "$TEMP_OUTPUT"
done

# VIP Section
echo "        </div>" >> "$TEMP_OUTPUT"
echo "        <div class=\"card\">" >> "$TEMP_OUTPUT"
echo "            <h2>🌐 Virtual IPs (keepalived)</h2>" >> "$TEMP_OUTPUT"

VIP_121_NODE="none"
for i in 1 2 3 4; do
    VIP_CHECK=$(ssh $SSH_OPTS pi@192.168.1.10$i "ip addr show eth0 | grep -q 192.168.1.121 && echo 'yes' || echo 'no'" 2>/dev/null)
    [ "$VIP_CHECK" = "yes" ] && VIP_121_NODE="zolo-pi-$i" && break
done

VIP_122_NODE="none"
for i in 3 4; do
    VIP_CHECK=$(ssh $SSH_OPTS pi@192.168.1.10$i "ip addr show eth0 | grep -q 192.168.1.122 && echo 'yes' || echo 'no'" 2>/dev/null)
    [ "$VIP_CHECK" = "yes" ] && VIP_122_NODE="zolo-pi-$i" && break
done

echo "            <div class=\"vip-box\">" >> "$TEMP_OUTPUT"
echo "                <strong>192.168.1.121</strong> - Storage VIP (NFS)<br>" >> "$TEMP_OUTPUT"
[ "$VIP_121_NODE" != "none" ] && echo "                <span class=\"badge success\">Active on: $VIP_121_NODE</span>" >> "$TEMP_OUTPUT" || echo "                <span class=\"badge danger\">Active on: $VIP_121_NODE</span>" >> "$TEMP_OUTPUT"
echo "            </div>" >> "$TEMP_OUTPUT"

echo "            <div class=\"vip-box\">" >> "$TEMP_OUTPUT"
echo "                <strong>192.168.1.122</strong> - Samba VIP<br>" >> "$TEMP_OUTPUT"
[ "$VIP_122_NODE" != "none" ] && echo "                <span class=\"badge success\">Active on: $VIP_122_NODE</span>" >> "$TEMP_OUTPUT" || echo "                <span class=\"badge danger\">Active on: $VIP_122_NODE</span>" >> "$TEMP_OUTPUT"
echo "            </div>" >> "$TEMP_OUTPUT"
echo "        </div>" >> "$TEMP_OUTPUT"
echo "    </div>" >> "$TEMP_OUTPUT"

# GlusterFS Section
echo "    <div class=\"grid\">" >> "$TEMP_OUTPUT"
echo "        <div class=\"card\">" >> "$TEMP_OUTPUT"
echo "            <h2>💾 GlusterFS Status</h2>" >> "$TEMP_OUTPUT"

if command -v gluster &> /dev/null; then
    VOL_STATUS=$(sudo gluster volume status gv0-swarm 2>/dev/null | grep -c "Y.*Online")
    HEAL_PENDING=$(sudo gluster volume heal gv0-swarm info 2>/dev/null | grep -c "Number of entries:" || echo "0")

    echo "            <div class=\"metric\">" >> "$TEMP_OUTPUT"
    echo "                <span class=\"metric-label-inline\">Volume</span>" >> "$TEMP_OUTPUT"
    echo "                <span class=\"metric-value\">gv0-swarm</span>" >> "$TEMP_OUTPUT"
    echo "            </div>" >> "$TEMP_OUTPUT"
    echo "            <div class=\"metric\">" >> "$TEMP_OUTPUT"
    echo "                <span class=\"metric-label-inline\">Bricks Online</span>" >> "$TEMP_OUTPUT"
    echo "                <span class=\"metric-value\">" >> "$TEMP_OUTPUT"
    [ "$VOL_STATUS" = "4" ] && echo "                    <span class=\"badge success\">$VOL_STATUS / 4</span>" >> "$TEMP_OUTPUT" || echo "                    <span class=\"badge warning\">$VOL_STATUS / 4</span>" >> "$TEMP_OUTPUT"
    echo "                </span>" >> "$TEMP_OUTPUT"
    echo "            </div>" >> "$TEMP_OUTPUT"
    echo "            <div class=\"metric\">" >> "$TEMP_OUTPUT"
    echo "                <span class=\"metric-label-inline\">Heal Pending</span>" >> "$TEMP_OUTPUT"
    echo "                <span class=\"metric-value\">" >> "$TEMP_OUTPUT"
    [ "$HEAL_PENDING" = "0" ] && echo "                    <span class=\"badge success\">$HEAL_PENDING</span>" >> "$TEMP_OUTPUT" || echo "                    <span class=\"badge warning\">$HEAL_PENDING</span>" >> "$TEMP_OUTPUT"
    echo "                </span>" >> "$TEMP_OUTPUT"
    echo "            </div>" >> "$TEMP_OUTPUT"

    DISK_USED=$(df -h /mnt/glusterfs-swarm 2>/dev/null | tail -1 | awk '{print $3}')
    DISK_TOTAL=$(df -h /mnt/glusterfs-swarm 2>/dev/null | tail -1 | awk '{print $2}')
    DISK_PERCENT=$(df /mnt/glusterfs-swarm 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')

    if [ -n "$DISK_PERCENT" ]; then
        PROGRESS_CLASS=""
        [ "$DISK_PERCENT" -gt 80 ] && PROGRESS_CLASS="danger"
        [ "$DISK_PERCENT" -gt 60 ] && [ "$DISK_PERCENT" -le 80 ] && PROGRESS_CLASS="warning"

        echo "            <div class=\"metric\">" >> "$TEMP_OUTPUT"
        echo "                <span class=\"metric-label-inline\">Storage Used</span>" >> "$TEMP_OUTPUT"
        echo "                <span class=\"metric-value\">$DISK_USED / $DISK_TOTAL ($DISK_PERCENT%)</span>" >> "$TEMP_OUTPUT"
        echo "            </div>" >> "$TEMP_OUTPUT"
        echo "            <div class=\"progress-bar\">" >> "$TEMP_OUTPUT"
        echo "                <div class=\"progress-fill $PROGRESS_CLASS\" style=\"width: ${DISK_PERCENT}%\"></div>" >> "$TEMP_OUTPUT"
        echo "            </div>" >> "$TEMP_OUTPUT"
    fi
else
    echo "            <div class=\"metric\">" >> "$TEMP_OUTPUT"
    echo "                <span class=\"metric-label-inline\">Status</span>" >> "$TEMP_OUTPUT"
    echo "                <span class=\"metric-value\"><span class=\"badge danger\">Gluster not found</span></span>" >> "$TEMP_OUTPUT"
    echo "            </div>" >> "$TEMP_OUTPUT"
fi

echo "        </div>" >> "$TEMP_OUTPUT"

# Docker Section
echo "        <div class=\"card\">" >> "$TEMP_OUTPUT"
echo "            <h2>🐳 Docker Swarm</h2>" >> "$TEMP_OUTPUT"

if command -v docker &> /dev/null && docker info &>/dev/null; then
    STACKS=$(docker stack ls 2>/dev/null | tail -n +2)

    if [ -n "$STACKS" ]; then
        echo "$STACKS" | while read -r line; do
            STACK_NAME=$(echo "$line" | awk '{print $1}')
            SERVICES=$(echo "$line" | awk '{print $2}')
            echo "            <div class=\"service-box\">" >> "$TEMP_OUTPUT"
            echo "                <div>" >> "$TEMP_OUTPUT"
            echo "                    <strong>$STACK_NAME</strong><br>" >> "$TEMP_OUTPUT"
            echo "                    <span style=\"font-size: 11px; color: #94a3b8;\">$SERVICES services</span>" >> "$TEMP_OUTPUT"
            echo "                </div>" >> "$TEMP_OUTPUT"
            echo "                <span class=\"badge success\">Running</span>" >> "$TEMP_OUTPUT"
            echo "            </div>" >> "$TEMP_OUTPUT"
        done
    else
        echo "            <div class=\"metric\">" >> "$TEMP_OUTPUT"
        echo "                <span class=\"metric-label-inline\">Stacks</span>" >> "$TEMP_OUTPUT"
        echo "                <span class=\"metric-value\">No stacks deployed</span>" >> "$TEMP_OUTPUT"
        echo "            </div>" >> "$TEMP_OUTPUT"
    fi

    MANAGERS=$(docker node ls --filter role=manager 2>/dev/null | tail -n +2 | wc -l)
    WORKERS=$(docker node ls --filter role=worker 2>/dev/null | tail -n +2 | wc -l)

    echo "            <div class=\"metric\">" >> "$TEMP_OUTPUT"
    echo "                <span class=\"metric-label-inline\">Managers</span>" >> "$TEMP_OUTPUT"
    echo "                <span class=\"metric-value\"><span class=\"badge info\">$MANAGERS</span></span>" >> "$TEMP_OUTPUT"
    echo "            </div>" >> "$TEMP_OUTPUT"
    echo "            <div class=\"metric\">" >> "$TEMP_OUTPUT"
    echo "                <span class=\"metric-label-inline\">Workers</span>" >> "$TEMP_OUTPUT"
    echo "                <span class=\"metric-value\"><span class=\"badge info\">$WORKERS</span></span>" >> "$TEMP_OUTPUT"
    echo "            </div>" >> "$TEMP_OUTPUT"
else
    echo "            <div class=\"metric\">" >> "$TEMP_OUTPUT"
    echo "                <span class=\"metric-label-inline\">Status</span>" >> "$TEMP_OUTPUT"
    echo "                <span class=\"metric-value\"><span class=\"badge danger\">Docker not available</span></span>" >> "$TEMP_OUTPUT"
    echo "            </div>" >> "$TEMP_OUTPUT"
fi

echo "        </div>" >> "$TEMP_OUTPUT"
echo "    </div>" >> "$TEMP_OUTPUT"
echo "</body>" >> "$TEMP_OUTPUT"
echo "</html>" >> "$TEMP_OUTPUT"

# Atomically move temp file to final location
mv "$TEMP_OUTPUT" "$OUTPUT"

echo "✅ Dashboard generated: $OUTPUT"