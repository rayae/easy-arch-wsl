#!/bin/bash

# 默认镜像
default_mirror="https://mirrors.aliyun.com"

rootfs=/mnt/rootfs
root_password="arch1234"
output=archlinux-rootfs.tar.gz

with_wslg=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-wslg)
            with_wslg=true
            shift
            ;;
        --output)
            if [[ -n $2 ]]; then
                output="$2"
                shift 2
            else
                echo "Error: --output requires a filename argument"
                exit 1
            fi
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

set -e
# set -x

# 初始化 Pacman
echo "Server = $default_mirror/archlinux/\$repo/os/\$arch" >| /etc/pacman.d/mirrorlist
pacman-key --init && pacman-key --populate && pacman -Sy --noconfirm archlinux-keyring && pacman -Syy --noconfirm

# 安装环境需要的基础软件
pacman -S --noconfirm base-devel arch-install-scripts wget curl zip unzip vim sed pacman-contrib openssl
# 选取最快的 6 个软件镜像
curl -s "https://archlinux.org/mirrorlist/?country=CN&protocol=https&use_mirror_status=on)" | sed -e 's/^#Server/Server/' -e '/^#/d' | rankmirrors -n 6 - | sudo tee /etc/pacman.d/mirrorlist
pacman -Syy --noconfirm

# 创建 rootfs
mkdir -p $rootfs ${rootfs}.mount
mount --bind ${rootfs}.mount $rootfs

pacstrap -G -M -C /etc/pacman.conf -K $rootfs base base-devel wget curl zip unzip vim sed nano sudo texinfo man-db man-pages openssl
cp /etc/pacman.conf $rootfs/etc/
cp /etc/pacman.d/mirrorlist $rootfs/etc/pacman.d/

# 设置 ROOT 用户密码
arch-chroot $rootfs bash -c "echo root:$root_password | chpasswd"

# 开启 UTF-8
echo 'LANG=en_US.UTF-8' > $rootfs/etc/locale.conf && sed -i -e 's/^#.*en_US.UTF-8/en_US.UTF-8/g' $rootfs/etc/locale.gen && arch-chroot $rootfs locale-gen
rm $rootfs/etc/machine-id && touch $rootfs/etc/machine-id

arch-chroot $rootfs bash -c 'pacman-key --init && pacman-key --populate && pacman -Sy --noconfirm archlinux-keyring'

# archlinuxcn 软件源
echo -e "[archlinuxcn]\nServer = $default_mirror/archlinuxcn/\$arch\n" >> $rootfs/etc/pacman.conf
arch-chroot $rootfs bash -c 'pacman-key --lsign-key "farseerfc@archlinux.org" &&
    pacman -Syy archlinuxcn-keyring --noconfirm'

# 滚动更新到最新
arch-chroot $rootfs pacman -Syyu --noconfirm

# sudo 配置
echo "%wheel ALL=(ALL) ALL" > $rootfs/etc/sudoers.d/wheel
# sudo 无需密码
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" >> $rootfs/etc/sudoers.d/wheel

# 安装 yay 和 bash-completion 等基本软件
arch-chroot $rootfs pacman -S --noconfirm yay bash-completion net-tools openssh
echo '[ -r /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion' >> $rootfs/etc/profile


# WSL 相关配置
cp ./wsl-boot.sh $rootfs/etc/
cp ./wsl.conf $rootfs/etc/
chmod 0755 $rootfs/etc/wsl-boot.sh
chmod 0644 $rootfs/etc/wsl.conf

if $with_wslg ; then

    # WSLg
    arch-chroot $rootfs pacman -S --noconfirm xorg-xrdb
    cp ./systemd/wsl-wayland-socket.service $rootfs/etc/systemd/user/
    cp ./systemd/wsl-x11-socket.service $rootfs/etc/systemd/system/
    arch-chroot $rootfs systemctl enable wsl-x11-socket
    arch-chroot $rootfs systemctl --user enable wsl-wayland-socket

    # 安装字体及语言包
    arch-chroot $rootfs pacman -S --noconfirm noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra

    # 安装 Fcitx5
    arch-chroot $rootfs pacman -S --noconfirm fcitx5-im fcitx5-chinese-addons fcitx5-qt fcitx5-gtk
    echo "
export GTK_IM_MODULE_DEFAULT=fcitx
export QT_IM_MODULE_DEFAULT=fcitx
export XMODIFIERS_DEFAULT=@im=fcitx
export SDL_IM_MODULE_DEFAULT=fcitx
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export DefaultIMModule=fcitx
" | tee -a $rootfs/etc/profile
    cp ./systemd/fcitx5.service $rootfs/etc/systemd/user/

    arch-chroot $rootfs systemctl --user enable fcitx5

fi

rm -rf $rootfs/var/cache/pacman/pkg/*

# 生成 rootfs.tar.gz
tar -czf "$output" -C $rootfs ./
sha256sum "$output" > "$output".sha256sum
du -h "$output"
chmod 0777 "$output"
chmod 0777 "$output".sha256sum

