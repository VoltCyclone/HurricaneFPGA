# syntax=docker/dockerfile:1.4

# Use Python 3.11 slim as the base image
FROM python:latest

# Set environment variables early (these rarely change)
ENV LUNA_PLATFORM="cynthion.gateware.platform:CynthionPlatformRev1D4"
ENV BUILD_LOCAL="1"
ENV CARGO_HOME=/usr/local/cargo
ENV RUSTUP_HOME=/usr/local/rustup
ENV PATH="/usr/local/cargo/bin:${PATH}"

# Install system dependencies including Rust prerequisites
# Combine all apt operations into a single layer to reduce image size
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        graphviz \
        pkg-config \
        libgraphviz-dev \
        libusb-1.0-0 \
        libusb-1.0-0-dev \
        libudev-dev \
        curl \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Install Rust (stable toolchain) with ARM cross-compilation support
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal && \
    chmod -R a+w $RUSTUP_HOME $CARGO_HOME && \
    rustup target add thumbv7em-none-eabihf

# Upgrade pip in a separate layer (cached unless base image changes)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip

# Install stable Python packages that rarely change (these will be cached)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir \
    amaranth \
    amaranth-boards \
    pyserial \
    setuptools \
    wheel \
    pyvcd \
    pytest \
    pygreat \
    cynthion

# Install yowasp packages separately (large downloads, benefit from caching)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir \
    yowasp-yosys \
    yowasp-nextpnr-ecp5

# Install luna from git (changes less frequently than local code)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir git+https://github.com/greatscottgadgets/luna.git

# Set working directory before copying files
WORKDIR /work

# Copy only dependency files first for better caching
COPY Cargo.toml Cargo.lock* ./

# Create dummy structure matching the binary path to build dependencies
RUN mkdir -p legacy/src/frontend && \
    echo "fn main() {}" > legacy/src/frontend/main.rs && \
    cargo build --release && \
    rm -rf legacy

# Copy your project files into the container (this layer invalidates most often)
COPY . /work

# Build the PC CLI tool (native binary) with cache mount for faster rebuilds
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/work/target \
    cargo build --release && \
    cp target/release/hurricanefpga /work/hurricanefpga

# Build the SAMD51 firmware (ARM Cortex-M4) with cache mount
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/work/firmware/samd51_hid_injector/target \
    cd firmware/samd51_hid_injector && \
    cargo build --release --target thumbv7em-none-eabihf && \
    cp target/thumbv7em-none-eabihf/release/samd51_hid_injector /work/samd51_hid_injector

# Create build output directory and copy all artifacts
RUN mkdir -p /work/build/binaries /work/build/firmware && \
    cp /work/hurricanefpga /work/build/binaries/ && \
    strip /work/build/binaries/hurricanefpga && \
    cp /work/samd51_hid_injector /work/build/firmware/ && \
    arm-none-eabi-size /work/build/firmware/samd51_hid_injector > /work/build/firmware/size-info.txt 2>&1 || echo "arm-none-eabi-size not available" > /work/build/firmware/size-info.txt

# Create a build info file
RUN echo "Build Date: $(date -u +'%Y-%m-%d %H:%M:%S UTC')" > /work/build/build-info.txt && \
    echo "Rust Version: $(rustc --version)" >> /work/build/build-info.txt && \
    echo "Cargo Version: $(cargo --version)" >> /work/build/build-info.txt && \
    echo "Python Version: $(python --version)" >> /work/build/build-info.txt && \
    echo "" >> /work/build/build-info.txt && \
    echo "Built Artifacts:" >> /work/build/build-info.txt && \
    echo "  - hurricanefpga (PC CLI tool)" >> /work/build/build-info.txt && \
    echo "  - samd51_hid_injector (ARM Cortex-M4 firmware)" >> /work/build/build-info.txt && \
    echo "" >> /work/build/build-info.txt && \
    echo "ARM Target: thumbv7em-none-eabihf" >> /work/build/build-info.txt

# Default command (change if needed)
CMD ["python", "src/backend_simple/top.py"]
