# Self-contained CARLA development image: build toolchain, web VS Code
# (code-server) and an artifact download server. Build it once with internet,
# then move it with `docker save` / `docker load` (see manage.sh).
#
# Not inside the image (too large, mounted at run time, see docker-compose.yml):
#   - Unreal Engine 4.26  -> /opt/UnrealEngine_4.26  (UE4_ROOT)
#   - CARLA sources       -> /workspace/carla
ARG UBUNTU_DISTRO="22.04"
FROM ubuntu:${UBUNTU_DISTRO}

ARG UID="1000"
ARG GID="1000"
ARG USERNAME="carla"
ARG CODE_SERVER_VERSION="4.96.4"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    UE4_ROOT=/opt/UnrealEngine_4.26 \
    ARTIFACT_DIR=/artifacts

# Toolchain, see Docs/build_linux.md; the rest is needed by UE4 and the examples.
RUN packages='build-essential g++-12 cmake ninja-build libvulkan1 vulkan-tools python3 python3-dev python3-pip python3-venv python-is-python3 \
      autoconf wget curl rsync unzip zstd git git-lfs openssh-client ca-certificates sudo gdb clangd \
      libpng-dev libtiff5-dev libjpeg-dev libxml2-dev libsdl2-dev libsdl2-2.0-0 fontconfig xdg-user-dirs \
      libxcb1 libxrandr2 libxi6 libxcursor1 libxinerama1 libgl1 libnss3 libasound2 less nano jq' && \
    apt-get update && \
    apt-get install -y --no-install-recommends $packages && \
    rm -rf /var/lib/apt/lists/* && \
    git lfs install --system

# Non-root user: the Unreal Editor and its build tools refuse to run as root.
RUN (getent group ${GID} >/dev/null || groupadd -g ${GID} ${USERNAME}) && \
    useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && \
    mkdir -p /workspace /artifacts /opt/UnrealEngine_4.26 /opt/wheelhouse /opt/offline-cache && \
    chown ${UID}:${GID} /workspace /artifacts /opt/wheelhouse /opt/offline-cache

# Python build requirements, also kept as a wheelhouse for pip without index.
COPY requirements.txt /tmp/requirements.txt
RUN pip3 download -r /tmp/requirements.txt -d /opt/wheelhouse && \
    pip3 install --no-index --find-links /opt/wheelhouse -r /tmp/requirements.txt && \
    chown -R ${UID}:${GID} /opt/wheelhouse

# Web VS Code
RUN curl -fL -o /tmp/cs.deb https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_amd64.deb && \
    dpkg -i /tmp/cs.deb && rm /tmp/cs.deb

COPY extensions.txt /tmp/extensions.txt
USER ${USERNAME}
# Open VSX is the extension registry of code-server; a missing one must not fail the image.
RUN while read -r ext; do \
      case "$ext" in ''|'#'*) continue ;; esac; \
      code-server --install-extension "$ext" || echo "WARNING: extension $ext not installed"; \
    done < /tmp/extensions.txt
USER root

COPY bin/ /usr/local/bin/
COPY artifact-server.py /usr/local/lib/artifact-server.py
COPY entrypoint.sh /usr/local/bin/carla-entrypoint
COPY settings.json /opt/code-server-settings.json
RUN chmod +x /usr/local/bin/* /usr/local/lib/artifact-server.py && ln -s /usr/local/lib/artifact-server.py /usr/local/bin/artifact-server

USER ${USERNAME}
ENV HOME=/home/${USERNAME}
WORKDIR /workspace/carla
EXPOSE 8080 8081 2000 2001 2002
ENTRYPOINT ["/usr/local/bin/carla-entrypoint"]
CMD ["serve"]
