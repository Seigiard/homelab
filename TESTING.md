# Testing

Scripts are tested in a Docker container with Ubuntu 22.04.

## Running Tests

```bash
# Build (with cache - fast, only changed files rebuild)
docker build -t homelab-test -f tests/Dockerfile .

# Build without cache (full rebuild)
docker build --no-cache -t homelab-test -f tests/Dockerfile .

# Run test
docker run --rm homelab-test

# Test single script
docker run --rm homelab-test /opt/homelab/scripts/setup/02-setup-zsh.sh

# Interactive mode
docker run -it --rm homelab-test bash
```

## TEST_MODE

In Docker, `TEST_MODE=1` is set, which:
- Skips interactive prompts (`press_enter`)
- Skips GitHub operations (SSH test)
- Skips Docker daemon operations (network create)
- Skips firewall configuration (UFW)

## Mocks

Docker doesn't have systemd, so stubs are used:
- `tests/mocks/systemctl` - emulates systemctl
- `tests/mocks/hostnamectl` - emulates hostnamectl

## Verification

Each script verifies its own result:

| Script | What's verified |
|--------|-----------------|
| 01-install-packages | `dpkg -s` for each package |
| 02-setup-zsh | `getent passwd` to check shell |
| 04-setup-avahi | `hostname` after setup |
| 05-apply-dotfiles | `readlink` for symlinks |
| 07-setup-ssh-key | Key files exist |
