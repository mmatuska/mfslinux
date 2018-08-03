# mfslinux build instructions

Copyright (c) 2018 Martin Matuska <mm at FreeBSD.org>

## Configuration
Read hints in the default configuration files in the config/default directory.
You may copy these files to the config directory and make modifications
to suit your needs.

## Additional packages and files
If you want any additional packages downloaded and installed, you need to copy
the package list from config/default to config and edit it.

## Requirements
You need openssl, git and mkisofs (sysutils/cdrtools).
On FreeBSD you additionally need opkg-cl (archivers/opkg).

## Creating image

Simply run make on Linux or gmake on FreeBSD

##Examples

1. mfslinux.iso bootable ISO file:

  ```bash
  make 
  ```
