#!/bin/bash
# Deploy script to extract build artifacts from Docker container
# Usage: ./deploy.sh [container_name]

set -e

CONTAINER_NAME="${1:-amaranth-cynthion}"
BUILD_DIR="./build"

echo "🚀 Deploying build artifacts from Docker container: $CONTAINER_NAME"

# Check if the image exists
if ! docker image inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo "❌ Error: Docker image '$CONTAINER_NAME' not found."
    echo "   Please build it first: docker build -t $CONTAINER_NAME ."
    exit 1
fi

# Create a temporary container from the image
echo "📦 Creating temporary container..."
TEMP_CONTAINER=$(docker create "$CONTAINER_NAME")

# Ensure cleanup on exit
trap "docker rm $TEMP_CONTAINER >/dev/null 2>&1" EXIT

# Create build directory if it doesn't exist
mkdir -p "$BUILD_DIR"

# Copy build artifacts from container
echo "📥 Copying build artifacts..."

# Copy Rust binaries
if docker cp "$TEMP_CONTAINER:/work/build/binaries" "$BUILD_DIR/" 2>/dev/null; then
    echo "   ✅ Copied Rust binaries to $BUILD_DIR/binaries/"
else
    echo "   ⚠️  No Rust binaries found"
fi

# Copy ARM firmware
if docker cp "$TEMP_CONTAINER:/work/build/firmware" "$BUILD_DIR/" 2>/dev/null; then
    echo "   ✅ Copied ARM firmware to $BUILD_DIR/firmware/"
else
    echo "   ⚠️  No ARM firmware found"
fi

# Copy build info
if docker cp "$TEMP_CONTAINER:/work/build/build-info.txt" "$BUILD_DIR/" 2>/dev/null; then
    echo "   ✅ Copied build info to $BUILD_DIR/build-info.txt"
else
    echo "   ⚠️  No build info found"
fi

# Copy gateware if it exists
if docker cp "$TEMP_CONTAINER:/work/build/gateware" "$BUILD_DIR/" 2>/dev/null; then
    echo "   ✅ Copied gateware to $BUILD_DIR/gateware/"
else
    echo "   ⚠️  No gateware found (might be built separately)"
fi

# Display build info
echo ""
echo "📊 Build Information:"
if [ -f "$BUILD_DIR/build-info.txt" ]; then
    cat "$BUILD_DIR/build-info.txt"
fi

echo ""
echo "✨ Deployment complete!"
echo "📂 Build artifacts are in: $BUILD_DIR/"
echo ""
echo "Available files:"
ls -lh "$BUILD_DIR/binaries/" 2>/dev/null || echo "   (no binaries)"
ls -lh "$BUILD_DIR/firmware/" 2>/dev/null || echo "   (no firmware)"
ls -lh "$BUILD_DIR/gateware/" 2>/dev/null || echo "   (no gateware)"
