# !/bin/bash
#
# ------------------------------------------------------------------------------
#        /\        | Title: Tir3 Arch Linux - Installer                        |
#       /  \       |-----------------------------------------------------------|
#      /\   \      |     OS      | Arch Linux                                  |
#     /      \     | Description | Arch Linux system installation              |
#    /   ,,   \    |    Owner    | Tir3                                        |
#   /   |  |  -\   |   GitHub    | https://github.com/atirelli3                |
#  /_-''    ''-_\  |   Version   | 1.0.0                                       |
# ------------------------------------------------------------------------------

source "$1"  # Load configuration file

# Constants
[[ $target =~ ^/dev/nvme[0-9]+n[0-9]+$ ]] && target_part="${target}p" || target_part="$target"
BTRFS_SV_OPTS=$(IFS=,; echo "${btrfs_opts[*]}")   ## Btrfs mount options
LNX="linux-zen linux-zen-headers linux-firmware"  ## Base Linux packages
BASE="base base-devel git"                        ## Base system packages
CPU="${cpu}-ucode"                                ## CPU driver
BOOTLOADER="efibootmgr os-prober"                 ## Bootloader
NETWORK="networkmanager"                          ## Network manager
CRYPT="cryptsetup"                                ## Encryption
EXTRA="sudo"                                      ## Extra packages
DE=""                                             ## Desktop environment
GNOME_EXT=""                                      ## GNOME extensions
OFFICE="libreoffice-fresh"                        ## Office suite
OFFICE+=" libreoffice-extension-texmaths"
OFFICE+=" libreoffice-extension-writer2latex"

# Conditional package addition
[ "$encrypt" = "yes" ] && [ "$part2_fs" != "btrfs" ] && CRYPT+=" lvm2"
[ "$part2_fs" = "btrfs" ] && EXTRA+=" btrfs-progs"
[ "$bootldr" = "grub" ] && BOOTLOADER+=" grub"
[ "$bootldr" = "systemd-boot" ] && BOOTLOADER+=" systemd-boot"
USR_EXT_PKGS=$(IFS=" "; echo "${pkgs[*]}")         ## User extra packages
if [ "$de" = "gnome" ]; then
    ## GNOME core packages
    DE="
        gdm
        gnome-shell
        gnome-keybindings
        power-profiles-daemon
    "
    ## XDG-related packages
    DE+="
        xdg-user-dirs
        xdg-desktop-portal
        xdg-user-dirs-gtk
        xdg-desktop-portal-gnome
    "
    ## Authentication packages
    DE+="
        polkit
        polkit-gnome
        gnome-keyring
    "
    # Add Bluetooth package if enabled
    [ "$bluetooth" = "yes" ] && DE+=" gnome-bluetooth-3.0" 
    ## Base GNOME applications
    DE+="
        gnome-control-center
        gnome-tweaks
        mission-center
        extension-manager
        dconf-editor
    "
    ## Default GNOME applications
    DE+="
        nautilus
        blackbox-terminal
        firefox
        thunderbird
        gnome-calculator
        gnome-calendar
        gnome-text-editor
        gnome-disk-utility
        papers
        loupe
        clapper
    "
    ## GNOME Nautilus addons
    DE+="
        sushi
        libnautilus-extension
    "
    ## GNOME Nautilus plugins
    DE+="
        nautilus-open-any-terminal
        seahorse-nautilus
        turtle
        nautilus-open-in-code
    "
    ## GNOME extensions
    GNOME_EXT="
        gnome-shell-extensions
        gnome-shell-extension-blur-my-shell
        gnome-shell-extension-dash-to-dock
        gnome-shell-extension-just-perfection-desktop
        gnome-shell-extension-unite
        gnome-shell-extension-rounded-window-corners-reborn
        gnome-shell-extension-arc-menu
        gnome-shell-extension-alphabetical-grid-extension
        gnome-shell-extension-arch-update
        gnome-shell-extension-runcat
        gnome-shell-extension-extension-list
        gnome-shell-extension-clipboard-indicator
        gnome-shell-extension-top-bar-organizer
        gnome-shell-extension-bluetooth-quick-connect
        gnome-shell-extension-weather-oclock
        gnome-shell-extension-openweatherrefined
    "
fi

# elif [ "$de" = "kde" ]; then
#     : # W.I.P. (Work in progress)
# fi

# Utility functions
print_debug() { echo -e "\e[${1}m${2}\e[0m"; }
print_success() { print_debug "32" "$1"; }  # Green
print_info() { print_debug "36" "$1"; }     # Cyan
print_warning() { print_debug "33" "$1";}   # Yellow

# Check prerequisites => root privileges and system is in UEFI mode
[ "$EUID" -ne 0 ] && { echo "Please run as root. Aborting script."; exit 1; }
[ -d /sys/firmware/efi/efivars ] || { echo "UEFI mode not detected. Aborting script."; exit 1; }



# ------------------------------------------------------------------------------
#                                  Preparation
# ------------------------------------------------------------------------------
print_warning "[*] Preparing the machine for installation..."

print_info "    - loading keyboard layout"
loadkeys $keyboard                     # Set keyboard layout
print_info "    - enabling NTP"
timedatectl set-ntp true &> /dev/null  # Enable NTP for time synchronization
print_info "    - updating mirrorlist"
pacman -Syy &> /dev/null               # Refresh package manager database(s)
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup  # Backup current mirrorlist
# Search for better mirror(s)
reflector --country "${reflector_countries}" \
            --protocol https \
            --age 6 \
            --sort rate \
            --save /etc/pacman.d/mirrorlist &> /dev/null
print_info "    - configuring pacman"
# Enable colored output, fancy progress bar, verbose package lists, and parallel downloads (20)
sed -i "/etc/pacman.conf" \
    -e "s|^#Color|&\nColor\nILoveCandy|" \
    -e "s|^#VerbosePkgLists|&\nVerbosePkgLists|" \
    -e "s|^#ParallelDownloads.*|&\nParallelDownloads = 20|"
print_info "    - updating keyring(s)"
pacman -S --noconfirm archlinux-keyring &> /dev/null  # Download updated keyrings
pacman-key --init &> /dev/null                        # Initialize newer keyrings
pacman -Syy &> /dev/null                              # Refresh package manager database(s)

print_success "[+] The machine is ready for the installation!"



# ------------------------------------------------------------------------------
#                                Disk Formatting
# ------------------------------------------------------------------------------
print_warning "[*] Formatting the disk..."

print_info "    - unmounting all"
umount -A --recursive /mnt &> /dev/null          # Ensure everything is unmounted
print_info "    - wiping data"
# Wipe data(s)
wipefs -af "$target" &> /dev/null                # Wipe all data
sgdisk --zap-all --clear "$target" &> /dev/null  # Clear partition table
sgdisk -a 2048 -o "$target" &> /dev/null         # Align sectors to 2048
partprobe "$target" &> /dev/null                 # Inform system of disk changes
print_info "    - filling with rnd data(s)"
# Fill disk with random data for security
cryptsetup open --type plain --batch-mode -d /dev/urandom $target target &> /dev/null
dd if=/dev/zero of=/dev/mapper/target bs=1M status=progress oflag=direct &> /dev/null
cryptsetup close target
print_info "    - partitioning disk"
# Partition the target disk
sgdisk -n 0:0:+${part1_size} -t 0:ef00 -c 0:ESP $target &> /dev/null  # EFI partition
sgdisk -n 0:0:0 -t 0:8300 -c 0:rootfs $target &> /dev/null            # Root partition
partprobe "$target" &> /dev/null                                      # Inform system of disk changes
# (Optional) Encrypt the root partition
if [ "$encrypt" = "yes" ]; then
    print_info "    - encrypting disk"
    sgdisk -t 2:8309 $target &> /dev/null  # Set partition 2 type to LUKS
    partprobe "$target" &> /dev/null       # Inform system of disk changes
    # Encrypt root partition
    echo -n "$encrypt_key" | cryptsetup --type $encrypt_type -v -y --batch-mode luksFormat ${target_part}2 --key-file=- &> /dev/null
    echo -n "$encrypt_key" | cryptsetup open --perf-no_read_workqueue --perf-no_write_workqueue --persistent ${target_part}2 $encrypt_label --key-file=- &> /dev/null
    root_device="/dev/mapper/${encrypt_label}"  # Set root to encrypted partition
else
    root_device=${target_part}2                 # Set root to non-encrypted partition
fi

print_info "    - formatting partitions and mounting (EFI)"
mkfs.vfat -F32 -n $part1_label ${target_part}1 &> /dev/null  # Format the EFI partition

if [ "$part2_fs" = "btrfs" ]; then
    print_info "    - formatting partitions and mounting (root - btrfs)"
    mkfs.btrfs -L $part2_label $root_device &> /dev/null  # Format as Btrfs
    mount $root_device /mnt                               # Mount root
    print_info "    - creating Btrfs subvolumes"
    # Create Btrfs subvolumes
    btrfs subvolume create /mnt/@ &> /dev/null           # System subvolume
    btrfs subvolume create /mnt/@home &> /dev/null       # Home subvolume
    btrfs subvolume create /mnt/@snapshots &> /dev/null  # Snapshots subvolume
    btrfs subvolume create /mnt/@cache &> /dev/null      # Cache subvolume
    btrfs subvolume create /mnt/@log &> /dev/null        # Log subvolume
    btrfs subvolume create /mnt/@tmp &> /dev/null        # Temp subvolume
    # Create additional subvolumes
    for subvol in "${btrfs_subvols[@]}"; do
        btrfs subvolume create /mnt/@$subvol &> /dev/null
    done
    umount /mnt  # Unmount to remount with subvolume options
    print_info "    - mounting Btrfs subvolumes"
    # Remount with Btrfs subvolumes
    mount -o ${BTRFS_SV_OPTS},subvol=@ $root_device /mnt &> /dev/null
    mkdir -p /mnt/{home,.snapshots,var/cache,var/log,var/tmp} &> /dev/null
    mount -o ${BTRFS_SV_OPTS},subvol=@home $root_device /mnt/home
    mount -o ${BTRFS_SV_OPTS},subvol=@snapshots $root_device /mnt/.snapshots
    mount -o ${BTRFS_SV_OPTS},subvol=@cache $root_device /mnt/var/cache
    mount -o ${BTRFS_SV_OPTS},subvol=@log $root_device /mnt/var/log
    mount -o ${BTRFS_SV_OPTS},subvol=@tmp $root_device /mnt/var/tmp

    # Mount additional subvolumes
    for i in "${!btrfs_subvols[@]}"; do
        mkdir -p /mnt${btrfs_subvols_mount[$i]}
        mount -o ${BTRFS_SV_OPTS},subvol=@${btrfs_subvols[$i]} $root_device /mnt${btrfs_subvols_mount[$i]}
    done
else
    print_info "    - formatting partitions and mounting (root - ext4)"
    mkfs.ext4 -L $part2_label $root_device &> /dev/null  # Format as EXT4
    mount $root_device /mnt                              # Mount root
fi

mkdir -p /mnt/$part1_mount
mount ${target_part}1 /mnt/$part1_mount  # Mount EFI partition

print_success "[+] Disk formatting completed."



# ------------------------------------------------------------------------------
#                            Base System Installation
# ------------------------------------------------------------------------------
print_warning "[*] Installing the base system..."

print_info "    - installing base packages"
# Install base system packages
pacstrap /mnt $LNX $BASE $CPU $BOOTLOADER $NETWORK $CRYPT $EXTRA &> /dev/null
print_info "    - generating fstab"
genfstab -U -p /mnt >> /mnt/etc/fstab &> /dev/null  # Generate fstab file table

print_success "[+] Base system installation completed."


# Passaggio delle variabili dal file di configurazione all'interno del chroot
env hostname="$hostname" lang="$lang" timezone="$timezone" keyboard="$keyboard" \
extra_lang="${extra_lang[@]}" lc_time="$lc_time" rootpwd="$rootpwd" \
username="$username" password="$password" reflector_countries="$reflector_countries" \
is_ssd="$is_ssd" encrypt="$encrypt" part2_fs="$part2_fs" target_part="$target_part" \
encrypt_key="$encrypt_key" part1_mount="$part1_mount" bootldr="$bootldr" \
secure_boot="$secure_boot" gpu="$gpu" editor="$editor" USR_EXT_PKGS="$USR_EXT_PKGS" \
aur="$aur" ssh="$ssh" bluetooth="$bluetooth" printer="$printer" de="$de" \
arch-chroot /mnt /bin/bash <<"EOT"
# Utility functions
print_debug() { echo -e "\e[${1}m${2}\e[0m"; }
print_success() { print_debug "32" "$1"; }  # Green
print_info() { print_debug "36" "$1"; }     # Cyan
print_warning() { print_debug "33" "$1";}   # Yellow

# ------------------------------------------------------------------------------
#                              System Configuration
# ------------------------------------------------------------------------------
print_warning "[*] Configuring the system..."

print_info "    - setting system hostname"
echo "$hostname" > /etc/hostname  # Set system hostname
print_info "    - configuring /etc/hosts"
cat > /etc/hosts << EOF           # Configure /etc/hosts for local hostname resolution
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${hostname}.localdomain ${hostname}
EOF
print_info "    - setting system language and locale"
sed -i "s/^#\(${lang}\)/\1/" /etc/locale.gen  # Enable the desired primary locale in /etc/locale.gen
for locale in "${extra_lang[@]}"; do          # Enable additional locales, if any
  sed -i "s/^#\(${locale}\)/\1/" /etc/locale.gen
done
echo "LANG=${lang}" > /etc/locale.conf         # Set system language/locale
echo "LC_TIME=${lc_time}" >> /etc/locale.conf  # Set locale for time display
locale-gen &> /dev/null                        # Generate locale
print_info "    - setting system timezone and keyboard layout"
# Set system timezone and sync hardware clock
ln -sf /usr/share/zoneinfo/"$timezone" /etc/localtime &> /dev/null
hwclock --systohc &> /dev/null
echo "KEYMAP=${keyboard}" > /etc/vconsole.conf  # Set console keymap

print_success "[+] System configuration completed."



# ------------------------------------------------------------------------------
#                               User Configuration
# ------------------------------------------------------------------------------
print_warning "[*] Configuring system root user and local user ..."

print_info "    - setting root password"
echo "root:$rootpwd" | chpasswd &> /dev/null        # Set root password
print_info "    - creating new user"
# Add new user, assign to 'wheel' group, and set Bash as default shell
useradd -m -G wheel -s /bin/bash "$username" &> /dev/null
echo "$username:$password" | chpasswd &> /dev/null  # Set user password
print_info "    - configuring user group (wheel)"
# Enable sudo for 'wheel' group
sed -i "s/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/" /etc/sudoers &> /dev/null

print_success "[+] User(s) configuration completed!"



# ------------------------------------------------------------------------------
#                              Pacman Configuration
# ------------------------------------------------------------------------------
print_warning "[*] Configuring pacman..."

print_info "    - configuring pacman"
# Enable colored output, fancy progress bar, verbose package lists, and parallel downloads (20)
sed -i "/etc/pacman.conf" \
    -e "s|^#Color|&\nColor\nILoveCandy|" \
    -e "s|^#VerbosePkgLists|&\nVerbosePkgLists|" \
    -e "s|^#ParallelDownloads.*|&\nParallelDownloads = 20|"
print_info "    - configuring makepkg 'QoL'"
# Improve 'Makepkg' QoL
sed -i "/etc/makepkg.conf" \
    -e "s|^#BUILDDIR=.*|&\nBUILDDIR=/var/tmp/makepkg|" \
    -e "s|^PKGEXT.*|PKGEXT='.pkg.tar'|" \
    -e "s|^OPTIONS=.*|#&\nOPTIONS=(docs \!strip \!libtool \!staticlibs emptydirs zipman purge \!debug lto)|" \
    -e "s|-march=.* -mtune=generic|-march=native|" \
    -e "s|^#RUSTFLAGS=.*|&\nRUSTFLAGS=\"-C opt-level=2 -C target-cpu=native\"|" \
    -e "s|^#MAKEFLAGS=.*|&\nMAKEFLAGS=\"-j$(($(nproc --all)-1))\"|"
print_info "    - installing pacman utils and scripts"
pacman -S --noconfirm pacman-contrib &> /dev/null  # pacman utils & scripts
systemctl enable paccache.timer &> /dev/null       # Enable automatic cache cleaning (every week)
print_info "    - enabling multilib repository"
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf  # Enable multilib repository
pacman -Syy &> /dev/null                                  # Refresh package manager database(s)

print_success "[+] Pacman configuration completed."



# ------------------------------------------------------------------------------
#                          Base Services Configuration
# ------------------------------------------------------------------------------
print_warning "[*] Configuring base services..."

print_info "    - configuring network service"
# Network
systemctl enable NetworkManager.service &> /dev/null              # Enable 'NetworkManager'
systemctl enable NetworkManager-wait-online.service &> /dev/null  # Extra service
print_info "    - configuring mirrorlist"
# Mirror(s)
pacman -S --noconfirm reflector &> /dev/null                 # Install 'reflector'
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup  # Backup current mirrorlist
# Search for better mirror(s)
reflector --country "${reflector_countries}" \
            --protocol https \
            --age 6 \
            --sort rate \
            --save /etc/pacman.d/mirrorlist &> /dev/null
systemctl enable reflector.service &> /dev/null              # Enable 'reflector' 
systemctl enable reflector.timer &> /dev/null                # Periodic update
print_info "    - configuring firewall"
# Firewall
pacman -S --noconfirm nftables &> /dev/null  # Install 'nftables'
NFTABLES_CONF="/etc/nftables.conf"           # Configuration file
bash -c "cat << EOF > $NFTABLES_CONF
#!/usr/sbin/nft -f

table inet filter
delete table inet filter
table inet filter {
  chain input {
    type filter hook input priority filter
    policy drop

    ct state invalid drop comment 'drop invalid connections'
    ct state {established, related} accept comment 'allow established connections'
    iifname lo accept comment 'allow loopback'
    ip protocol icmp accept comment 'allow ICMP'
    meta l4proto ipv6-icmp accept comment 'allow ICMPv6'
    pkttype host limit rate 5/second counter reject with icmpx type admin-prohibited
    counter
  }

  chain forward {
    type filter hook forward priority filter
    policy drop
  }
}
EOF"
systemctl enable nftables &> /dev/null       # Enable 'nftables'
print_info "    - configuring kernel parameters"
# Kernel network parameters
SYSCTL_CONF="/etc/sysctl.d/90-network.conf"  # Configuration file
bash -c "cat << EOF > $SYSCTL_CONF
# Disable IP forwarding
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Enable SYN flood protection
net.ipv4.tcp_syncookies = 1

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Do not send ICMP redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
EOF"
sysctl --system &> /dev/null  # Apply sysctl settings
# SSDs
if [ "is_ssd" = "yes" ]; then
    print_info "    - configuring SSD optimizations"
    pacman -S --noconfirm util-linux &> /dev/null     # Install 'util-linux'
    systemctl enable --now fstrim.timer &> /dev/null  # Enable fstrim
fi

print_success "[+] Base services configuration completed!"



# ------------------------------------------------------------------------------
#                         Initial Ramdisk Configuration
# ------------------------------------------------------------------------------
print_warning "[*] Configuring initial ramdisk ..."

# Key decryption file (to prevent double asking of the passkey)
if [ "$encrypt" = "yes" ]; then
    print_info "    - configuring encryption keyfile"
    # Generate keyfile for LUKS encryption
    dd bs=512 count=4 iflag=fullblock if=/dev/random of=/key.bin &> /dev/null
    chmod 600 /key.bin &> /dev/null                                        # Restrict keyfile access
    cryptsetup luksAddKey "${target_part}2" /key.bin &> /dev/null          # Add keyfile to LUKS
    sed -i '/^FILES=/ s/)/ \/key.bin)/' /etc/mkinitcpio.conf &> /dev/null  # Add keyfile to mkinitcpio
    print_info "    - configuring mkinitcpio (w/ encryption)"
    if [ "$part2_fs" = "btrfs" ]; then
        # Hooks for encryption and btrfs
        sed -i '/^HOOKS=/ s/(.*)/(base udev keyboard autodetect microcode keymap consolefont modconf block encrypt btrfs filesystems fsck)/' /etc/mkinitcpio.conf &> /dev/null
    else
        # Hooks for encryption without btrfs
        sed -i '/^HOOKS=/ s/(.*)/(base udev keyboard autodetect microcode keymap consolefont modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf &> /dev/null
    fi
else
    print_info "    - configuring mkinitcpio"
    # Hooks without encryption
    if [ "$part2_fs" = "btrfs" ]; then
        sed -i '/^HOOKS=/ s/(.*)/(base udev keyboard autodetect microcode keymap consolefont modconf block btrfs filesystems fsck)/' /etc/mkinitcpio.conf &> /dev/null
    else
        sed -i '/^HOOKS=/ s/(.*)/(base udev keyboard autodetect microcode keymap consolefont modconf block filesystems fsck)/' /etc/mkinitcpio.conf &> /dev/null
    fi
fi
# Include 'btrfs' module if btrfs filesystem is used on the disk
if [ "$part2_fs" = "btrfs" ]; then
    sed -i '/^MODULES=/ s/)/ btrfs)/' /etc/mkinitcpio.conf &> /dev/null
fi
print_info "    - generating initial ramdisk"
mkinitcpio -P &> /dev/null  # Generate the initial ramdisk

print_success "[+] Initial ramdisk configuration completed!"



# ------------------------------------------------------------------------------
#                                   Bootloader
# ------------------------------------------------------------------------------
print_warning "[*] Configuring the bootloader ..."

if [ "$bootldr" = "grub" ]; then
    print_info "    - configuring GRUB"
    cp /etc/default/grub /etc/default/grub.backup  # Backup current GRUB configuration
    # Update GRUB settings
    sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=30/" /etc/default/grub                          # Timeout = 30s
    sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/" /etc/default/grub                       # Use last selection
    sed -i "s/^#GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=y/" /etc/default/grub                  # Save last selection
    sed -i "s/^#GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/" /etc/default/grub          # Sub-menus
    sed -i "s/^#GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/" /etc/default/grub  # Os-prober
    # UUID 4 encrypt disk
    if [ "$encrypt" = "yes" ]; then
        print_info "    - configuring GRUB for encrypted disk"
        uuid=$(blkid -s UUID -o value ${target_part}2)  # Get UUID of the encrypted partition
        # Update GRUB for encrypted disk
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 cryptdevice=UUID=${uuid}:cryptdev\"|" /etc/default/grub
        sed -i "s/^GRUB_PRELOAD_MODULES=.*/GRUB_PRELOAD_MODULES=\"part_gpt part_msdos luks\"/" /etc/default/grub
        sed -i "s/^#GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/" /etc/default/grub
    fi
    print_info "    - installing GRUB (w/ new config)"
    # Install GRUB to EFI partition
    grub-install --target=x86_64-efi --efi-directory=/${part1_mount} --bootloader-id=GRUB --modules="tpm" --disable-shim-lock
    grub-mkconfig -o /boot/grub/grub.cfg &> /dev/null # Generate GRUB configuration
    if [ "$secure_boot" = "yes" ]; then
        print_info "    - configuring secure boot"
        # Secure boot (make sure system secure boot is in 'Setup mode')
        pacman -S --noconfirm sbctl &> /dev/null  # Install 'sbctl'
        sbctl create-keys &> /dev/null            # Create secure boot keys
        sbctl enroll-keys -m &> /dev/null         # Enroll secure boot keys
        # Sign the necessary files
        sbctl sign -s /${part1_mount}/EFI/GRUB/grubx64.efi \
                -s /${part1_mount}/grub/x86_64-efi/core.efi \
                -s /${part1_mount}/grub/x86_64-efi/grub.efi \
                -s /${part1_mount}/vmlinuz-linux-zen &> /dev/null
    fi
# elif [ "$bootldr" = "systemd-boot" ]; then
    # W.I.P.
fi

print_success "[+] Bootloader configuration completed!"



# ------------------------------------------------------------------------------
#                                Audio Driver(s)
# ------------------------------------------------------------------------------
print_warning "[*] Installing audio driver ..."

print_info "    - installing audio driver(s)"
pacman -S --noconfirm pipewire lib32-pipewire \
                pipewire-jack lib32-pipewire-jack \
                wireplumber \
                pipewire-alsa \
                pipewire-audio \
                pipewire-ffado \
                pipewire-pulse \
                pipewire-docs &> /dev/null

print_info "    - enabling audio driver(s)"
systemctl --user disable pulseaudio.service pulseaudio.socket &> /dev/null
systemctl --user stop pulseaudio.service pulseaudio.socket &> /dev/null
systemctl --user enable pipewire pipewire-pulse &> /dev/null
systemctl --user start pipewire pipewire-pulse &> /dev/null

print_success "[+] Audio driver installation completed!"



# ------------------------------------------------------------------------------
#                               Graphics Driver(s)
# ------------------------------------------------------------------------------
print_warning "[*] Installing graphics driver ..."

if [ "gpu" = "nvidia" ]; then
    print_info "    - installing NVIDIA driver"
    pacman -S --noconfirm nvidia-open nvidia-open-dkms \
                    nvidia-utils opencl-nvidia \
                    lib32-nvidia-utils lib32-opencl-nvidia \
                    nvidia-settings &> /dev/null
    print_info "    - configuring NVIDIA driver"
    # Add necessary kernel modules and udev rules
    sed -i '/^MODULES=/ s/(\(.*\))/(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia_drm.modeset=1"/' /etc/default/grub
    bash -c 'echo "ACTION==\"add\", DEVPATH==\"/bus/pci/drivers/nvidia\", RUN+=\"/usr/bin/nvidia-modprobe -c 0 -u\"" > /etc/udev/rules.d/70-nvidia.rules'
    bash -c 'echo "options nvidia NVreg_PreserveVideoMemoryAllocations=1" > /etc/modprobe.d/nvidia-power-mgmt.conf'
    print_info "    - generating initial ramdisk and GRUB configuration (w/ NVIDIA modules)"
    mkinitcpio -P &> /dev/null                         # Generate the initial ramdisk
    grub-mkconfig -o /boot/grub/grub.cfg &> /dev/null  # Generate GRUB configuration
elif [ "gpu" = "intel" ]; then
    print_info "    - installing Intel driver"
    pacman -S --noconfirm mesa lib32-mesa \
                    intel-media-driver libva-intel-driver \
                    vulkan-intel lib32-vulkan-intel &> /dev/null
    print_info "    - configuring Intel driver kernel modules"
    sed -i '/^MODULES=/ s/(\(.*\))/(\1 i915)/' /etc/mkinitcpio.conf  # Add i915 to modules
    print_info "    - generating initial ramdisk and GRUB configuration (w/ Intel modules)"
    mkinitcpio -P &> /dev/null                         # Generate the initial ramdisk
    grub-mkconfig -o /boot/grub/grub.cfg &> /dev/null  # Generate GRUB configuration
fi

print_success "[+] Graphics driver installation completed!"



# ------------------------------------------------------------------------------
#                           (User) Extra Configuration
# ------------------------------------------------------------------------------
print_warning "[*] User extra configuration ..."

su $username
print_info "    - installing default editor"
sudo pacman -S --noconfirm $editor &> /dev/null  # Install default editor
print_info "    - configuring default editor"
echo "EDITOR=${editor}" | sudo tee -a /etc/environment > /dev/null  # Set the default editor
echo "VISUAL=${editor}" | sudo tee -a /etc/environment > /dev/null  # Set the default visual editor
print_info "    - installing user extra packages"
sudo pacman -S --noconfirm $USR_EXT_PKGS &> /dev/null  # Install additional packages
# Install AUR helper (paru or yay)
if [ "$aur" = "paru" ]; then
    print_info "    - installing AUR helper (paru)"
    git clone https://aur.archlinux.org/paru.git /tmp/paru &> /dev/null
    cd /tmp/paru
    makepkg -si --noconfirm &> /dev/null
    cd - && rm -rf /tmp/paru
    sudo pacman -Syyu --noconfirm &> /dev/null
    paru -Syyu --noconfirm &> /dev/null
elif [ "$aur" = "yay" ]; then
    print_info "    - installing AUR helper (yay)"
    git clone https://aur.archlinux.org/yay.git /tmp/yay &> /dev/null
    cd /tmp/yay
    makepkg -si --noconfirm &> /dev/null
    cd - && rm -rf /tmp/yay
    sudo pacman -Syyu --noconfirm &> /dev/null
    yay -Syyu --noconfirm &> /dev/null
fi
print_info "    - installing QoL packages"
# QoL
${aur} -S --noconfirm pkgfile &> /dev/null       # Install 'pkgfile'
sudo pkgfile --update &> /dev/null               # Update 'pkgfile' database(s)
${aur} -S --noconfirm tealdeer &> /dev/null      # Install 'tealdeer'
tldr --update &> /dev/null                       # Update tldr pages
sudo pacman -S --noconfirm mlocate &> /dev/null  # Install 'mlocate'
sudo updatedb &> /dev/null                       # Update 'mlocate' database(s)
# Add command-not-found support to ~/.bashrc if not present
BASHRC="$HOME/.bashrc"
CONTENT='
# Command-not-found support for pkgfile
if [[ -f /usr/share/doc/pkgfile/command-not-found.bash ]]; then
    . /usr/share/doc/pkgfile/command-not-found.bash
fi
'
if ! grep -q "/usr/share/doc/pkgfile/command-not-found.bash" "$BASHRC"; then
    echo "$CONTENT" >> "$BASHRC"
fi
# Install and enable optional services
# SSH
if [ "$ssh" = "yes" ]; then
    print_info "    - installing SSH"
    sudo pacman -S --noconfirm openssh &> /dev/null  # Install 'openSSH'
    print_info "    - enabling SSH"
    sudo systemctl enable sshd.service &> /dev/null  # Enable 'sshd'
fi
# Bluetooth
if [ "$bluetooth" = "yes" ]; then
    print_info "    - installing Bluetooth"
    # Install Bluetooth packages
    sudo pacman -S --noconfirm bluez bluez-utils bluez-tools &> /dev/null
    print_info "    - configuring Bluetooth"
    BLUETOOTH_CONF="/etc/bluetooth/main.conf"  # Configuration file
    # Ensure ControllerMode is set to 'dual'
    if grep -q "^#*ControllerMode = dual" "$BLUETOOTH_CONF"; then
        sudo sed -i 's/^#*ControllerMode = dual/ControllerMode = dual/' "$BLUETOOTH_CONF"
    else
        echo "ControllerMode = dual" | sudo tee -a "$BLUETOOTH_CONF" > /dev/null
    fi
    # Ensure [General] section contains Experimental = true
    if grep -q "^\[General\]" "$BLUETOOTH_CONF"; then
        if grep -q "^#*Experimental = false" "$BLUETOOTH_CONF"; then
            sudo sed -i 's/^#*Experimental = false/Experimental = true/' "$BLUETOOTH_CONF"
        elif ! grep -q "^Experimental = true" "$BLUETOOTH_CONF"; then
            sudo sed -i '/^\[General\]/a Experimental = true' "$BLUETOOTH_CONF"
        fi
    else
        echo -e "\n[General]\nExperimental = true" | sudo tee -a "$BLUETOOTH_CONF" > /dev/null
    fi
    # Enable Bluetooth service
    print_info "    - enabling Bluetooth"
    sudo systemctl enable bluetooth.service &> /dev/null
fi
# Printer
if [ "$printer" = "yes" ]; then
    print_info "    - installing printer"
    sudo pacman -S --noconfirm cups cups-pdf bluez-cups &> /dev/null  # Install 'cups' and related packages
    print_info "    - configuring printer"
    sudo systemctl enable cups.service &> /dev/null                   # Enable 'cups'
fi
exit

print_success "[+] User extra configuration completed!"



# ------------------------------------------------------------------------------
#                              Desktop Environment
# ------------------------------------------------------------------------------
print_info "[*] Configuring desktop environment ..."

su $username
if [ "$de" = "gnome" ]; then
    ${aur} -Syy &> /dev/null           # Refresh package manager database(s)
    ${aur} -S $DE &> /dev/null         # Install GNOME
    ${aur} -S $GNOME_EXT &> /dev/null  # Install GNOME extensions
    sudo ln -sf /dev/null /etc/udev/rules.d/61-gdm.rules                            # Disable GDM rule
    sudo sed -i 's/^#WaylandEnable=false/WaylandEnable=true/' /etc/gdm/custom.conf  # Enable Wayland in GDM
    # Add blackbox-terminal as "Open in terminal ..."
    gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal blackbox-terminal
    sudo systemctl enable gdm.service  # Enable GDM service
# elif [ "$de" = "kde" ]; then
    # W.I.P.
fi

print_success "[+] Desktop environment configuration completed!"



# ------------------------------------------------------------------------------
#                              Post Boot Script(s)
# ------------------------------------------------------------------------------
cd /home/${username}
# Btrfs snapshots
wget https://raw.githubusercontent.com/atirelli3/installers/refs/heads/main/archlinux/scripts/btrfs-snapshot.sh
chmod +x btrfs-snapshot.sh
# Fingerprint reader

EOT



umount -R /mnt  # Unmount all device(s)
reboot now      # Reboot