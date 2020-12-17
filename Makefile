# mfslinux
#
# Copyright (c) 2020 Martin Matuska <mm at matuska dot org>
#
MFSLINUX_VERSION?=	0.1.8

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
LN?=		$(shell which ln)
GIT?=		$(shell which git)
MKISOFS?=	$(shell which mkisofs || which genisoimage)
LS?=		$(shell which ls)
FILE?=		$(shell which file)
BSDTAR?=	$(shell which bsdtar)
BUILD_OS?=	$(shell uname)

ifeq ($(BUILD_OS),FreeBSD)
WGET?=		$(shell which fetch)
WGET_ARGS?=	-q
OPKG_CL?=	$(shell which opkg-cl)
else
WGET?=		$(shell which wget)
WGET_ARGS?=	-nv
endif

CURDIR?=	$(shell pwd)
CONFIGDIR?=	$(CURDIR)/config
WRKDIR?=	$(CURDIR)/work
ISOLINUXDIR?=	$(CURDIR)/isolinux
DOWNLOADDIR?=	$(CURDIR)/download
ISODIR?=	$(WRKDIR)/iso

OPENWRT_ROOTDIR?=	$(WRKDIR)/openwrt_root
OPENWRT_IMGDIR?=	$(WRKDIR)/openwrt_root_img

OPENWRT_VERSION=	19.07.5
OPENWRT_KERNEL_VERSION=	4.14.209
OPENWRT_TARGET_URL=	https://downloads.openwrt.org/releases/$(OPENWRT_VERSION)/targets/x86/64/
OPENWRT_PACKAGES_URL=	http://downloads.openwrt.org/releases/$(OPENWRT_VERSION)/packages/x86_64/
OPENWRT_ROOTFS_TAR=	openwrt-$(OPENWRT_VERSION)-x86-64-generic-rootfs.tar.gz
OPENWRT_KERNEL=		openwrt-$(OPENWRT_VERSION)-x86-64-vmlinuz

OPENWRT_PACKAGES_REMOVE?=	$(CONFIGDIR)/openwrt_packages_remove
OPENWRT_PACKAGES_ADD?=		$(CONFIGDIR)/openwrt_packages_add
OPENWRT_TARGET_PACKAGES_ADD?=	$(CONFIGDIR)/openwrt_target_packages_add

CONFIGFILES=	network system
ISOLINUX_CFG=	$(ISOLINUXDIR)/isolinux.cfg
ISOLINUX_BOOTTXT=	$(ISOLINUXDIR)/boot.txt
ISOLINUX_FILES=	isolinux.bin ldlinux.c32

ROOTPW?=	mfsroot
ROOT_SHELL?=	/bin/bash

GIT_REVISION=	$(shell $(GIT) rev-parse --short HEAD)

OUTPUT_ISO?=	mfslinux-$(MFSLINUX_VERSION)-$(GIT_REVISION).iso
ARTIFACT?=	mfslinux.iso
OUTPUT_ISO_LABEL?=	mfslinux

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

VERIFY_STRING=	ISO 9660 CD-ROM filesystem data '$(OUTPUT_ISO_LABEL)' (bootable)

all: iso

download: $(DOWNLOADDIR) download_kernel download_rootfs_tar

$(WRKDIR):
	$(_v)$(MKDIR) -p $(WRKDIR)

$(DOWNLOADDIR):
	$(_v)$(MKDIR) -p $(DOWNLOADDIR)

download_kernel: $(DOWNLOADDIR) $(DOWNLOADDIR)/$(OPENWRT_KERNEL)
$(DOWNLOADDIR)/$(OPENWRT_KERNEL):
	$(_v)echo "Downloading OpenWrt kernel"
	$(_v)cd $(DOWNLOADDIR) && $(WGET) $(WGET_ARGS) \
		$(OPENWRT_TARGET_URL)/$(OPENWRT_KERNEL)

download_rootfs_tar: $(DOWNLOADDIR) $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_TAR)
$(DOWNLOADDIR)/$(OPENWRT_ROOTFS_TAR):
	$(_v)echo "Downloading OpenWrt rootfs"
	$(_v)cd $(DOWNLOADDIR) && $(WGET) $(WGET_ARGS) \
		$(OPENWRT_TARGET_URL)/$(OPENWRT_ROOTFS_TAR)

extract_rootfs_tar: $(WRKDIR)/.extract_rootfs_tar_done
$(WRKDIR)/.extract_rootfs_tar_done:
	$(_v)$(MKDIR) -p $(OPENWRT_ROOTDIR)
	$(_v)$(TAR) -x -f $(DOWNLOADDIR)/$(OPENWRT_ROOTFS_TAR) -C $(OPENWRT_ROOTDIR)
	$(_v)$(TOUCH) $(WRKDIR)/.extract_rootfs_tar_done

deploy_init: $(OPENWRT_ROOTDIR)/init
$(OPENWRT_ROOTDIR)/init:
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
	PACKAGES_ADD=`echo $$PACKAGES_ADD | $(SED) -e \
	  "s,%%KERNEL_VERSION%%,$(OPENWRT_KERNEL_VERSION),g"`; \
	for PKG in $$PACKAGES_ADD; do \
	if [ ! -f $(DOWNLOADDIR)/$${PKG} ]; then \
	echo "Downloading: $${PKG}"; \
	cd $(DOWNLOADDIR) && $(WGET) $(WGET_ARGS) \
		$(OPENWRT_TARGET_URL)/packages/$${PKG}; \
	if [ "$$?" != "0" ]; then rm -f  $(DOWNLOADDIR)/$${PKG}; exit 1; fi; \
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
	cd $(DOWNLOADDIR) && $(WGET) $(WGET_ARGS) \
		$(OPENWRT_PACKAGES_URL)/$${PKG}; \
	if [ "$$?" != "0" ]; then rm -f $(DOWNLOADDIR)/$${PKGNAME}; exit 1; fi; \
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
	PACKAGES_ADD=`echo $$PACKAGES_ADD | $(SED) -e \
	  "s,%%KERNEL_VERSION%%,$(OPENWRT_KERNEL_VERSION),g"`; \
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
	$(_v)for file in $(CONFIGFILES); do \
	if [ -f $(CONFIGDIR)/$$file ]; then \
		$(CP) -f $(CONFIGDIR)/$$file $(WRKDIR)/openwrt_root/etc/config/$$file; \
	elif [ -f $(CONFIGDIR)/default/$$file ]; then \
		$(CP) -f $(CONFIGDIR)/default/$$file $(WRKDIR)/openwrt_root/etc/config/$$file; \
	else \
		echo "Missing configuration file: $(CONFIGDIR)/$$file"; \
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
	$(_v)echo "Appending mfslinux info to OpenWrt banner"
	$(_v)echo " mfslinux $(MFSLINUX_VERSION) $(GIT_REVISION)" >> $(OPENWRT_ROOTDIR)/etc/banner
	$(_v)echo " -----------------------------------------------------" >> \
		$(OPENWRT_ROOTDIR)/etc/banner
	$(_v)$(TOUCH) $(WRKDIR)/.banner_done

authorized_keys: $(WRKDIR)/.authorized_keys_done
$(WRKDIR)/.authorized_keys_done:
	$(_v)if [ -f "$(CONFIGDIR)/authorized_keys" ]; then \
		$(CP) $(CONFIGDIR)/authorized_keys $(OPENWRT_ROOTDIR)/etc/dropbear/authorized_keys; \
	fi
	$(_v)$(TOUCH) $(WRKDIR)/.authorized_keys_done

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
	$(_v)for file in $(ISOLINUX_FILES); do \
	$(CP) -f $(ISOLINUXDIR)/$$file $(ISODIR)/isolinux/$$file; \
	 done
	$(_v)$(CP) -f $(ISOLINUX_CFG) $(ISODIR)/isolinux/isolinux.cfg
	$(_v)$(SED) -e "s,%%MFSLINUX_VERSION%%,$(MFSLINUX_VERSION) $(GIT_REVISION),g" \
   		-e "s,%%OPENWRT_VERSION%%,$(OPENWRT_VERSION),g" \
		$(ISOLINUX_BOOTTXT) > $(ISODIR)/isolinux/boot.txt
	$(_v)$(TOUCH) $(WRKDIR)/.copy_isolinux_files_done

customize_rootfs: deploy_init remove_packages add_packages copy_configuration_files set_root_pw set_root_shell host_key banner authorized_keys

generate_initramfs: download_rootfs_tar extract_rootfs_tar customize_rootfs $(ISODIR)/isolinux/initramfs.igz

iso: generate_initramfs copy_kernel copy_isolinux_files $(OUTPUT_ISO)
$(OUTPUT_ISO):
	$(_v)echo "Generating $(OUTPUT_ISO)"
	$(_v)if [ "$(MKISOFS)" = "" ]; then echo "Error: mkisofs or genisoimage missing"; exit 1; fi
	$(_v)$(MKISOFS) -quiet -r -T -J -iso-level 2 -V "$(OUTPUT_ISO_LABEL)" \
		-b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 \
		-boot-info-table -o $(OUTPUT_ISO) $(ISODIR)

check: iso
	$(_v)echo Examining output ISO file
	$(_v)$(LS) -l $(OUTPUT_ISO)
	$(_v)VERIFY="`$(FILE) -b $(OUTPUT_ISO) | $(GREP) -o 'ISO 9660.*'`"; \
		echo $$VERIFY; \
		if [ "$$VERIFY" != "$(VERIFY_STRING)" ]; then \
			exit 1; \
		fi
	$(_v)$(BSDTAR) -t -v -f $(OUTPUT_ISO)

artifact: iso $(ARTIFACT)
$(ARTIFACT): $(OUTPUT_ISO)
	$(_v)echo Symlinking ISO file
	$(_v)$(LN) -s $(OUTPUT_ISO) $(ARTIFACT)

clean-download:
	$(_v)if [ "$(DOWNLOADDIR)" != "/" ]; then $(RM) -rf $(DOWNLOADDIR); fi

clean:
	$(_v)if [ "$(WRKDIR)" != "/" ]; then $(RM) -rf $(WRKDIR); fi
	$(_v)$(RM) -f $(OUTPUT_ISO) $(ARTIFACT)

clean-all: clean clean-download
