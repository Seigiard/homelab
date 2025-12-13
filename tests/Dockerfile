FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TEST_MODE=1
ENV TERM=xterm

# Create test user with sudo (no password)
RUN apt-get update \
    && apt-get install -y sudo git curl \
    && useradd -m -s /bin/bash testuser \
    && echo "testuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Mock systemd commands (no systemd in Docker)
COPY tests/mocks/systemctl /usr/local/bin/systemctl
COPY tests/mocks/hostnamectl /usr/local/bin/hostnamectl
RUN chmod +x /usr/local/bin/systemctl /usr/local/bin/hostnamectl

USER testuser
WORKDIR /home/testuser

# Copy project
COPY --chown=testuser:testuser . /opt/homelab

# Create symlink like setup.sh would
RUN ln -s /opt/homelab ~/homelab

CMD ["/opt/homelab/scripts/setup/--init.sh"]
