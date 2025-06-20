#!/bin/bash

set -exuo pipefail


# Function to remove the directory on exit
cleanup() {
    echo "Cleaning up: microshift"
    rm -rf microshift
}

# Trap EXIT and INT signals to ensure cleanup
trap cleanup EXIT INT

# Detect the system architecture
ARCH=$(uname -m)

# Map system architectures to container image architectures
case "$ARCH" in
  "x86_64")
    ARCH="amd64"
    REPO="registry.ci.openshift.org/origin/release-scos"
    ;;
  "aarch64")
    ARCH="arm64"
    REPO="quay.io/okd-arm/okd-arm-release"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

# Variables
# Get the version from https://amd64.origin.releases.ci.openshift.org/
OKD_VERSION=${OKD_VERSION:-4.19.0-okd-scos.3}
IMAGE_NAME="quay.io/minc-org/minc"
IMAGE_ARCH_TAG="${IMAGE_NAME}:${OKD_VERSION}-${ARCH}"
CONTAINERFILE="microshift-okd-multi-build.Containerfile"
RELEASE_BRANCH="release-4.19"


# check if image already exist
if skopeo --override-os="linux" --override-arch="${ARCH}" inspect --format "Digest: {{.Digest}}" docker://${IMAGE_ARCH_TAG}; then
   echo "${IMAGE_ARCH_TAG} already exist"
   exit 0
fi

echo "Building image for architecture: $ARCH using repository: $REPO"

git clone https://github.com/microshift-io/microshift
pushd microshift

echo "Embed storage.conf and dns.conf to $CONTAINERFILE"
cp ../storage.conf ../00-dns.yaml .
sed -i '/^FROM quay.io\/centos-bootc\/centos-bootc:stream9[[:space:]]*$/s|FROM quay.io/centos-bootc/centos-bootc:stream9|FROM quay.io/centos/centos:stream9|' $CONTAINERFILE
sed -i '$a COPY storage.conf /etc/containers/storage.conf\nCOPY 00-dns.yaml /etc/microshift/config.d/00-dns.yaml' $CONTAINERFILE
sed -i '$a STOPSIGNAL SIGRTMIN+3\nCMD ["/sbin/init"]' $CONTAINERFILE

# Build the image
sudo podman build \
  --build-arg OKD_REPO="$REPO" \
  --build-arg USHIFT_BRANCH="$RELEASE_BRANCH" \
  --build-arg OKD_VERSION_TAG="$OKD_VERSION" \
  --env WITH_FLANNEL=1 \
  --env EMBED_CONTAINER_IMAGES=1 \
  --file "$CONTAINERFILE" \
  --tag "$IMAGE_ARCH_TAG" \
  .

# Push the image
echo "Pushing image: $IMAGE_ARCH_TAG"
sudo podman push "$IMAGE_ARCH_TAG"
popd
