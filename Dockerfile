FROM debian:bookworm-slim

# Install base deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git jq openssh-server rsync tmux xxd \
    && rm -rf /var/lib/apt/lists/*

# Install opencode
RUN curl -fsSL https://opencode.ai/install | bash -s -- --prefix /usr/local

# Copy looper scripts
COPY .opencode/scripts /home/ubuntu/.opencode/scripts
COPY .opencode/agents /home/ubuntu/.opencode/agents

# Set working directory
WORKDIR /home/ubuntu

# Default command
CMD ["/bin/bash"]