# mfslinux
#
# Copyright (c) 2018 Martin Matuska <mm at FreeBSD.org>

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
OPENWRT_ROOT_TAR?=	$(WRKDIR)/openwrt_root.tar

OPENWRT_TARGET_URL=	https://downloads.openwrt.org/releases/18.06.0-rc1/targets/x86/64/
OPENWRT_PACKAGES_URL=	http://downloads.openwrt.org/releases/18.06.0-rc1/packages/x86_64/
OPENWRT_ROOTFS_IMAGE=	openwrt-18.06.0-rc1-x86-64-rootfs-ext4.img
OPENWRT_KERNEL=		openwrt-18.06.0-rc1-x86-64-vmlinuz

OPENWRT_PACKAGES_REMOVE?=	$(CONFIGDIR)/openwrt_packages_remove
OPENWRT_PACKAGES_ADD?=		$(CONFIGDIR)/openwrt_packages_add

CONFIGFILES=	network system
ISOLINUX_CFG=	$(ISOLINUXDIR)/isolinux.cfg
ISOLINUX_BOOTTXT=	$(ISOLINUXDIR)/boot.txt
ISOLINUX_FILES=	isolinux.bin ldlinux.c32

ROOTPW?=	mfsroot

OUTPUT_ISO?=	mfslinux.iso


all: iso

download: $(DOWNLOADDIR) download_kernel download_rootfs_image

$(WRKDIR):
	@$(MKDIR) -p $(WRKDIR)

$(DOWNLOADDIR):
	@$(MKDIR) -p $(DOWNLOADDIR)

download_kernel: $(DOWNLOADDIR) $(DOWNLOADDIR)/$(OPENWRT_KERNEL)

download_rootfs_image: $(DOWNLOADDIR) $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE)

$(DOWNLOADDIR)/$(OPENWRT_KERNEL):
	@echo "Downloading OpenWRT kernel"
	@cd $(DOWNLOADDIR) && $(WGET) $(OPENWRT_TARGET_URL)/$(OPENWRT_KERNEL)

# Download and extract rootfs image
$(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE):
	@echo "Downloading OpenWRT rootfs image"
	@cd $(DOWNLOADDIR) && $(WGET) $(OPENWRT_TARGET_URL)/$(OPENWRT_ROOTFS_IMAGE).gz
	@echo "Extracting OpenWRT rootfs image"
	@cd $(DOWNLOADDIR) && $(GZIP) -d $(OPENWRT_ROOTFS_IMAGE).gz

# Mount rootfs image
create_rootfs_tar: $(OPENWRT_ROOT_TAR)

$(OPENWRT_ROOT_TAR):
	@echo "Extracting openwrt root"
	@$(MKDIR) -p $(OPENWRT_IMGDIR)
ifeq ($(BUILD_OS),FreeBSD)
	@if ! $(MDCONFIG) -l -f $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) > /dev/null; then \
	 $(MDCONFIG) -a -t vnode -f $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE); \
	 fi
	@LOOPDEV=`$(MDCONFIG) -l -f $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(HEAD) -1`; \
	 if ! $(MOUNT) | $(GREP) $$LOOPDEV > /dev/null; then \
	 $(MOUNT) -t ext2fs -o ro /dev/$$LOOPDEV $(OPENWRT_IMGDIR); \
	 fi
else
	@if ! $(LOSETUP) -j $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(GREP) $(OPENWRT_ROOTFS_IMAGE) > /dev/null; then \
	 $(LOSETUP) -f $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE); \
	 fi
	@LOOPDEV=`$(LOSETUP) -j $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(HEAD) -1 | $(AWK) -F: '{ print $$1 }'`; \
	 if ! $(MOUNT) | $(GREP) $$LOOPDEV > /dev/null; then \
	 $(MOUNT) -o loop,ro $$LOOPDEV $(OPENWRT_IMGDIR); \
	 fi
endif
	@$(TAR) -c -f $(OPENWRT_ROOT_TAR) -C $(OPENWRT_IMGDIR) .
	@$(UMOUNT) $(OPENWRT_IMGDIR)
	@$(RMDIR) $(OPENWRT_IMGDIR)
ifeq ($(BUILD_OS),FreeBSD)
	@LOOPDEV=`$(MDCONFIG) -l -f $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(HEAD) -1`; \
	 $(MDCONFIG) -d -u $$LOOPDEV
else
	@LOOPDEV=`$(LOSETUP) -j $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(HEAD) -1 | $(AWK) -F: '{ print $$1 }'`; \
	 $(LOSETUP) -d $$LOOPDEV
endif

extract_rootfs: create_rootfs_tar $(OPENWRT_ROOTDIR)/init

$(OPENWRT_ROOTDIR)/init:
	@$(MKDIR) -p $(OPENWRT_ROOTDIR)
	@$(TAR) -x -f $(OPENWRT_ROOT_TAR) -C $(OPENWRT_ROOTDIR)
	@$(CP) $(OPENWRT_ROOTDIR)/sbin/init $(OPENWRT_ROOTDIR)/init

set_rootpw: $(WRKDIR)/.rootpw_done

$(WRKDIR)/.rootpw_done:
	@echo "Setting root password"
	@ROOTPW_HASH=`$(OPENSSL) passwd -1 $(ROOTPW)`; \
	$(SED) -i -e "s,root:[^:]*,root:$$ROOTPW_HASH,g" $(OPENWRT_ROOTDIR)/etc/shadow
	@$(TOUCH) $(WRKDIR)/.rootpw_done

remove_packages: $(WRKDIR)/.remove_packages_done

$(WRKDIR)/.remove_packages_done:
ifeq ($(BUILD_OS),FreeBSD)
	@echo "Removing OpenWRT packages not supported on FreeBSD"
else
	@echo "Removing packages"
	@$(MKDIR) -p $(OPENWRT_ROOTDIR)/tmp/lock
	@if [ -f $(OPENWRT_PACKAGES_REMOVE) ]; then \
	  PACKAGES_REMOVE=`$(CAT) $(OPENWRT_PACKAGES_REMOVE)`; \
	else \
	  PACKAGES_REMOVE=`$(CAT) $(CONFIGDIR)/default/openwrt_packages_remove`; \
	fi; \
	  $(CHROOT) $(OPENWRT_ROOTDIR) opkg remove $$PACKAGES_REMOVE
endif
	@$(TOUCH) $(WRKDIR)/.remove_packages_done

download_packages:
	@if [ -f $(OPENWRT_PACKAGES_ADD) ]; then \
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
ifeq ($(BUILD_OS),FreeBSD)
	@echo "Adding new OpenWRT packages not supported on FreeBSD"
else
	@$(MKDIR) -p $(OPENWRT_ROOTDIR)/packages
	@if [ -f $(OPENWRT_PACKAGES_ADD) ]; then \
	  PACKAGES_ADD=`$(CAT) $(OPENWRT_PACKAGES_ADD)`; \
	else \
	  PACKAGES_ADD=`$(CAT) $(CONFIGDIR)/default/openwrt_packages_add`; \
	fi; \
	for PKG in $$PACKAGES_ADD; do \
	PKGNAME=`basename $$PKG`; \
	$(CP) $(DOWNLOADDIR)/$$PKGNAME $(OPENWRT_ROOTDIR)/packages; \
	$(CHROOT) $(OPENWRT_ROOTDIR) opkg install /packages/$$PKGNAME; \
	done
	@$(RM) -rf $(OPENWRT_ROOTDIR)/packages
endif
	@$(TOUCH) $(WRKDIR)/.add_packages_done

copy_configuration_files: $(WRKDIR)/.copy_configuration_files_done

$(WRKDIR)/.copy_configuration_files_done:
	@echo "Coypying configuration files"
	@for FILE in $(CONFIGFILES); do \
	if [ -f $(CONFIGDIR)/$$FILE ]; then \
		$(CP) -f $(CONFIGDIR)/$$FILE $(WRKDIR)/openwrt_root/etc/config/$$FILE; \
	elif [ -f $(CONFIGDIR)/default/$$FILE ]; then \
		$(CP) -f $(CONFIGDIR)/default/$$FILE $(WRKDIR)/openwrt_root/etc/config/$$FILE; \
	else \
		echo "Missing configuration file: $(CONFIGDIR)/$$FILE"; \
		exit 1; \
	fi; \
	done
	@$(TOUCH) $(WRKDIR)/.copy_configuration_files_done

host_key: $(WRKDIR)/.host_key_done

$(WRKDIR)/.host_key_done:
	@if [ -f $(CONFIGDIR)/dropbear_rsa_host_key ]; then \
	echo "Installing dropbear_rsa_host_key"; \
	$(CP) -f $(CONFIGDIR)/dropbear_rsa_host_key \
	  $(OPENWRT_ROOTDIR)/etc/dropbear/dropbear_rsa_host_key; \
	fi
	@$(TOUCH) $(WRKDIR)/.host_key_done

banner: $(WRKDIR)/.banner_done

$(WRKDIR)/.banner_done:
	@echo "Appending mfslinux info to OpenWRT banner"
	@echo " mfslinux `$(GIT) rev-parse --short HEAD`" >> $(OPENWRT_ROOTDIR)/etc/banner
	@echo " -----------------------------------------------------" >> \
		$(OPENWRT_ROOTDIR)/etc/banner
	@$(TOUCH) $(WRKDIR)/.banner_done

$(ISODIR)/isolinux/initramfs.igz: 
	@echo "Generating initramfs"
	@$(MKDIR) -p $(ISODIR)/isolinux
	@cd $(WRKDIR)/openwrt_root && $(FIND) . | $(CPIO) -H newc -o | $(GZIP) > $(ISODIR)/isolinux/initramfs.igz

copy_kernel: download_kernel $(ISODIR)/isolinux/vmlinuz

$(ISODIR)/isolinux/vmlinuz:
	@echo "Copying kernel"
	@$(MKDIR) -p $(ISODIR)/isolinux
	@$(CP) $(DOWNLOADDIR)/$(OPENWRT_KERNEL) $(ISODIR)/isolinux/vmlinuz

copy_isolinux_files: $(WRKDIR)/.copy_isolinux_files_done

$(WRKDIR)/.copy_isolinux_files_done:
	@echo "Copying isolinux files"
	@for FILE in $(ISOLINUX_FILES); do \
	$(CP) -f $(ISOLINUXDIR)/$$FILE $(ISODIR)/isolinux/$$FILE; \
	 done
	@$(CP) -f $(ISOLINUX_CFG) $(ISODIR)/isolinux/isolinux.cfg
	@$(CP) -f $(ISOLINUX_BOOTTXT) $(ISODIR)/isolinux/boot.txt
	@$(TOUCH) $(WRKDIR)/.copy_isolinux_files_done

customize_rootfs: remove_packages add_packages copy_configuration_files set_rootpw host_key banner

generate_initramfs: download_rootfs_image extract_rootfs customize_rootfs $(ISODIR)/isolinux/initramfs.igz

iso: generate_initramfs copy_kernel copy_isolinux_files $(OUTPUT_ISO)

$(OUTPUT_ISO):
	@echo "Generating $(OUTPUT_ISO)"
	@$(MKISOFS) -quiet -r -T -J -V "mfslinux" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 5 -boot-info-table -o $(OUTPUT_ISO) $(ISODIR)

clean-download:
	@if [ "$(DOWNLOADDIR)" != "/" ]; then $(RM) -rf $(DOWNLOADDIR); fi

clean:
	@if [ "$(WRKDIR)" != "/" ]; then $(RM) -rf $(WRKDIR); fi
	@$(RM) -f $(OUTPUT_ISO)

clean-all: clean clean-download
