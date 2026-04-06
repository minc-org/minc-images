#!/bin/bash

set -exuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cleanup() {
    echo "Cleaning up: microshift"
    rm -rf microshift
}

trap cleanup EXIT INT

# Detect the system architecture
ARCH=$(uname -m)

case "$ARCH" in
  "x86_64")
    ARCH="amd64"
    ;;
  "aarch64")
    ARCH="arm64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

OKD_VERSION=${OKD_VERSION:-4.22.0-okd-scos.ec.10}
IMAGE_NAME="quay.io/minc-org/minc"
IMAGE_ARCH_TAG="${IMAGE_NAME}:${OKD_VERSION}-${ARCH}"
CONTAINERFILE="packaging/bootc.Containerfile"

if skopeo --override-os="linux" --override-arch="${ARCH}" inspect --format "Digest: {{.Digest}}" "docker://${IMAGE_ARCH_TAG}"; then
   echo "${IMAGE_ARCH_TAG} already exist"
   exit 0
fi

echo "Building image for architecture: $ARCH"

git clone https://github.com/microshift-io/microshift
pushd microshift

# Copy minc-specific config files into the repo for the Containerfile COPY context
cp "${SCRIPT_DIR}/storage.conf" "${SCRIPT_DIR}/00-dns.yaml" .

# Patch the bootc Containerfile for minc (running as a regular container, not bootc)
sed -i 's|^ARG BOOTC_IMAGE_URL=.*|ARG BOOTC_IMAGE_URL=quay.io/centos/centos|' "${CONTAINERFILE}"
sed -i 's|^ARG BOOTC_IMAGE_TAG=.*|ARG BOOTC_IMAGE_TAG=stream9|' "${CONTAINERFILE}"
sed -i '$a COPY storage.conf /etc/containers/storage.conf\nCOPY 00-dns.yaml /etc/microshift/config.d/00-dns.yaml' "${CONTAINERFILE}"
sed -i '$a STOPSIGNAL SIGRTMIN+3\nCMD ["/sbin/init"]' "${CONTAINERFILE}"

# Build MicroShift RPMs using the upstream Makefile pipeline
sudo -E make rpm 

# Build the bootc container image with minc-specific overrides
sudo -E make image \
  BOOTC_IMAGE_URL="quay.io/centos/centos" \
  BOOTC_IMAGE_TAG="stream9" \
  WITH_TOPOLVM=0 \
  WITH_KINDNET=1 \
  WITH_OLM=1 \
  EMBED_CONTAINER_IMAGES=1

# Tag and push the resulting image
sudo podman tag microshift-okd "${IMAGE_ARCH_TAG}"
echo "Pushing image: ${IMAGE_ARCH_TAG}"
sudo podman push "${IMAGE_ARCH_TAG}"
popd
