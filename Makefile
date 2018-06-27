# mfslinux
#
# Copyright (c) 2018 Martin Matuska <mm at FreeBSD.org>

WGET?=		$(shell which wget)
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
CPIO?=		$(shell which cpio)
MKISOFS?=	$(shell which mkisofs)
OPENSSL?=	$(shell which openssl)
CHROOT?=	$(shell which chroot)
TOUCH?=		$(shell which touch)

CURDIR?=	$(shell pwd)
CONFIGDIR?=	$(CURDIR)/config
WRKDIR?=	$(CURDIR)/work
ISOLINUXDIR?=	$(CURDIR)/isolinux
DOWNLOADDIR?=	$(CURDIR)/download
ISODIR?=	$(WRKDIR)/iso

OPENWRT_ROOTDIR?=	$(WRKDIR)/openwrt_root
OPENWRT_IMGDIR?=	$(WRKDIR)/openwrt_root_img
OPENWRT_ROOT_TAR?=	$(WRKDIR)/openwrt_root.tar

OPENWRT_DOWNLOAD_URL=	https://downloads.openwrt.org/releases/18.06.0-rc1/targets/x86/64/
OPENWRT_ROOTFS_IMAGE=	openwrt-18.06.0-rc1-x86-64-rootfs-ext4.img
OPENWRT_KERNEL=		openwrt-18.06.0-rc1-x86-64-vmlinuz

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
	@cd $(DOWNLOADDIR) && $(WGET) $(OPENWRT_DOWNLOAD_URL)/$(OPENWRT_KERNEL)

# Download and extract rootfs image
$(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE):
	@echo "Downloading OpenWRT rootfs image"
	@cd $(DOWNLOADDIR) && $(WGET) $(OPENWRT_DOWNLOAD_URL)/$(OPENWRT_ROOTFS_IMAGE).gz
	@echo "Extracting OpenWRT rootfs image"
	@cd $(DOWNLOADDIR) && $(GZIP) -d $(OPENWRT_ROOTFS_IMAGE).gz

# Mount rootfs image
create_rootfs_tar: $(OPENWRT_ROOT_TAR)

$(OPENWRT_ROOT_TAR):
	@echo "Extracting openwrt root"
	@$(MKDIR) -p $(OPENWRT_IMGDIR)
	@if ! $(LOSETUP) -j $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(GREP) $(OPENWRT_ROOTFS_IMAGE) > /dev/null; then \
	 $(LOSETUP) -f $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE); \
	 fi
	@LOOPDEV=`$(LOSETUP) -j $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(HEAD) -1 | $(AWK) -F: '{ print $$1 }'`; \
	 if ! $(MOUNT) | $(GREP) $$LOOPDEV > /dev/null; then \
	 $(MOUNT) -o loop,ro $$LOOPDEV $(OPENWRT_IMGDIR); \
	 fi
	@$(TAR) -c -f $(OPENWRT_ROOT_TAR) -C $(OPENWRT_IMGDIR) .
	@$(UMOUNT) $(OPENWRT_IMGDIR)
	@$(RMDIR) $(OPENWRT_IMGDIR)
	@LOOPDEV=`$(LOSETUP) -j $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(HEAD) -1 | $(AWK) -F: '{ print $$1 }'`; \
	 $(LOSETUP) -d $$LOOPDEV

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

copy_configuration_files: $(WRKDIR)/.copy_configuration_files_done

$(WRKDIR)/.copy_configuration_files_done:
	@echo "Coypying configuration files"
	@for FILE in $(CONFIGFILES); do \
	$(CP) -f $(CONFIGDIR)/$$FILE $(WRKDIR)/openwrt_root/etc/config/; \
	done
	@$(TOUCH) $(WRKDIR)/.copy_configuration_files_done

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

customize_rootfs: copy_configuration_files set_rootpw

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
