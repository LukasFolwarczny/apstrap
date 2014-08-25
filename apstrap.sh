#!/bin/bash

# Expects an Arch with all partitions mounted and with a base system.
# See CONFIG part before running.

if [[ $EUID -ne 0 ]]; then
	echo "apstrap must be run as root."
	exit 1
fi

die() {
	echo " ERROR: $1"
	exit 1
}

ensure_installed() {
	command=yaourt
	if [ "$1" = "-p" ]; then
		command=pacman
		shift
	fi

	package="$1"
	pacman -Q "$package" >/dev/null 2>&1
	if (( $? )); then
		[ "$command" = yaourt ] && echo " ==> Package not installed: $package Installing..."
		$command --noconfirm -S $package >/dev/null 2>&1 || die "Failed to install package!"
	fi
}

ensure_installed_group() {
	command=yaourt
	if [ "$1" = "-p" ]; then
		command=pacman
		shift
	fi

	group="$1"
	if [ -n "`pacman --noconfirm -Sp --needed "$group"`" ]; then
		[ "$command" = yaourt ] && echo " ==> Package group not installed: $group Installing..."
		$command --noconfirm -S --needed $group >/dev/null 2>&1 || die "Failed to install group!"
	fi
}

check_yaourt() {
	yaourt --help >/dev/null 2>&1
	if [ $? != 127 ]; then
		echo " ==> Yaourt already installed."
		return 0
	fi
		
	echo "Installing yaourt..."

	cd /tmp
	ensure_installed_group -p base-devel
	ensure_installed -p wget
	wget http://aur.archlinux.org/packages/pa/package-query/package-query.tar.gz >/dev/null 2>&1 \
	 || die "package-query download failed!"
	tar zxvf package-query.tar.gz >/dev/null 2>&1
	cd package-query
	makepkg --noconfirm -si --asroot >/dev/null 2>&1 || die "package-query installation failed!"
	cd ..
	wget http://aur.archlinux.org/packages/ya/yaourt/yaourt.tar.gz >/dev/null 2>&1 \
	 || die "yaourt download failed!"
	tar zxvf yaourt.tar.gz >/dev/null 2>&1
	cd yaourt
	makepkg --noconfirm -si --asroot >/dev/null 2>&1 || die "yaourt installation failed!"
	cd ..
	rm -r package-query
	rm -r yaourt

	yaourt --help >/dev/null 2>&1
	[ $? == 127 ] && die "yaourt installation failed!"

	echo " ==> Yaourt installed."
}

check_font() {
	config="/etc/vconsole.conf"
	[ ! -f $config ] && die "$config doesn't exist!"
	. $config
	[ $FONT != "ter-u12n" ] && die "Font not set to ter-u12n in $config!"

	echo " ==> Console font is OK."
}

check_hostname() {
	if [ ! -f "/etc/hostname" ]; then
		if [ -n "$HOSTNAME" ]; then
			echo "Setting hostname to $HOSTNAME."
			echo "$HOSTNAME" > /etc/hostname	
		else
			die "Hostname not set in /etc/hostname and hostname not specified!"
		fi
	fi

	if [ -n "$HOSTNAME" ]; then
		if [ "$HOSTNAME" != "`cat /etc/hostname`" ]; then
			die "Hostname should be $HOSTNAME, is `cat /etc/hostname`!"
		fi
	fi
	
	# TODO: check /etc/hosts
	echo " ==> Hostname OK."
}

check_timezone() {
	[ ! -f "/etc/localtime" ] && ln -s /usr/share/zoneinfo/Europe/Prague /etc/localtime
}

check_locale() {
	NEW_LANG="en_US.UTF-8"
	if [ ! -f /etc/locale.conf ]; then
		echo "Setting LANG to $NEW_LANG."
		localectl set-locale "LANG=$NEW_LANG"
	else
		. /etc/locale.conf
		if [ "$LANG" != "$NEW_LANG" ]; then
			die "LANG is $LANG, but should be $NEW_LANG! Fix or delete /etc/locale.conf."
		fi
	fi

	echo " ==> Locale OK. ($NEW_LANG)"
}

check_locale_gen() {
	if [ ! -f /etc/locale.gen ]; then
		die "/etc/locale.gen doesn't exist!"
	fi

	patch --dry-run -R /etc/locale.gen uncomment-my-locale.patch >/dev/null

	if (( $? )); then
		patch -p1 /etc/locale.gen uncomment-my-locale.patch -N -r- >/dev/null 2>&1
		if (( $? )); then
			die "Error patching /etc/locale.gen!"
		fi
		locale-gen
	fi

	echo " ==> Locale-gen OK."
}

get_package_selection() {
	PACKAGES=()
	GROUPZ=()

	# Essential stuff
	GROUPZ+=(linux-tools)
	PACKAGES+=(mc vim openssh sudo bc less fakeroot)
	PACKAGES+=(gcc patch make git)

	# Basic stuff
	PACKAGES+=(unrar unzip)
	PACKAGES+=(wget curl rsync)
	PACKAGES+=(colordiff bash-completion)
	PACKAGES+=(terminus-font tmux)
	PACKAGES+=(gtypist moc irssi)
	PACKAGES+=(cups ntp)

	(( $INSTALL_DEVEL )) && PACKAGES+=(python perl ghc swi-prolog gdb markdown)

	# Drivers
	PACKAGES+=(alsa-utils alsa-firmware alsa-plugins)
	PACKAGES+=(ntfs-3g-fuse exfat-utils fuse-exfat)
	(( $INSTALL_LAPTOP )) && PACKAGES+=(acpi acpid)

	# Utils
	PACKAGES+=(macchanger traceroute)

	PACKAGES+=(ecryptfs-utils) ### TODO: config it

	if (( $INSTALL_X )); then
		# X
		PACKAGES+=(xorg-server xorg-xrandr xorg-xev awesome)

		PACKAGES+=(scrot xscreensaver)

		# X applications
		PACKAGES+=(evince mupdf okular)
		PACKAGES+=(luakit firefox chromium flashplugin)
		PACKAGES+=(sxiv eog feh inkscape ipe)
		PACKAGES+=(rxvt-unicode urxvt-perls)

		PACKAGES+=(jdownloader qbittorrent)

		PACKAGES+=(vlc)

		PACKAGES+=(baobab)

		PACKAGES+=(graphviz gnuplot)

		(( $INSTALL_STUFF )) && PACKAGES+=(easytag digikam)
		(( $INSTALL_STUFF )) && PACKAGES+=(geogebra octave gimp glpk)
		(( $INSTALL_LAPTOP )) && PACKAGES+=(xf86-input-synaptics)

		PACKAGES+=(libreoffice-still-base libreoffice-still-calc libreoffice-still-draw)
		PACKAGES+=(libreoffice-still-cs libreoffice-still-impress libreoffice-still-math)
		PACKAGES+=(libreoffice-still-writer)

		PACKAGES+=(gnumeric)

		PACKAGES+=(dropbox)

		# Util
		PACKAGES+=(gparted)
		## TODO: JAVA???

		PACKAGES+=(udiskie) # Auto-mounting

		(( $INSTALL_MAIL )) && PACKAGES+=(thunderbird gnupg thunderbird-enigmail)
	fi

	PACKAGES+=(gnuplot)

	if (( $INSTALL_TEX )); then
		# texlive-most
		PACKAGES+=(texlive-core texlive-fontsextra texlive-formatsextra texlive-games texlive-genericextra)
		PACKAGES+=(texlive-htmlxml texlive-humanities texlive-latexextra texlive-music texlive-pictures)
		PACKAGES+=(texlive-plainextra texlive-pstricks texlive-publishers texlive-science)
	fi

	# Chce multilib
	#$INSTALL wine
	#$INSTALL skype
}

check_packages() {
	echo "Checking packages..."
	get_package_selection

	for group in ${GROUPZ[@]}; do
		ensure_installed_group "$group"
	done
	for package in ${PACKAGES[@]}; do
		ensure_installed "$package"
	done
	mandb # TODO: Is it necessary?
	echo " ==> Packages OK."
}

check_root() {
	if [ ! -f ./rootpwdset ]; then
		echo "Set root password. (If already set, input just two random strings.)"
		passwd
		touch ./rootpwdset
	fi
}

check_user() {
	user="$1"
	name="$2"
	if ! id $1 >/dev/null 2>&1; then
		useradd -m -c "$name" $1
		echo "User $1 ($2) created, set his password."
		passwd $1
	fi
	echo " ==> User '$user' OK."
}

check_user_environment() {
	user="$1"
	# TODO: v prvakovi to nechci mit read-only!
	# TODO: downloadni si dotfiles, scripts
	echo "user environment check not implemented. please check environment of user $1."

	#cd ~prvak
	#git clone git://github.com/MichalPokorny/dotfiles.git .
	#mkdir bin
	#git clone git://github.com/MichalPokorny/scripts.git bin
	#chown -R prvak:prvak ~prvak

	#su "$user" -c "xmonad --recompile"

	#if (( $? )); then
	#	die "Failed to recompile XMonad for $user!"
	#else
	#	echo " ==> Recompiled XMonad of $user"
	#fi
}

#check_vgaswitcheroo() {
#	tag="# Added by check.sh. Don't remove this line."
#	grep "$tag" /etc/rc.local --quiet
#
#	if (( $? )); then
#		cat >> /etc/rc.local <<EOF

#$tag
# Turn off vgaswitcheroo if present.
#SWITCHER="/sys/kernel/debug/vgaswitcheroo/switch"
#[ -f \$SWITCHER ] && echo OFF > \$SWITCHER
#EOF
#		echo " ==> Added vgaswitcheroo lines to /etc/rc.local"	else
#		echo " ==> /etc/rc.local already tagged, won't retag."
#	fi
#}

check_sudoers() {
	# TODO: Modify
	return
	exit 1
	tag="# Added by check.sh. Don't remove this line."
	grep "$tag" /etc/sudoers --quiet

	if (( $? )); then
		cat >> /etc/sudoers <<EOF

$tag
# Allow mounting, unmounting and suspending.
prvak ALL=(ALL) NOPASSWD: /home/prvak/bin/cryptomount, /home/prvak/bin/cryptounmount, /usr/sbin/pm-suspend
EOF
		echo " ==> /etc/sudoers set"
	else
		echo " ==> /etc/sudoers already tagged, won't retag."
	fi
}

update() {
	yaourt -Syua --noconfirm 2>&1 > /dev/null
	if (( $? )); then
		die "Error updating system!"
	else
		echo " ==> System updated"
	fi
}

install_grub() {
	# TODO
	if [ -n "$DISK_DEVICE" ]; then
		grub-install "$DISK_DEVICE" # TODO: vybrat zarizeni!
		grub-mkconfig > /boot/grub/grub.cfg
		mkinitcpio -p linux
		echo " ==> GRUB installed"
	else
		echo " ==> Not installing GRUB: disk device unspecified"
	fi
}

patch_acpi_event_handler() {
	# TODO
	#patch -p1 /etc/acpi/handler.sh handle-acpi-events.patch -N -r-
	#if (( $? )); then
	#	die "Error patching /etc/acpi/handler.sh!"
	#fi
	echo patch_acpi_event_handler not implemented.
}

enable_daemons() {
	###systemctl enable upower
	systemctl enable dbus
	###(( $INSTALL_MUSIC )) && systemctl enable mpd
	###(( $INSTALL_X )) && systemctl enable xdm
}

check_system() {
	check_yaourt
	check_hostname
	check_timezone
	check_font
	check_locale
	check_locale_gen
	check_packages

	check_root
	check_user lukas "Lukáš Folwarczný"
	check_user test "Králík Pokusný"

	check_user_environment root
	check_user_environment lukas
	check_user_environment test

	# TODO: check GRUB

	# TODO: xosdutil spravne nainstalovana

	# TODO: mount -a, a je primontovany debugfs
	# TODO: sudo-veci jdou

	#echo "none /sys/kernel/debug debugfs defaults 0 0" >> /etc/fstab
	#cat >> /etc/rc.local <<EOF
	#EOF

	check_vgaswitcheroo
	# TODO
	# check_sudoers

	# TODO: Set acpi
	# patch_acpi_event_handler

	update

	# TODO
	#install_grub

	enable_daemons

	echo "Most drone work done. The remaining stuff:"
	# TODO: Update.
	echo "    Configure /etc/hosts: add l-alias, hostname alias"

	# TODO:
	#/etc/lighttpd/lighttpd.conf; lighttpd do demonu
	#mkdir -p /srv/http/public
}

### CONFIG ###

INSTALL_MAIL=1
INSTALL_STUFF=1
INSTALL_DEVEL=1
INSTALL_TEX=1
INSTALL_LAPTOP=1
INSTALL_X=1
HOSTNAME=""
#DISK_DEVICE=""

###

echo "apstrap by Folwar BETA, based on apstrap by prvak"
check_system
