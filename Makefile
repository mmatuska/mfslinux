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
AWK?=		$(shell which awk)
HEAD?=		$(shell which head)
TAR?=		$(shell which tar)
CP?=		$(shell which cp)
FIND?=		$(shell which find)
CPIO?=		$(shell which cpio)

CURDIR?=	$(shell pwd)
CONFIGDIR?=	$(CURDIR)/config
WRKDIR?=	$(CURDIR)/work
ISOLINUXDIR?=	$(CURDIR)/isolinux
DOWNLOADDIR?=	$(WRKDIR)/download
ISODIR?=	$(WRKDIR)/iso
OPENWRT_ROOTDIR?=	$(WRKDIR)/openwrt_root

OPENWRT_DOWNLOAD_URL=	https://downloads.openwrt.org/releases/18.06.0-rc1/targets/x86/64/
OPENWRT_ROOTFS_IMAGE=	openwrt-18.06.0-rc1-x86-64-rootfs-ext4.img
OPENWRT_KERNEL=		openwrt-18.06.0-rc1-x86-64-vmlinuz

CONFIGFILES=	network
ISOLINUX_CFG=	$(ISOLINUXDIR)/isolinux.cfg
ISOLINUX_BOOTMSG=	$(ISOLINUXDIR)/boot.txt
ISOLINUX_FILES=	isolinux.bin ldlinux.c32

all: initramfs
	@echo "ok"

download: $(DOWNLOADDIR) download_kernel download_rootfs_image

$(WRKDIR):
	@$(MKDIR) -p $(WRKDIR)

$(DOWNLOADDIR):
	@$(MKDIR) -p $(DOWNLOADDIR)

download_kernel: $(DOWNLOADDIR) $(DOWNLOADDIR)/$(OPENWRT_KERNEL)

download_rootfs_image: $(DOWNLOADDIR) $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE)

$(DOWNLOADDIR)/$(OPENWRT_KERNEL):
	@cd $(DOWNLOADDIR) && $(WGET) $(OPENWRT_DOWNLOAD_URL)/$(OPENWRT_KERNEL)

# Download and extract rootfs image
$(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE):
	@cd $(DOWNLOADDIR) && $(WGET) $(OPENWRT_DOWNLOAD_URL)/$(OPENWRT_ROOTFS_IMAGE).gz
	@cd $(DOWNLOADDIR) && $(GZIP) -d $(OPENWRT_ROOTFS_IMAGE).gz

# Mount rootfs image
prepare_rootfs_image: $(WRKDIR)/openwrt_root/usr

$(WRKDIR)/openwrt_root/usr:
	@$(MKDIR) -p $(WRKDIR)/openwrt_root $(WRKDIR)/openwrt_root_img
	@if ! $(LOSETUP) -j $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(GREP) $(OPENWRT_ROOTFS_IMAGE) > /dev/null; then \
	 $(LOSETUP) -f --show $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE); \
	 fi
	@LOOPDEV=`$(LOSETUP) -j $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(HEAD) -1 | $(AWK) -F: '{ print $$1 }'`; \
	 if ! $(MOUNT) | $(GREP) $$LOOPDEV > /dev/null; then \
	 $(MOUNT) -o loop,ro $$LOOPDEV $(WRKDIR)/openwrt_root_img; \
	 fi
	@$(TAR) -c -f $(WRKDIR)/openwrt_root.tar -C $(WRKDIR)/openwrt_root_img .
	@$(UMOUNT) $(WRKDIR)/openwrt_root_img
	@$(RMDIR) $(WRKDIR)/openwrt_root_img
	@LOOPDEV=`$(LOSETUP) -j $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_IMAGE) | $(HEAD) -1 | $(AWK) -F: '{ print $$1 }'`; \
	 $(LOSETUP) -d $$LOOPDEV
	@$(TAR) -x -f $(WRKDIR)/openwrt_root.tar -C $(WRKDIR)/openwrt_root

copy_configuration_files:
	@for FILE in $(CONFIGFILES); do \
	$(CP) -f $(CONFIGDIR)/$$FILE $(WRKDIR)/openwrt_root/etc/config/; \
	done

generate_initramfs: download_rootfs_image prepare_rootfs_image copy_configuration_files $(ISODIR)/isolinux/initramfs.igz

$(ISODIR)/isolinux/initramfs.igz: 
	@$(MKDIR) -p $(ISODIR)/isolinux
	@cd $(WRKDIR)/openwrt_root && $(FIND) . | $(CPIO) -H newc -o | $(GZIP) > $(ISODIR)/isolinux/initramfs.igz

copy_kernel: download_kernel $(ISODIR)/isolinux/vmlinuz

$(ISODIR)/isolinux/vmlinuz:
	@$(MKDIR) -p $(ISODIR)/isolinux
	@$(CP) $(DOWNLOADDIR)/$(OPENWRT_KERNEL) $(ISODIR)/isolinux/vmlinuz

copy_isolinux_files:
	@for FILE in $(ISOLINUXFILES); do \
	echo $FILE; \
	$(CP) -f $(ISOLINUXDIR)/$$FILE $(ISODIR)/isolinux/$$FILE; \
	 done
	@$(CP) -f $(ISOLINUX_CFG) $(ISODIR)/isolinux/isolinux.cfg
	@$(CP) -f $(ISOLINUX_BOOTTXT) $(ISODIR)/isolinux/boot.txt

initramfs: generate_initramfs

isolinux: generate_initramfs copy_kernel copy_isolinux_files
