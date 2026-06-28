#!/usr/bin/env bash
set -euo pipefail

prepare_rpm_repo_dependencies() {
  if [[ "$DISTRO" = "oracle8" ]]; then
    dnf config-manager --set-enabled ol8_codeready_builder
    dnf install -y oracle-epel-release-el8
  elif [[ "${DISTRO}" == "oracle9" ]]; then
    dnf config-manager --set-enabled ol9_codeready_builder
    dnf install -y oracle-epel-release-el9
  fi
}

echo "Install KasmVNC server"
BUILD_ARCH=$(uname -m)
UBUNTU_CODENAME=""
COMMIT_ID="d9b4772680641bd7b122519bdfdcdc4b3b264d8f"
BRANCH="master" # just use 'release' for a release branch
KASMVNC_VER="1.4.1"
COMMIT_ID_SHORT=$(echo "${COMMIT_ID}" | cut -c1-6)

# Naming scheme is now different between an official release and feature branch
KASM_VER_NAME_PART="${KASMVNC_VER}_${BRANCH}_${COMMIT_ID_SHORT}"
if [[ "${BRANCH}" == "release" ]] ; then
  KASM_VER_NAME_PART="${KASMVNC_VER}"
fi

if [ "${DISTRO}" == "kali" ]  ;
then
    apt-get update
    apt-get install -y sgml-base
    if [[ "$(arch)" =~ ^x86_64$ ]] ; then
        BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_kali-rolling_${KASM_VER_NAME_PART}_amd64.deb"
    else
        BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_kali-rolling_${KASM_VER_NAME_PART}_arm64.deb"
    fi
elif [[ "${DISTRO}" == @(rockylinux8|oracle8|almalinux8) ]] ; then
    if [[ "$(arch)" =~ ^x86_64$ ]] ; then
        BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_oracle_8_${KASM_VER_NAME_PART}_x86_64.rpm"
    else
        BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_oracle_8_${KASM_VER_NAME_PART}_aarch64.rpm"
    fi
elif [[ "${DISTRO}" == @(rockylinux9|oracle9|rhel9|almalinux9) ]] ; then
    if [[ "$(arch)" =~ ^x86_64$ ]] ; then
        BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_oracle_9_${KASM_VER_NAME_PART}_x86_64.rpm"
    else
        BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_oracle_9_${KASM_VER_NAME_PART}_aarch64.rpm"
    fi
elif [[ "${DISTRO}" == "opensuse" ]] ; then
    if grep -q "16" /etc/os-release;then
        if [[ "$(arch)" =~ ^x86_64$ ]] ; then
            BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_opensuse_16_${KASM_VER_NAME_PART}_x86_64.rpm"
        else
            BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_opensuse_16_${KASM_VER_NAME_PART}_aarch64.rpm"
        fi
    fi
elif [[ "${DISTRO}" == "fedora42" ]] ; then
    if [[ "$(arch)" =~ ^x86_64$ ]] ; then
        BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_fedora_42_${KASM_VER_NAME_PART}_x86_64.rpm"
    else
        BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_fedora_42_${KASM_VER_NAME_PART}_aarch64.rpm"
    fi
elif [[ "${DISTRO}" == "fedora43" ]] ; then
    if [[ "$(arch)" =~ ^x86_64$ ]] ; then
        BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_fedora_43_${KASM_VER_NAME_PART}_x86_64.rpm"
    else
        BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_fedora_43_${KASM_VER_NAME_PART}_aarch64.rpm"
    fi
elif [[ "${DISTRO}" = @(debian|parrotos7) ]] ; then
    if grep -q trixie /etc/os-release || grep -qi echo /etc/os-release; then
        if [[ "$(arch)" =~ ^x86_64$ ]] ; then
            BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_trixie_${KASM_VER_NAME_PART}_amd64.deb"
        else
            BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_trixie_${KASM_VER_NAME_PART}_arm64.deb"
        fi
    elif grep -q bookworm /etc/os-release || grep -q lory /etc/os-release; then
        if [[ "$(arch)" =~ ^x86_64$ ]] ; then
            BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_bookworm_${KASM_VER_NAME_PART}_amd64.deb"
        else
            BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_bookworm_${KASM_VER_NAME_PART}_arm64.deb"
        fi
    else
        if [[ "$(arch)" =~ ^x86_64$ ]] ; then
            BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_bullseye_${KASM_VER_NAME_PART}_amd64.deb"
        else
            BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_bullseye_${KASM_VER_NAME_PART}_arm64.deb"
        fi
    fi
elif [[ "${DISTRO}" == "alpine" ]] ; then
    if grep -q v3.23 /etc/os-release; then
        if [[ "$(arch)" =~ ^x86_64$ ]] ; then
            BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_alpine_323_${KASM_VER_NAME_PART}_x86_64.apk"
        else
            BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_alpine_323_${KASM_VER_NAME_PART}_aarch64.apk"
        fi
    elif grep -q v3.22 /etc/os-release; then
        if [[ "$(arch)" =~ ^x86_64$ ]] ; then
            BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_alpine_322_${KASM_VER_NAME_PART}_x86_64.apk"
        else
            BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_alpine_322_${KASM_VER_NAME_PART}_aarch64.apk"
        fi
    elif grep -q v3.21 /etc/os-release; then
        if [[ "$(arch)" =~ ^x86_64$ ]] ; then
            BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_alpine_321_${KASM_VER_NAME_PART}_x86_64.apk"
        else
            BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_alpine_321_${KASM_VER_NAME_PART}_aarch64.apk"
        fi
    fi
else
    UBUNTU_CODENAME=$(grep -Po -m 1 "(?<=_CODENAME=)\w+" /etc/os-release)
    if [[ "${BUILD_ARCH}" =~ ^aarch64$ ]] ; then
        BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_${UBUNTU_CODENAME}_${KASM_VER_NAME_PART}_arm64.deb"
    else
        BUILD_URL="https://kasmweb-build-artifacts.s3.amazonaws.com/kasmvnc/${COMMIT_ID}/kasmvncserver_${UBUNTU_CODENAME}_${KASM_VER_NAME_PART}_amd64.deb"
    fi
fi

KASMVNC_CACHE_DIR="${KASMVNC_CACHE_DIR:-/var/cache/dockypody/kasmvnc}"
KASMVNC_CACHE_KEY_DIR="${KASMVNC_CACHE_DIR}/${COMMIT_ID}"

mkdir -p "${KASMVNC_CACHE_KEY_DIR}"


prepare_rpm_repo_dependencies
if [[ -z "${BUILD_URL:-}" ]]; then
  echo "BUILD_URL not set for DISTRO=${DISTRO} BUILD_ARCH=${BUILD_ARCH}" >&2
  exit 1
fi
ARTIFACT_BASENAME="$(basename "${BUILD_URL}")"
ARTIFACT_PATH="${KASMVNC_CACHE_KEY_DIR}/${ARTIFACT_BASENAME}"

validate_cached_artifact() {
    case "${ARTIFACT_PATH}" in
        *.deb)
            dpkg-deb --info "${ARTIFACT_PATH}" >/dev/null 2>&1
            ;;
        *.rpm)
            rpm -qp "${ARTIFACT_PATH}" >/dev/null 2>&1
            ;;
        *.apk)
            tar -tzf "${ARTIFACT_PATH}" >/dev/null 2>&1 || tar -tf "${ARTIFACT_PATH}" >/dev/null 2>&1
            ;;
        *)
            return 0
            ;;
    esac
}

if [ -s "${ARTIFACT_PATH}" ] && ! validate_cached_artifact; then
    rm -f "${ARTIFACT_PATH}"
fi

if [ ! -s "${ARTIFACT_PATH}" ]; then
    tmp="${ARTIFACT_PATH}.part.$$"
    trap 'rm -f "${tmp}"' EXIT
    rm -f "${tmp}"
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 30 --max-time 600 -o "${tmp}" "${BUILD_URL}"
    mv "${tmp}" "${ARTIFACT_PATH}"
    trap - EXIT
fi

if [[ "${DISTRO}" == @(oracle8|oracle9|rhel9|rockylinux9|rockylinux8|almalinux8|almalinux9) ]] ; then
    dnf localinstall -y "${ARTIFACT_PATH}"
    dnf install -y mesa-dri-drivers
elif [[ "${DISTRO}" == @(fedora42|fedora43) ]] ; then
    dnf install -y xorg-x11-drv-amdgpu xorg-x11-drv-ati
    if [ "${BUILD_ARCH}" == "x86_64" ]; then
        dnf install -y xorg-x11-drv-intel
    fi
    if [[ "${DISTRO}" == @(fedora42|fedora43) ]] ; then
        dnf-3 localinstall -y --allowerasing "${ARTIFACT_PATH}"
        dnf install -y crypto-policies-scripts
        update-crypto-policies --set DEFAULT:SHA1
    else
        dnf localinstall -y --allowerasing "${ARTIFACT_PATH}"
    fi
    dnf install -y mesa-dri-drivers
elif [[ "${DISTRO}" == "opensuse" ]] ; then
    mkdir -p /etc/pki/tls/private
    zypper install -y \
        libdrm_amdgpu1 \
	libdrm_radeon1
    if [ "${BUILD_ARCH}" == "x86_64" ]; then
        zypper install -y libdrm_intel1
    fi
    zypper install -y --allow-unsigned-rpm "${ARTIFACT_PATH}"
elif [[ "${DISTRO}" == "alpine" ]] ; then
    apk add --no-cache \
        libgomp \
        libjpeg-turbo \
        libwebp \
        libxfont2 \
        libxshmfence \
        mesa-gbm \
        pciutils-libs \
        perl \
        perl-datetime \
        perl-hash-merge-simple \
        perl-list-moreutils \
        perl-switch \
        perl-try-tiny \
        perl-yaml-tiny \
        perl-datetime \
        perl-datetime-timezone \
        pixman \
        py3-xdg \
        setxkbmap \
        xauth \
        xf86-video-amdgpu \
        xf86-video-ati \
        xf86-video-nouveau \
        xkbcomp \
        xkeyboard-config \
        xterm
    if [ "${BUILD_ARCH}" == "x86_64" ]; then
        apk add --no-cache xf86-video-intel
        apk add --no-cache mesa-vulkan-intel
    fi
    apk add --no-cache --allow-untrusted "${ARTIFACT_PATH}"
    ln -s /usr/local/share/kasmvnc /usr/share/kasmvnc
    ln -s /usr/local/etc/kasmvnc /etc/kasmvnc
    ln -s /usr/local/lib/kasmvnc /usr/lib/kasmvncserver
else
    apt-get update
    apt-get install -y gettext libavformat-dev libswscale-dev libxfont2 ssl-cert
    apt-get install -y "${ARTIFACT_PATH}"
fi
mkdir -p $KASM_VNC_PATH/www/Downloads
chown -R 0:0 $KASM_VNC_PATH
chmod -R og-w $KASM_VNC_PATH
ln -sf /home/ocm-user/Downloads $KASM_VNC_PATH/www/Downloads/Downloads
chown -R 1000:0 $KASM_VNC_PATH/www/Downloads
