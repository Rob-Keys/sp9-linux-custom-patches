# Surface Pro 9 Linux Compatibility Setup

This document contains other miscellaneous changes needed to make the Surface Pro 9 compatible with the Linux kernel.

## 1. Install linux-surface Kernel

The linux-surface project provides kernel patches and drivers specifically for Microsoft Surface devices.

**Repository:** https://github.com/linux-surface/linux-surface

Follow the installation instructions from the repository to install the patched kernel and Surface-specific drivers.

## 2. GRUB Configuration Changes

Modify the GRUB bootloader configuration to ensure proper ACPI compatibility.

**File:** `/etc/default/grub`

**Change the following line:**

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash acpi=force acpi_osi=! \"acpi_osi=Windows 2020\""
```

**Parameters explained:**
- `acpi=force` - Forces ACPI support even if the BIOS is dated before 2000
- `acpi_osi=!` - Disables all OS interface strings
- `acpi_osi="Windows 2020"` - Makes the firmware think it's running Windows 2020

These in combination make the lid open/close and s2idle sleeping more reliable.

**After making changes, update GRUB:**

```bash
sudo update-grub
```

Then reboot for the changes to take effect.
