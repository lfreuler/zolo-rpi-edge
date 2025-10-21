# WireGuard: EC2 Server + zolo-pi-1 Client
*Minimal setup - Only zolo-pi-1 connects to EC2 via VPN*

---

## Architecture

```
EC2 (Public IP - YOUR_EC2_IP)
├─ WireGuard Server: 10.0.0.1:51820/UDP
└─ Clients:
   └─ zolo-pi-1: 10.0.0.2

Home Network (NO ports forwarded)
├─ zolo-pi-1: 192.168.1.101 → WireGuard CLIENT (connects OUT to EC2:51820)
├─ zolo-pi-2: 192.168.1.102 (stays internal)
├─ zolo-pi-3: 192.168.1.103 (stays internal)
├─ zolo-pi-4: 192.168.1.104 (stays internal)
├─ Storage VIP: 192.168.1.121
└─ SSH Tunnel: zolo-pi-1 → EC2 (backup)

Access:
├─ Session Manager → EC2
├─ EC2 SSH → zolo-pi-1 (10.0.0.2 via VPN)
├─ EC2 SSH → zolo-pi-2/3/4 (via zolo-pi-1 as bastion)
└─ EC2 NFS → 10.0.0.2:/mnt/glusterfs-swarm
```

---

## Phase 1: EC2 Setup (WireGuard Server)

### 1.1 Install WireGuard on EC2

```bash
#!/bin/bash
# On EC2 (via Session Manager)

sudo apt update
sudo apt install -y wireguard wireguard-tools

# Enable IP forwarding
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.conf.all.rp_filter = 0" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "✅ WireGuard installed on EC2"
```

### 1.2 Generate Keys on EC2

```bash
#!/bin/bash
# On EC2

sudo -i  # Enter root shell

cd /etc/wireguard
umask 077

# Server keys
wg genkey | tee server_private.key | wg pubkey | tee server_public.key

# Client key for zolo-pi-1
wg genkey | tee zolo-pi-1_private.key | wg pubkey | tee zolo-pi-1_public.key

# Display keys - SAVE THESE
echo "=== SERVER KEYS ==="
echo "Server Private:"
cat server_private.key
echo ""
echo "Server Public:"
cat server_public.key

echo ""
echo "=== ZOLO-PI-1 CLIENT KEYS ==="
echo "zolo-pi-1 Private:"
cat zolo-pi-1_private.key
echo ""
echo "zolo-pi-1 Public:"
cat zolo-pi-1_public.key
```

**Save to file on your laptop:**
```
server_private.key: [paste output]
server_public.key: [paste output]
zolo-pi-1_private.key: [paste output]
zolo-pi-1_public.key: [paste output]
```

### 1.3 Create WireGuard Server Config on EC2

```bash
#!/bin/bash
# On EC2

sudo tee /etc/wireguard/wg0.conf << 'EOF'
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = SERVER_PRIVATE_KEY_HERE

# Enable forwarding and NAT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# zolo-pi-1 (only client)
[Peer]
PublicKey = ZOLO_PI1_PUBLIC_KEY_HERE
AllowedIPs = 10.0.0.2/32
EOF

# Replace SERVER_PRIVATE_KEY_HERE and ZOLO_PI1_PUBLIC_KEY_HERE with actual keys

sudo nano /etc/wireguard/wg0.conf  # Edit to add keys

sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

sudo systemctl status wg-quick@wg0

echo "✅ WireGuard server running on EC2"
```

### 1.4 Update EC2 Security Group

```
AWS Console → EC2 → Security Groups

Inbound Rules:
  - Protocol: UDP
    Port: 51820
    Source: YOUR_HOME_PUBLIC_IP/32 (e.g., 203.0.113.45/32)

Outbound Rules:
  - Leave as default (allow all)
```

**Why /32?** Restricts to only your home IP, maximum security. Only your home can connect to WireGuard port.

---

## Phase 2: zolo-pi-1 Setup (WireGuard Client)

### 2.1 Install WireGuard on zolo-pi-1

```bash
#!/bin/bash
# On zolo-pi-1 (SSH from home network or local)

sudo apt update
sudo apt install -y wireguard wireguard-tools

# Enable IP forwarding
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "✅ WireGuard installed on zolo-pi-1"
```

### 2.2 Create WireGuard Client Config on zolo-pi-1

```bash
#!/bin/bash
# On zolo-pi-1

YOUR_EC2_IP="YOUR_ELASTIC_IP"
CLIENT_PRIVATE_KEY="zolo-pi-1_private_key_from_ec2"
SERVER_PUBLIC_KEY="server_public_key_from_ec2"

sudo tee /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.0.0.2/24
PrivateKey = ${CLIENT_PRIVATE_KEY}
DNS = 8.8.8.8, 1.1.1.1

# Keep connection alive (auto-reconnect if drops)
PersistentKeepalive = 25

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${YOUR_EC2_IP}:51820
AllowedIPs = 10.0.0.0/24
EOF

# Replace YOUR_EC2_IP, CLIENT_PRIVATE_KEY, SERVER_PUBLIC_KEY with actual values

sudo nano /etc/wireguard/wg0.conf  # Double-check keys

sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# Verify
sudo wg show
ip addr show wg0

echo "✅ WireGuard client connected to EC2"
```

---

## Phase 3: SSH Tunnel Backup (zolo-pi-1)

**If VPN drops, SSH tunnel provides fallback access:**

### 3.1 Setup EC2 SSH Key on zolo-pi-1

```bash
# On zolo-pi-1, copy EC2 private key
nano ~/.ssh/ec2-key.pem
# Paste your EC2 private key
chmod 600 ~/.ssh/ec2-key.pem

# Test SSH to EC2
ssh -i ~/.ssh/ec2-key.pem ubuntu@YOUR_EC2_IP
```

### 3.2 Create SSH Tunnel Script on zolo-pi-1

```bash
#!/bin/bash
# On zolo-pi-1

sudo tee /usr/local/bin/ssh-tunnel-backup.sh << 'EOF'
#!/bin/bash

EC2_IP="YOUR_EC2_IP"
EC2_USER="ubuntu"
TUNNEL_PORT=8022

while true; do
  echo "[$(date)] Starting SSH tunnel..."
  
  # Reverse tunnel: external SSH -p 8022 ec2_ip connects to zolo-pi-1:22
  ssh -i ~/.ssh/ec2-key.pem \
      -R ${TUNNEL_PORT}:localhost:22 \
      ${EC2_USER}@${EC2_IP} \
      -N -T
  
  echo "Tunnel disconnected, reconnecting in 10s..."
  sleep 10
done
EOF

sudo chmod +x /usr/local/bin/ssh-tunnel-backup.sh
```

### 3.3 Add to Systemd (Auto-start on reboot)

```bash
#!/bin/bash
# On zolo-pi-1

sudo tee /etc/systemd/system/ssh-tunnel-backup.service << 'EOF'
[Unit]
Description=SSH Tunnel Backup to EC2
After=network.target

[Service]
Type=simple
User=pi
ExecStart=/usr/local/bin/ssh-tunnel-backup.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ssh-tunnel-backup
sudo systemctl start ssh-tunnel-backup

# Check status
sudo systemctl status ssh-tunnel-backup
```

---

## Testing

### Test 1: WireGuard Connection

```bash
# On EC2
sudo wg show

# Should show:
# interface: wg0
#   peer: ZOLO_PI1_PUBLIC_KEY
#     allowed ips: 10.0.0.2/32
#     latest handshake: just now
#     transfer: X B received, Y B sent
```

### Test 2: Ping zolo-pi-1 from EC2

```bash
# On EC2
ping 10.0.0.2

# Should respond
```

### Test 3: SSH to zolo-pi-1 via VPN

```bash
# On EC2
ssh -i ~/.ssh/ec2-key.pem pi@10.0.0.2

# Should connect to zolo-pi-1 via VPN (10.0.0.2)
```

### Test 4: NFS from EC2

```bash
# On EC2
sudo mkdir -p /mnt/zolo
sudo mount -t nfs 10.0.0.2:/mnt/glusterfs-swarm /mnt/zolo
df -h /mnt/zolo

# Should work
```

### Test 5: SSH Tunnel Fallover

```bash
# On EC2, stop WireGuard on zolo-pi-1
ssh -i ~/.ssh/ec2-key.pem pi@10.0.0.2 'sudo systemctl stop wg-quick@wg0'

# Wait 30-60s for tunnel to establish
sleep 60

# Access via SSH tunnel (port 8022)
ssh -i ~/.ssh/ec2-key.pem -p 8022 ubuntu@YOUR_EC2_IP

# Then (from that session):
ssh -i ~/.ssh/ec2-key.pem pi@localhost

# Restart VPN
sudo systemctl start wg-quick@wg0
```

---

## Access from EC2

### SSH to Zolo Cluster

```bash
# Via VPN (zolo-pi-1 is the gateway)
ssh -i ~/.ssh/ec2-key.pem pi@10.0.0.2          # zolo-pi-1 direct

# Via zolo-pi-1 as bastion (to other nodes)
ssh -J pi@10.0.0.2 pi@192.168.1.102           # zolo-pi-2
ssh -J pi@10.0.0.2 pi@192.168.1.103           # zolo-pi-3
ssh -J pi@10.0.0.2 pi@192.168.1.104           # zolo-pi-4
```

### Mount NFS on EC2

```bash
# Direct via VPN
sudo mount -t nfs 10.0.0.2:/mnt/glusterfs-swarm /mnt/zolo

# Or internal IPs via bastion
# (less useful, stick with VPN IPs)
```

### Docker Access

```bash
# From EC2
docker -H ssh://pi@10.0.0.2 ps

# View containers on zolo-pi-1 cluster
docker -H ssh://pi@10.0.0.2 ps -a
```

---

## Monitoring

### Check WireGuard Status

```bash
# On EC2
sudo wg show              # Detailed status
watch -n 1 'sudo wg show' # Real-time monitoring

# On zolo-pi-1
sudo wg show
```

### View Logs

```bash
# On EC2
sudo journalctl -u wg-quick@wg0 -f

# On zolo-pi-1
sudo journalctl -u wg-quick@wg0 -f
sudo journalctl -u ssh-tunnel-backup -f
```

---

## Troubleshooting

### WireGuard won't connect

```bash
# On zolo-pi-1
sudo systemctl status wg-quick@wg0
sudo journalctl -u wg-quick@wg0 -n 20

# Check config syntax
sudo wg-quick show wg0

# Verify EC2 is reachable
ping YOUR_EC2_IP

# Try manual restart
sudo wg-quick down wg0
sudo wg-quick up wg0 --verbose
```

### "Stale file handle" on NFS

```bash
# Connection dropped
sudo umount -f /mnt/zolo
sudo mount -t nfs 10.0.0.2:/mnt/glusterfs-swarm /mnt/zolo
```

### SSH tunnel not working

```bash
# On zolo-pi-1
sudo systemctl status ssh-tunnel-backup
sudo journalctl -u ssh-tunnel-backup -n 20

# Check EC2 key permission
ls -la ~/.ssh/ec2-key.pem
# Should be: -rw------- (600)

# Test SSH manually
ssh -i ~/.ssh/ec2-key.pem ubuntu@YOUR_EC2_IP
```

### High latency

```bash
# Test ping
ping -c 10 10.0.0.1

# If >50ms, check:
# - EC2 region (use closest to you)
# - Home internet quality
# - Increase PersistentKeepalive to 10 (from 25) if drops
```

---

## Quick Reference

### IPs

```
EC2 Public: YOUR_EC2_IP
EC2 VPN: 10.0.0.1
zolo-pi-1 Private: 192.168.1.101
zolo-pi-1 VPN: 10.0.0.2
zolo-pi-2: 192.168.1.102
zolo-pi-3: 192.168.1.103
zolo-pi-4: 192.168.1.104
Storage VIP: 192.168.1.121
```

### Access Strings

```bash
# From EC2 via Session Manager
ssh -i ~/.ssh/ec2-key.pem pi@10.0.0.2                    # zolo-pi-1 via VPN
ssh -J pi@10.0.0.2 pi@192.168.1.102                      # zolo-pi-2 via bastion
sudo mount -t nfs 10.0.0.2:/mnt/glusterfs-swarm /mnt/zolo

# If VPN down (SSH tunnel)
ssh -i ~/.ssh/ec2-key.pem -p 8022 ubuntu@YOUR_EC2_IP
# Then: ssh -i ~/.ssh/ec2-key.pem pi@localhost
```

### Commands

```bash
# Check WireGuard
sudo wg show
sudo systemctl status wg-quick@wg0

# Check SSH tunnel
sudo systemctl status ssh-tunnel-backup
sudo journalctl -u ssh-tunnel-backup -f

# Restart
sudo systemctl restart wg-quick@wg0
sudo systemctl restart ssh-tunnel-backup
```

---

## Deployment Checklist

```
EC2 Setup:
□ WireGuard installed
□ Keys generated (server + zolo-pi-1)
□ Server config created with keys
□ Service enabled and running
□ Security group allows 51820/UDP
□ Can see 0 peers initially

zolo-pi-1 Setup:
□ WireGuard installed
□ Client config created
□ Service enabled and running
□ Shows successful handshake

SSH Tunnel Setup:
□ EC2 private key copied to zolo-pi-1
□ Tunnel script created
□ Systemd service created and running
□ Can SSH -p 8022 to EC2

Testing:
□ EC2 sees zolo-pi-1 in wg show
□ Ping 10.0.0.2 from EC2 works
□ SSH to 10.0.0.2 from EC2 works
□ NFS mount from EC2 works
□ SSH tunnel failover tested

Final:
□ All services set to auto-start
□ Monitoring configured
□ VPN + tunnel working as primary/backup
```

---

## Summary

```
What you have:
✅ EC2 = WireGuard VPN hub (public facing, secure)
✅ zolo-pi-1 = VPN client (no incoming ports at home)
✅ SSH tunnel backup (if VPN drops)
✅ NFS access from EC2 via VPN
✅ Docker access via SSH
✅ All other nodes accessible via zolo-pi-1 bastion

Cost: $3-5/month (EC2 t2.nano)
Setup: 2 hours
Maintenance: Minimal
Security: Military-grade encryption + no incoming ports at home
Reliability: 99%+ (EC2 + home ISP quality)
```