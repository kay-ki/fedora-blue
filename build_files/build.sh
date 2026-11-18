#!/bin/bash

set -ouex pipefail

PKGS=/ctx/packages.json

cp -avf /ctx/system_files/. /
install -Dm644 /ctx/cosign.pub /usr/lib/pki/containers/fedora-blue.pub

dnf5 -y install jq

for repo in $(jq -r '.repos[]' "$PKGS"); do
    cp "/ctx/repos/${repo}.repo" "/etc/yum.repos.d/fedora-blue-${repo}.repo"
done
for copr in $(jq -r '.coprs[]' "$PKGS"); do
    dnf5 -y copr enable "$copr"
done

mapfile -t remove < <(jq -r '.remove[]' "$PKGS")
dnf5 -y remove "${remove[@]}"

mkdir -p /var/opt
mapfile -t install < <(jq -r '.install[]' "$PKGS")
dnf5 -y install --exclude="$(jq -r '.exclude | join(",")' "$PKGS")" "${install[@]}"

KVER=$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | tail -1)
dnf5 -y install "kernel-devel-${KVER}"
test -d "/usr/src/kernels/${KVER}"

for kmod in $(jq -r '.kmods[]' "$PKGS"); do
    cp -a "/ctx/kmods/${kmod}" "/tmp/${kmod}"
    make -C "/tmp/${kmod}" -j"$(nproc)" KVER="${KVER}" KSRC="/usr/src/kernels/${KVER}"
    install -Dm644 "/tmp/${kmod}/${kmod}.ko" "/usr/lib/modules/${KVER}/extra/${kmod}.ko"
    echo "${kmod}" > "/usr/lib/modules-load.d/${kmod}.conf"
done
depmod -a "${KVER}"
modinfo -k "${KVER}" $(jq -r '.kmods[]' "$PKGS") > /dev/null

# RPMs writing to /opt land in /var/opt, which bootc does not ship; move them into /usr and link back
mkdir -p /usr/lib/opt
: > /usr/lib/tmpfiles.d/fedora-blue-opt.conf
while IFS= read -r dir; do
    mv "/var/opt/${dir}" "/usr/lib/opt/${dir}"
    echo "L+ \"/var/opt/${dir}\" - - - - /usr/lib/opt/${dir}" >>/usr/lib/tmpfiles.d/fedora-blue-opt.conf
done < <(jq -r '.opt[]' "$PKGS")

for repo in $(jq -r '.repos[]' "$PKGS"); do
    rm "/etc/yum.repos.d/fedora-blue-${repo}.repo"
done
for copr in $(jq -r '.coprs[]' "$PKGS"); do
    dnf5 -y copr disable "$copr"
done

for svc in $(jq -r '.services[]' "$PKGS"); do
    systemctl enable "$svc"
done
for svc in $(jq -r '.user_services[]' "$PKGS"); do
    systemctl --global enable "$svc"
done

jq '.transports.docker["ghcr.io/kay-ki/fedora-blue"] = [{"type": "sigstoreSigned", "keyPath": "/usr/lib/pki/containers/fedora-blue.pub", "signedIdentity": {"type": "matchRepository"}}]' \
    /etc/containers/policy.json > /tmp/policy.json
mv /tmp/policy.json /etc/containers/policy.json

for f in $(jq -r '.required[]' "$PKGS"); do
    test -x "$f"
done

dnf5 clean all
