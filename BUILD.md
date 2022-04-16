# mfslinux build instructions

Copyright (c) 2022 Martin Matuska <mm at matuska dot de>

## Configuration
Read hints in the default configuration files in the config/default directory.
You may copy these files to the config directory and make modifications
to suit your needs.

## Additional packages and files
If you want any additional packages downloaded and installed, you need to copy
the package list from config/default to config and edit it.

## Requirements

You need to build as root (ext4 image extraction and chrooting is required).

### Linux
 - openssl, git, mkisofs or genisoimage

### FreeBSD
 - git (devel/git), mkisofs (sysutils/cdrtools), opkg-cl (archivers/opkg)
 - linux64 module loaded for opkg chroot

## Creating an image

Simply run make on Linux or gmake on FreeBSD

## Examples

1. create mfslinux.iso bootable ISO file on Linux with a different root password:

  ```bash
  make ROOTPW=testpass
  ```

2. create mfslinux.iso bootable ISO file on FreeBSD with increased verbosity:

  ```bash
  gmake VERBOSE=1
  ```
