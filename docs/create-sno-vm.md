# Creating the SNO VM on KVM

This document explains how to create the **SNO virtual machine** used for the Assisted Installer / BareMetalHost environment.

The VM is created using **virt-install** from the **libvirt / KVM** toolset.

## VM Creation Command

```bash
virt-install \
--name sno-spoke \
--ram 16384 \
--vcpus 8 \
--os-variant rhel9.0 \
--disk size=100,format=qcow2,bus=virtio,sparse=true \
--network bridge=bridge0,model=virtio \
--boot hd,cdrom \
--graphics none \
--noautoconsole
```

## Parameter Explanation

| Parameter                  | Description                             |
| -------------------------- | --------------------------------------- |
| `--name sno-spoke`         | Name of the virtual machine             |
| `--ram 16384`              | Allocates 16GB of RAM                   |
| `--vcpus 8`                | Allocates 8 virtual CPUs                |
| `--os-variant rhel9.0`     | Optimizes VM settings for RHEL 9        |
| `--disk size=100`          | Creates a 100GB disk                    |
| `format=qcow2`             | Uses QCOW2 disk format                  |
| `bus=virtio`               | Uses VirtIO for better disk performance |
| `sparse=true`              | Allocates disk space on demand          |
| `--network bridge=bridge0` | Connects VM to the bridge network       |
| `model=virtio`             | Uses VirtIO network driver              |
| `--boot hd,cdrom`          | Allows boot from disk or ISO            |
| `--graphics none`          | Disables graphical console              |
| `--noautoconsole`          | Prevents automatic console attachment   |

## Requirements

Before running this command ensure:

* KVM virtualization is enabled
* libvirt is installed and running
* bridge network `bridge0` exists
* sufficient CPU/RAM resources are available

## Example Use Case

This VM is used as a **Single Node OpenShift (SNO) spoke cluster** in a lab environment for testing:

* OpenShift Assisted Installer
* BareMetalHost provisioning
* Redfish virtual media boot
* Open Cluster Management (ACM)

## Verification

After creating the VM, verify it exists:

```bash
virsh list --all
```
