FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    GODOT_VERSION=4.6-stable \
    PORT=10000 \
    INTERNAL_PORT=7777 \
    ROOM_NAME="Arena Online TANK.IO" \
    MAX_PLAYERS=10

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    python3 \
    libx11-6 \
    libxcursor1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxinerama1 \
    libxrandr2 \
    libxrender1 \
    libgl1 \
    libfontconfig1 \
    libfreetype6 \
    libasound2 \
    libpulse0 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" -o /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /tmp/godot_bin \
    && mv "/tmp/godot_bin/Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -rf /tmp/godot.zip /tmp/godot_bin

WORKDIR /app
COPY . /app

# Pre-import project assets cleanly inside the Linux container
RUN /usr/local/bin/godot --headless --audio-driver Dummy --path /app --import --quit

EXPOSE 10000

CMD ["python3", "/app/server_proxy.py"]
