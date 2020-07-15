#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Ideas heavily borrowed from:
# https://github.com/irvingpop/packer-chef-highperf-centos-ami/tree/centos8/create_base_ami
# https://github.com/plus3it/AMIgen7


################################################################################

ROOTFS=/rootfs
DEVICE="/dev/sdf"

arch="$( uname --machine )"

################################################################################

# Update builder system
dnf -y update

# Install missing packages for building
dnf -y install expect podman python2

################################################################################

# Download and install ebsnvme-id and ec2-metadata from the Amazon Linux 2 AMI.
# This is optional.

mkdir /tmp/tmp.ec2utils

cat <<'EOS' | podman run --rm -v '/tmp/tmp.ec2utils:/work:Z' --workdir='/work' -i 'docker.io/library/amazonlinux:2'
yum -y install yum-utils

mkdir -pv etc/udev/rules.d sbin usr/bin

# /etc/udev/rules.d/ comes from the systemd package, am2 uses v219
rpm2cpio "$( yumdownloader --enablerepo=amzn2-core --urls ec2-utils | grep -E '^https' | sort --field-separator='/' --key=6 --version-sort | tail -1 )" | cpio --quiet --extract --to-stdout ./etc/udev/rules.d/70-ec2-nvme-devices.rules > etc/udev/rules.d/70-ec2-nvme-devices.rules
chmod -c 0644 etc/udev/rules.d/70-ec2-nvme-devices.rules

# requires python2.7 in the $PATH
rpm2cpio "$( yumdownloader --enablerepo=amzn2-core --urls ec2-utils | grep -E '^https' | sort --field-separator='/' --key=6 --version-sort | tail -1 )" | cpio --quiet --extract --to-stdout ./sbin/ebsnvme-id > sbin/ebsnvme-id
chmod -c 0755 sbin/ebsnvme-id

# requires curl
rpm2cpio "$( yumdownloader --enablerepo=amzn2-core --urls ec2-utils | grep -E '^https' | sort --field-separator='/' --key=6 --version-sort | tail -1 )" | cpio --quiet --extract --to-stdout ./usr/bin/ec2-metadata > usr/bin/ec2-metadata
chmod -c 0755 usr/bin/ec2-metadata
EOS

mv -v /tmp/tmp.ec2utils/etc/udev/rules.d/70-ec2-nvme-devices.rules /etc/udev/rules.d/70-ec2-nvme-devices.rules
mv -v /tmp/tmp.ec2utils/sbin/ebsnvme-id /sbin/ebsnvme-id
mv -v /tmp/tmp.ec2utils/usr/bin/ec2-metadata /usr/bin/ec2-metadata

rm -rvf /tmp/tmp.ec2utils

udevadm control --reload-rules
udevadm trigger

# Wait for udev to create symlink for secondary disk
while [[ ! -e "$DEVICE" ]]; do sleep 1; done

# Read-only/print command
ls -ld /dev/sd* /dev/nvme*

################################################################################

# Use the same partitioning as the RHEL8 AMI

  parted --script "$DEVICE" -- \
    mklabel gpt \
    mkpart primary fat32 1 201MiB \
    mkpart primary xfs 201MiB 713MiB \
    mkpart primary xfs 713MiB -1 \
    set 1 esp on

  # With gpt disks, "primary" becomes the partition label, so we change or remove with the name command
  env DEVICE="$DEVICE" expect <<'EOS'
  set device $env(DEVICE)

  spawn parted "$device"

  expect "(parted) "
  send "name 1 'EFI System Partition'\r"

  expect "(parted) "
  send "name 2\r"
  expect "Partition name? "
  send "''\r"

  expect "(parted) "
  send "name 3\r"
  expect "Partition name? "
  send "''\r"

  expect "(parted) "
  send "quit\r"

  expect eof
EOS

  # Set the main partition as a variable
  PARTITION="${DEVICE}3"

  # Wait for device partition creation
  while [[ ! -e "${DEVICE}2" ]]; do sleep 1; done

  # /boot
  mkfs.xfs -f "${DEVICE}2"
  # /boot/efi
  mkfs.fat -F 16 "${DEVICE}1"



# Wait for device partition creation
while [[ ! -e "$PARTITION" ]]; do sleep 1; done

# /
mkfs.xfs -f "$PARTITION"

# Read-only/print commands
ls -ld /dev/sd* /dev/nvme*
parted "$DEVICE" print
fdisk -l "$DEVICE"

################################################################################

# Chroot Mount /
mkdir -p "$ROOTFS"
mount "$PARTITION" "$ROOTFS"


# Chroot Mount /boot
mkdir -p "$ROOTFS/boot"
mount "${DEVICE}2" "$ROOTFS/boot"

# Chroot Mount /boot/efi
mkdir -p "$ROOTFS/boot/efi"
mount "${DEVICE}1" "$ROOTFS/boot/efi"


# Special filesystems
mkdir -p "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys"
mount -o bind          /dev     "$ROOTFS/dev"
mount -t devpts        devpts   "$ROOTFS/dev/pts"
mount --types tmpfs    tmpfs    "$ROOTFS/dev/shm"
mount --types proc     proc     "$ROOTFS/proc"
mount --types sysfs    sysfs    "$ROOTFS/sys"
mount --types selinuxfs selinuxfs "$ROOTFS/sys/fs/selinux"

################################################################################

# Grab the latest release and repos packages.
release_pkg_latest="$( curl --silent https://mirrors.edge.kernel.org/centos/8/BaseOS/$arch/os/Packages/ | grep --only-matching 'centos-release-8[^"]*.rpm' | sort --unique --version-sort | tail -1 )"
release_pkg_url="https://mirrors.edge.kernel.org/centos/8/BaseOS/$arch/os/Packages/$release_pkg_latest"

repos_pkg_latest="$( curl --silent https://mirrors.edge.kernel.org/centos/8/BaseOS/$arch/os/Packages/ | grep --only-matching 'centos-repos-8[^"]*.rpm' | sort --unique --version-sort | tail -1 )"
repos_pkg_url="https://mirrors.edge.kernel.org/centos/8/BaseOS/$arch/os/Packages/$repos_pkg_latest"

rpm --root="$ROOTFS" --initdb

rpm --root="$ROOTFS" --nodeps -ivh "$release_pkg_url"
rpm --root="$ROOTFS" --nodeps -ivh "$repos_pkg_url"

# Note: using "--nogpgcheck" so users of the resulting AMI still need to confirm GPG key usage

dnf --installroot="$ROOTFS" --nogpgcheck -y update

# Similar to RHEL8
cat > "${ROOTFS}/etc/fstab" <<EOF

#
# /etc/fstab
#
# Accessible filesystems, by reference, are maintained under '/dev/disk/'.
# See man pages fstab(5), findfs(8), mount(8) and/or blkid(8) for more info.
#
# After editing this file, run 'systemctl daemon-reload' to update systemd
# units generated from this file.
#
UUID=$( lsblk "$PARTITION" --noheadings --output uuid ) /                       xfs     defaults        0 0
EOF


  cat >> "${ROOTFS}/etc/fstab" <<EOF
UUID=$( lsblk "${DEVICE}2" --noheadings --output uuid ) /boot                   xfs     defaults        0 0
UUID=$( lsblk "${DEVICE}1" --noheadings --output uuid )          /boot/efi               vfat    defaults,uid=0,gid=0,umask=077,shortname=winnt 0 2
EOF


# Copy from RHEL8
mkdir "${ROOTFS}/etc/default"
cp -av /etc/default/grub "${ROOTFS}/etc/default/grub"

# Refer to https://github.com/CentOS/sig-cloud-instance-build/blob/master/cloudimg/CentOS-7-x86_64-hvm.ks
# for rationale for most excludes and removes.

ARM_PKGS=()

  ARM_PKGS+=('efibootmgr' 'shim')


set +u
dnf --installroot="$ROOTFS" --nogpgcheck -y install \
  --exclude="iwl*firmware" \
  --exclude="libertas*firmware" \
  --exclude="plymouth*" \
  "@Minimal Install" \
  centos-gpg-keys \
  cloud-init \
  cloud-utils-growpart \
  dracut-config-generic \
  grub2 \
  kernel \
  python2 \
  yum-utils \
  "${ARM_PKGS[@]}"
set -u

dnf --installroot="$ROOTFS" -C -y remove firewalld --setopt="clean_requirements_on_remove=1"

dnf --installroot="$ROOTFS" -C -y remove linux-firmware

# This is failing on the dependency "timedatex" having a cpio package problem, but chrony still installs
dnf --installroot="$ROOTFS" --nogpgcheck -y install chrony || true

################################################################################

# Run to complete bootloader setup and create /boot/grub2/grubenv

chroot "$ROOTFS" grub2-mkconfig -o /etc/grub2-efi.cfg


# Read-only/print command
chroot "$ROOTFS" grubby --default-kernel

################################################################################

# Other misc tasks from official CentOS 7 kickstart

sed -e '/^#NAutoVTs=.*/ a\
NAutoVTs=0' -i "$ROOTFS/etc/systemd/logind.conf"

sed -r -e 's/ec2-user/centos/g' -e 's/(groups: \[)(adm)/\1wheel, \2/' /etc/cloud/cloud.cfg > "$ROOTFS/etc/cloud/cloud.cfg"

chroot "$ROOTFS" systemctl enable sshd.service
chroot "$ROOTFS" systemctl enable cloud-init.service
chroot "$ROOTFS" systemctl enable chronyd.service
chroot "$ROOTFS" systemctl mask tmp.mount
chroot "$ROOTFS" systemctl set-default multi-user.target

cat > "$ROOTFS/etc/hosts" <<'EOF'
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF

touch "$ROOTFS/etc/resolv.conf"

echo 'RUN_FIRSTBOOT=NO' > "$ROOTFS/etc/sysconfig/firstboot"

cat > "$ROOTFS/etc/sysconfig/network" <<'EOF'
NETWORKING=yes
NOZEROCONF=yes
EOF

################################################################################

# Set up ebsnvme-id and ec2-metadata in the image. This is optional.

cp -av /etc/udev/rules.d/70-ec2-nvme-devices.rules "$ROOTFS/etc/udev/rules.d/"

cp -av /sbin/ebsnvme-id "$ROOTFS/sbin"

cp -av /usr/bin/ec2-metadata "$ROOTFS/usr/bin"

################################################################################

# Cleanup before creating AMI.

# SELinux, also cleans up /tmp
if ! getenforce | grep --quiet --extended-regexp '^Disabled$' ; then
  # Prevent relabel on boot (b/c next command will do it manually)
  rm --verbose --force "$ROOTFS"/.autorelabel

  # Manually "restore" SELinux contexts ("relabel" clears /tmp and then runs "restore"). Requires '/sys/fs/selinux' to be mounted in the chroot.
  chroot "$ROOTFS" /sbin/fixfiles -f -F relabel

  # Packages from https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html-single/using_selinux/index
  # that contain RPM scripts. Reinstall for the postinstall scriptlets.
  dnf --installroot="$ROOTFS" --nogpgcheck -y reinstall selinux-policy-targeted policycoreutils
fi

# Repo cleanup
dnf --installroot="$ROOTFS" --cacheonly --assumeyes clean all
rm --recursive --verbose "$ROOTFS"/var/cache/dnf/*

# Clean up systemd machine ID file
truncate --size=0 "$ROOTFS"/etc/machine-id
chmod --changes 0444 "$ROOTFS"/etc/machine-id

# Clean up /etc/resolv.conf
truncate --size=0 "$ROOTFS"/etc/resolv.conf

# Delete any logs
find "$ROOTFS"/var/log -type f -print -delete

# Cleanup cloud-init (https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)
rm --recursive --verbose "$ROOTFS"/var/lib/cloud/

# Clean up temporary directories
find "$ROOTFS"/run \! -type d -print -delete
find "$ROOTFS"/run -mindepth 1 -type d -empty -print -delete
find "$ROOTFS"/tmp \! -type d -print -delete
find "$ROOTFS"/tmp -mindepth 1 -type d -empty -print -delete
find "$ROOTFS"/var/tmp \! -type d -print -delete
find "$ROOTFS"/var/tmp -mindepth 1 -type d -empty -print -delete

################################################################################

# Don't /need/ this for packer because the instance is shut down before the volume is snapshotted, but it doesn't hurt...

umount --all-targets --recursive "$ROOTFS"

################################################################################

exit 0
