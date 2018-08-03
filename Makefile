# mfslinux
#
# Copyright (c) 2018 Martin Matuska <mm at FreeBSD.org>
#
MFSLINUX_VERSION?=	0.1.2

MOUNT?=		$(shell which mount)
UMOUNT?=	$(shell which umount)
LOSETUP?=	$(shell which losetup)
GZIP?=		$(shell which gzip)
MKDIR?=		$(shell which mkdir)
RMDIR?=		$(shell which rmdir)
GREP?=		$(shell which grep)
SED?=		$(shell which sed)
AWK?=		$(shell which awk)
HEAD?=		$(shell which head)
TAR?=		$(shell which tar)
CP?=		$(shell which cp)
RM?=		$(shell which rm)
FIND?=		$(shell which find)
CAT?=		$(shell which cat)
CPIO?=		$(shell which cpio)
OPENSSL?=	$(shell which openssl)
CHROOT?=	$(shell which chroot)
TOUCH?=		$(shell which touch)
GIT?=		$(shell which git)
MKISOFS?=	$(shell which mkisofs)
BUILD_OS?=	$(shell uname)

ifeq ($(BUILD_OS),FreeBSD)
WGET?=		$(shell which fetch)
MDCONFIG?=	$(shell which mdconfig)
OPKG_CL?=	$(shell which opkg-cl)
else
WGET?=		$(shell which wget)
endif

CURDIR?=	$(shell pwd)
CONFIGDIR?=	$(CURDIR)/config
WRKDIR?=	$(CURDIR)/work
ISOLINUXDIR?=	$(CURDIR)/isolinux
DOWNLOADDIR?=	$(CURDIR)/download
ISODIR?=	$(WRKDIR)/iso

OPENWRT_ROOTDIR?=	$(WRKDIR)/openwrt_root
OPENWRT_IMGDIR?=	$(WRKDIR)/openwrt_root_img

OPENWRT_TARGET_URL=	https://downloads.openwrt.org/releases/18.06.0/targets/x86/64/
OPENWRT_PACKAGES_URL=	http://downloads.openwrt.org/releases/18.06.0/packages/x86_64/
OPENWRT_ROOTFS_IMAGE=	openwrt-18.06.0-x86-64-rootfs-ext4.img
OPENWRT_KERNEL=		openwrt-18.06.0-x86-64-vmlinuz

OPENWRT_PACKAGES_REMOVE?=	$(CONFIGDIR)/openwrt_packages_remove
OPENWRT_PACKAGES_ADD?=		$(CONFIGDIR)/openwrt_packages_add
OPENWRT_TARGET_PACKAGES_ADD?=	$(CONFIGDIR)/openwrt_target_packages_add
OPENWRT_ROOT_TAR?=	$(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE).tar

CONFIGFILES=	network system
ISOLINUX_CFG=	$(ISOLINUXDIR)/isolinux.cfg
ISOLINUX_BOOTTXT=	$(ISOLINUXDIR)/boot.txt
ISOLINUX_FILES=	isolinux.bin ldlinux.c32

ROOTPW?=	mfsroot
ROOT_SHELL?=	/bin/bash

GIT_REVISION=	$(shell $(GIT) rev-parse --short HEAD)

OUTPUT_ISO?=	mfslinux-$(MFSLINUX_VERSION)-$(GIT_REVISION).iso

VERBOSE?=	0

ifeq ("$(VERBOSE)","0")
	_v=@
else
	_v=
endif

OPKG_ENV=	env PATH="/usr/sbin:/usr/bin:/sbin:/bin"
ifeq ($(BUILD_OS),FreeBSD)
OPKG_CHROOT=
OPKG_PROG=	$(OPKG_CL)
OPKG_ARGS=	--chroot $(OPENWRT_ROOTDIR) \
		--add-arch all:1 \
		--add-arch noarch:1 \
		--add-arch x86_64:10 \
                --conf /etc/opkg.conf
else
OPKG_CHROOT=	$(CHROOT) $(OPENWRT_ROOTDIR)
OPKG_PROG=	env PATH="/usr/sbin:/usr/bin:/sbin:/bin" \
		opkg
OPKG_ARGS=
endif

all: iso

download: $(DOWNLOADDIR) download_kernel download_rootfs_image

$(WRKDIR):
	$(_v)$(MKDIR) -p $(WRKDIR)

$(DOWNLOADDIR):
	$(_v)$(MKDIR) -p $(DOWNLOADDIR)

download_kernel: $(DOWNLOADDIR) $(DOWNLOADDIR)/$(OPENWRT_KERNEL)

download_rootfs_image: $(DOWNLOADDIR) $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE)

$(DOWNLOADDIR)/$(OPENWRT_KERNEL):
	$(_v)echo "Downloading OpenWRT kernel"
	$(_v)cd $(DOWNLOADDIR) && $(WGET) $(OPENWRT_TARGET_URL)/$(OPENWRT_KERNEL)

# Download and extract rootfs image
$(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE):
	$(_v)echo "Downloading OpenWRT rootfs image"
	$(_v)cd $(DOWNLOADDIR) && $(WGET) $(OPENWRT_TARGET_URL)/$(OPENWRT_ROOTFS_IMAGE).gz
	$(_v)echo "Extracting OpenWRT rootfs image"
	$(_v)cd $(DOWNLOADDIR) && $(GZIP) -d $(OPENWRT_ROOTFS_IMAGE).gz

# Mount rootfs image
create_rootfs_tar: $(OPENWRT_ROOT_TAR)

$(OPENWRT_ROOT_TAR):
	$(_v)echo "Building openwrt root tar from image file"
	$(_v)$(MKDIR) -p $(OPENWRT_IMGDIR)
ifeq ($(BUILD_OS),FreeBSD)
	$(_v)if ! $(MDCONFIG) -l -f $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) > /dev/null; then \
	 $(MDCONFIG) -a -t vnode -f $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE); \
	 fi
	$(_v)LOOPDEV=`$(MDCONFIG) -l -f $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(HEAD) -1`; \
	 if ! $(MOUNT) | $(GREP) $$LOOPDEV > /dev/null; then \
	 $(MOUNT) -t ext2fs -o ro /dev/$$LOOPDEV $(OPENWRT_IMGDIR); \
	 fi
else
	$(_v)if ! $(LOSETUP) -j $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(GREP) $(OPENWRT_ROOTFS_IMAGE) > /dev/null; then \
	 $(LOSETUP) -f $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE); \
	 fi
	$(_v)LOOPDEV=`$(LOSETUP) -j $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(HEAD) -1 | $(AWK) -F: '{ print $$1 }'`; \
	 if ! $(MOUNT) | $(GREP) $$LOOPDEV > /dev/null; then \
	 $(MOUNT) -o loop,ro $$LOOPDEV $(OPENWRT_IMGDIR); \
	 fi
endif
	$(_v)$(TAR) -c -f $(OPENWRT_ROOT_TAR) -C $(OPENWRT_IMGDIR) .
	$(_v)$(UMOUNT) $(OPENWRT_IMGDIR)
	$(_v)$(RMDIR) $(OPENWRT_IMGDIR)
ifeq ($(BUILD_OS),FreeBSD)
	$(_v)LOOPDEV=`$(MDCONFIG) -l -f $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(HEAD) -1`; \
	 $(MDCONFIG) -d -u $$LOOPDEV
else
	$(_v)LOOPDEV=`$(LOSETUP) -j $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(HEAD) -1 | $(AWK) -F: '{ print $$1 }'`; \
	 $(LOSETUP) -d $$LOOPDEV
endif

extract_rootfs: create_rootfs_tar $(OPENWRT_ROOTDIR)/init

$(OPENWRT_ROOTDIR)/init:
	$(_v)$(MKDIR) -p $(OPENWRT_ROOTDIR)
	$(_v)$(TAR) -x -f $(OPENWRT_ROOT_TAR) -C $(OPENWRT_ROOTDIR)
	$(_v)$(CP) $(OPENWRT_ROOTDIR)/sbin/init $(OPENWRT_ROOTDIR)/init

set_root_pw: $(WRKDIR)/.set_root_pw_done

$(WRKDIR)/.set_root_pw_done:
	$(_v)echo "Setting root password"
	$(_v)ROOTPW_HASH=`$(OPENSSL) passwd -1 $(ROOTPW)`; \
	$(SED) -i -e "s,root:[^:]*,root:$$ROOTPW_HASH,g" $(OPENWRT_ROOTDIR)/etc/shadow
	$(_v)$(TOUCH) $(WRKDIR)/.set_root_pw_done

set_root_shell: $(WRKDIR)/.set_root_shell_done

$(WRKDIR)/.set_root_shell_done:
	$(_v)if [ -n "$(ROOT_SHELL)" ]; then \
	echo "Setting root shell"; \
	$(SED) -i -e "s,/bin/ash,$(ROOT_SHELL),g" $(OPENWRT_ROOTDIR)/etc/passwd; \
	$(TOUCH) $(WRKDIR)/.set_root_shell_done; \
	fi

remove_packages: $(WRKDIR)/.remove_packages_done

$(WRKDIR)/.remove_packages_done:
	$(_v)echo "Removing packages"
	$(_v)$(MKDIR) -p $(OPENWRT_ROOTDIR)/tmp/lock
	$(_v)if [ -f "$(OPENWRT_PACKAGES_REMOVE)" ]; then \
	  PACKAGES_REMOVE=`$(CAT) $(OPENWRT_PACKAGES_REMOVE)`; \
	else \
	  PACKAGES_REMOVE=`$(CAT) $(CONFIGDIR)/default/openwrt_packages_remove`; \
	fi; \
	$(OPKG_CHROOT) $(OPKG_ENV) $(OPKG_PROG) $(OPKG_ARGS) \
		remove $$PACKAGES_REMOVE
	$(_v)$(TOUCH) $(WRKDIR)/.remove_packages_done

download_packages:
	$(_v)if [ -f "$(OPENWRT_TARGET_PACKAGES_ADD)" ]; then \
	  PACKAGES_ADD=`$(CAT) $(OPENWRT_TARGET_PACKAGES_ADD)`; \
	else \
	  PACKAGES_ADD=`$(CAT) $(CONFIGDIR)/default/openwrt_target_packages_add`; \
	fi; \
	for PKG in $$PACKAGES_ADD; do \
	if [ ! -f $(DOWNLOADDIR)/$${PKG} ]; then \
	echo "Downloading: $${PKG}"; \
	cd $(DOWNLOADDIR) && $(WGET) $(OPENWRT_TARGET_URL)/packages/$${PKG}; \
	fi; \
	done; \
	if [ -f "$(OPENWRT_PACKAGES_ADD)" ]; then \
	  PACKAGES_ADD=`$(CAT) $(OPENWRT_PACKAGES_ADD)`; \
	else \
	  PACKAGES_ADD=`$(CAT) $(CONFIGDIR)/default/openwrt_packages_add`; \
	fi; \
	for PKG in $$PACKAGES_ADD; do \
	PKGNAME=`basename $$PKG`; \
	if [ ! -f $(DOWNLOADDIR)/$${PKGNAME} ]; then \
	echo "Downloading: $${PKG}"; \
	cd $(DOWNLOADDIR) && $(WGET) $(OPENWRT_PACKAGES_URL)/$${PKG}; \
	fi; \
	done

add_packages: download_packages $(WRKDIR)/.add_packages_done

$(WRKDIR)/.add_packages_done:
	$(_v)$(MKDIR) -p $(OPENWRT_ROOTDIR)/packages
	$(_v)if [ -f $(OPENWRT_TARGET_PACKAGES_ADD) ]; then \
	  PACKAGES_ADD=`$(CAT) $(OPENWRT_TARGET_PACKAGES_ADD)`; \
	else \
	  PACKAGES_ADD=`$(CAT) $(CONFIGDIR)/default/openwrt_target_packages_add`; \
	fi; \
	if [ -f $(OPENWRT_PACKAGES_ADD) ]; then \
	  PACKAGES_ADD="$$PACKAGES_ADD `$(CAT) $(OPENWRT_PACKAGES_ADD)`"; \
	else \
	  PACKAGES_ADD="$$PACKAGES_ADD `$(CAT) $(CONFIGDIR)/default/openwrt_packages_add`"; \
	fi; \
	for PKG in $$PACKAGES_ADD; do \
	PKGNAME=`basename $$PKG`; \
	$(CP) $(DOWNLOADDIR)/$$PKGNAME $(OPENWRT_ROOTDIR)/packages; \
	$(OPKG_CHROOT) $(OPKG_ENV) $(OPKG_PROG) $(OPKG_ARGS) \
		install /packages/$$PKGNAME; \
	done; \
	$(RM) -rf $(OPENWRT_ROOTDIR)/packages
	$(_v)$(TOUCH) $(WRKDIR)/.add_packages_done

copy_configuration_files: $(WRKDIR)/.copy_configuration_files_done

$(WRKDIR)/.copy_configuration_files_done:
	$(_v)echo "Coypying configuration files"
	$(_v)for FILE in $(CONFIGFILES); do \
	if [ -f $(CONFIGDIR)/$$FILE ]; then \
		$(CP) -f $(CONFIGDIR)/$$FILE $(WRKDIR)/openwrt_root/etc/config/$$FILE; \
	elif [ -f $(CONFIGDIR)/default/$$FILE ]; then \
		$(CP) -f $(CONFIGDIR)/default/$$FILE $(WRKDIR)/openwrt_root/etc/config/$$FILE; \
	else \
		echo "Missing configuration file: $(CONFIGDIR)/$$FILE"; \
		exit 1; \
	fi; \
	done
	$(_v)$(TOUCH) $(WRKDIR)/.copy_configuration_files_done

host_key: $(WRKDIR)/.host_key_done

$(WRKDIR)/.host_key_done:
	$(_v)if [ -f $(CONFIGDIR)/dropbear_rsa_host_key ]; then \
	echo "Installing dropbear_rsa_host_key"; \
	$(CP) -f $(CONFIGDIR)/dropbear_rsa_host_key \
	  $(OPENWRT_ROOTDIR)/etc/dropbear/dropbear_rsa_host_key; \
	fi
	$(_v)$(TOUCH) $(WRKDIR)/.host_key_done

banner: $(WRKDIR)/.banner_done

$(WRKDIR)/.banner_done:
	$(_v)echo "Appending mfslinux info to OpenWRT banner"
	$(_v)echo " mfslinux $(MFSLINUX_VERSION) $(GIT_REVISION)" >> $(OPENWRT_ROOTDIR)/etc/banner
	$(_v)echo " -----------------------------------------------------" >> \
		$(OPENWRT_ROOTDIR)/etc/banner
	$(_v)$(TOUCH) $(WRKDIR)/.banner_done

$(ISODIR)/isolinux/initramfs.igz: 
	$(_v)echo "Generating initramfs"
	$(_v)$(MKDIR) -p $(ISODIR)/isolinux
	$(_v)cd $(WRKDIR)/openwrt_root && $(FIND) . | $(CPIO) -H newc -o | $(GZIP) > $(ISODIR)/isolinux/initramfs.igz

copy_kernel: download_kernel $(ISODIR)/isolinux/vmlinuz

$(ISODIR)/isolinux/vmlinuz:
	$(_v)echo "Copying kernel"
	$(_v)$(MKDIR) -p $(ISODIR)/isolinux
	$(_v)$(CP) $(DOWNLOADDIR)/$(OPENWRT_KERNEL) $(ISODIR)/isolinux/vmlinuz

copy_isolinux_files: $(WRKDIR)/.copy_isolinux_files_done

$(WRKDIR)/.copy_isolinux_files_done:
	$(_v)echo "Copying isolinux files"
	$(_v)for FILE in $(ISOLINUX_FILES); do \
	$(CP) -f $(ISOLINUXDIR)/$$FILE $(ISODIR)/isolinux/$$FILE; \
	 done
	$(_v)$(CP) -f $(ISOLINUX_CFG) $(ISODIR)/isolinux/isolinux.cfg
	$(_v)$(CP) -f $(ISOLINUX_BOOTTXT) $(ISODIR)/isolinux/boot.txt
	$(_v)$(TOUCH) $(WRKDIR)/.copy_isolinux_files_done

customize_rootfs: remove_packages add_packages copy_configuration_files set_root_pw set_root_shell host_key banner

generate_initramfs: download_rootfs_image extract_rootfs customize_rootfs $(ISODIR)/isolinux/initramfs.igz

iso: generate_initramfs copy_kernel copy_isolinux_files $(OUTPUT_ISO)

$(OUTPUT_ISO):
	$(_v)echo "Generating $(OUTPUT_ISO)"
	$(_v)if [ "$(MKISOFS)" = "" ]; then echo "Error: mkisofs missing"; exit 1; fi
	$(_v)$(MKISOFS) -quiet -r -T -J -iso-level 2 -V "mfslinux" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $(OUTPUT_ISO) $(ISODIR)

clean-download:
	$(_v)if [ "$(DOWNLOADDIR)" != "/" ]; then $(RM) -rf $(DOWNLOADDIR); fi

clean:
	$(_v)if [ "$(WRKDIR)" != "/" ]; then $(RM) -rf $(WRKDIR); fi
	$(_v)$(RM) -f $(OUTPUT_ISO)

clean-all: clean clean-download
