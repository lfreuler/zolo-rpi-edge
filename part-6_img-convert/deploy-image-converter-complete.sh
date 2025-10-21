#!/bin/bash
# ZoLo Image Converter - Complete Deployment with Private Registry
# Run on zolo-pi-1 (manager node)

set -e

echo "================================================"
echo "ZoLo Image Converter - Complete Deployment"
echo "================================================"
echo ""

# Configuration
GLUSTER_BASE="/mnt/glusterfs-swarm"
USB_BASE="/mnt/usb-nas-master/data/luggie/BACKUP"
REGISTRY="localhost:5000"
IMAGE_NAME="image-converter"
IMAGE_TAG="latest"
STACK_NAME="imageconv"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if running on manager
if ! docker node ls &>/dev/null; then
    echo -e "${RED}Error: Must run on Docker Swarm manager!${NC}"
    exit 1
fi

echo "Step 1: Setup Node Labels..."
docker node update --label-add storage.nas=true zolo-pi-3
docker node update --label-add storage.nas=true zolo-pi-4
docker node update --label-add storage.nas.priority=master zolo-pi-3
docker node update --label-add storage.nas.priority=backup zolo-pi-4
echo -e "${GREEN}✓ Node labels configured${NC}"
echo ""

echo "Step 2: Create directories on all NAS nodes..."
for node in zolo-pi-3 zolo-pi-4; do
    echo "  Configuring $node..."
    ssh pi@$node "sudo mkdir -p $USB_BASE/{photos,photos-resized} && \
                  sudo mkdir -p $GLUSTER_BASE/logs/image-converter && \
                  sudo chmod 777 $USB_BASE/photos-resized && \
                  sudo chmod 777 $GLUSTER_BASE/logs/image-converter" || true
done
echo -e "${GREEN}✓ Directories created${NC}"
echo ""

echo "Step 3: Build and push to private registry..."
cd $GLUSTER_BASE/repo/image-converter

# Build
docker build -t $REGISTRY/$IMAGE_NAME:$IMAGE_TAG .
echo -e "${GREEN}✓ Image built${NC}"

# Push to registry
docker push $REGISTRY/$IMAGE_NAME:$IMAGE_TAG
echo -e "${GREEN}✓ Image pushed to registry${NC}"
echo ""

echo "Step 4: Deploy stack..."
cd $GLUSTER_BASE/apps/image-converter

# Remove old stack if exists
if docker stack ls | grep -q "$STACK_NAME"; then
    echo "Removing existing stack..."
    docker stack rm "$STACK_NAME"
    sleep 10
fi

# Deploy
docker stack deploy -c image-converter-stack.yml "$STACK_NAME"
echo -e "${GREEN}✓ Stack deployed${NC}"
echo ""

echo "Step 5: Wait for service..."
sleep 5

echo ""
echo "================================================"
echo -e "${GREEN}Deployment Complete!${NC}"
echo "================================================"
echo ""
echo "Service Status:"
docker service ps ${STACK_NAME}_image-converter

echo ""
echo "Registry Image:"
echo "  $REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo ""
echo "Useful Commands:"
echo "  # View logs:"
echo "  docker service logs -f ${STACK_NAME}_image-converter"
echo ""
echo "  # Manual trigger:"
echo "  docker exec \$(docker ps -q -f name=${STACK_NAME}) python3 /app/image-converter.py"
echo ""
echo "  # Update after code changes:"
echo "  cd $GLUSTER_BASE/repo/image-converter"
echo "  docker build -t $REGISTRY/$IMAGE_NAME:$IMAGE_TAG ."
echo "  docker push $REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
echo "  docker service update --image $REGISTRY/$IMAGE_NAME:$IMAGE_TAG ${STACK_NAME}_image-converter"
echo ""