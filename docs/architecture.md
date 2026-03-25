# Technical Report: ACM Power Management Architecture Decision
## Why Direct Redfish Replaces BareMetalHost spec.online for Assisted Installer Deployments

**Project:** SNO Loadshedding Automation  
**Date:** March 2026  
**Author:** Daniel Leite De Abreu  
**Status:** Approved

---

## 1. Executive Summary

During the implementation of automated power management for lab1 and lab2 Single Node
OpenShift (SNO) clusters, the team encountered a fundamental architectural constraint
in how Red Hat Advanced Cluster Management (ACM) and the Assisted Installer manage
BareMetalHost (BMH) objects after cluster provisioning.

The original design used the Kubernetes `BareMetalHost` resource's `spec.online` field
to trigger graceful shutdown and power restoration via the `baremetal-operator`. This
approach works correctly for clusters provisioned via the bare metal IPI
(Installer-Provisioned Infrastructure) path, but is **incompatible** with clusters
deployed through ACM's Assisted Installer / Host Inventory workflow.

The solution is to replace the `BareMetalHost spec.online` power control with **direct
Redfish API calls** issued from the hub cluster. This document explains why, and
confirms that graceful shutdown behaviour is fully preserved.

---

## 2. Background — Original Design

The original ACM shutdown policy was designed to power off managed SNO clusters by
patching the `BareMetalHost` object:

```yaml
spec:
  online: false   # baremetal-operator issues IPMI/Redfish power-off
```

When `spec.online` is set to `false`, the `baremetal-operator` detects the change,
calls the node's BMC (Baseboard Management Controller) via Redfish or IPMI, and
powers off the physical or virtual machine.

This is the **industry standard approach** for clusters provisioned via the full bare
metal IPI installer, where `baremetal-operator` has full ownership of the BMH from
day one.

---

## 3. The Problem — Assisted Installer BMH Ownership

When a cluster is installed through **ACM's Host Inventory / Assisted Installer**
workflow, a component called the **Assisted Service** runs on the hub cluster and
manages the entire provisioning lifecycle. After installation completes, the Assisted
Service does not release ownership of the BMH. Instead, it deliberately locks the
BMH by setting two Kubernetes annotations:

```
baremetalhost.metal3.io/detached: "assisted-service-controller"
baremetalhost.metal3.io/paused:   "assisted-service-controller"
```

These annotations cause the `baremetal-operator` to completely ignore the BMH:

```
controllers.BareMetalHost: "host is paused, no work to do"
controllers.BareMetalHost: "the host is detached, not running reconciler"
```

Any attempt to remove these annotations is immediately reversed by the Assisted
Service controller, which actively watches all BMHs associated with an InfraEnv and
resets its annotations within seconds.

As a result, patching `spec.online: false` on the BMH has **no effect** — the
`baremetal-operator` never processes the change because it is blocked from
reconciling the resource.

---

## 4. Why the Assisted Service Keeps Ownership

This behaviour is intentional and by design. The Assisted Service retains BMH
ownership for the following reasons:

### 4.1 Day-2 Operations
The Assisted Service keeps control of the BMH so it can perform ongoing operations
such as node re-provisioning, cluster expansion, and host replacement — all driven
from the ACM hub without requiring manual intervention on the managed cluster.

### 4.2 Conflict Prevention
The `baremetal-operator` is a general-purpose controller. Without the detached and
paused annotations, it would reconcile the BMH on its own schedule, potentially
sending unexpected power commands or attempting to re-provision a healthy running
node. The Assisted Service prevents this by maintaining exclusive ownership.

### 4.3 InfraEnv Relationship
BMHs provisioned through the Assisted Installer remain linked to their
`InfraEnvironment` resource. The Assisted Service continuously watches all BMHs
belonging to an InfraEnv and actively manages their lifecycle. This relationship
persists for the lifetime of the cluster.

---

## 5. Industry Standard for Assisted Installer Deployments

Red Hat's telco and edge computing documentation confirms that for SNO clusters
deployed via the Assisted Installer at scale — such as 5G RAN (Radio Access Network)
edge sites — the recommended power management approach is **direct BMC/Redfish
control from the hub cluster**, not BMH `spec.online`.

The rationale is:
- Edge SNO nodes may have limited or intermittent connectivity to the hub
- The hub must be able to power nodes on and off independently of the managed
  cluster's health
- Direct Redfish/IPMI is more reliable than depending on Kubernetes controller
  reconciliation loops

The `BareMetalHost spec.online` approach is the standard for **IPI-provisioned**
clusters where `baremetal-operator` has full ownership. For **Assisted Installer**
deployments, direct Redfish/IPMI is the correct and recommended pattern.

---

## 6. Solution — Direct Redfish Power Control

The revised ACM policy replaces the `BareMetalHost spec.online` field with a
Kubernetes `Job` that runs on the hub cluster and issues Redfish API calls directly
to the virtual BMC (sushy-emulator in this lab environment, physical iLO/iDRAC/BMC
in production).

### 6.1 Shutdown sequence

```
ACM Policy (enabled by EDA when loadshedding approaches)
    │
    ├── Step 1: ConfigurationPolicy → cordon SNO node
    │             sets node.spec.unschedulable: true
    │             (standard Kubernetes, unaffected by BMH ownership)
    │
    ├── Step 2: ConfigurationPolicy → drain Job
    │             oc adm drain — evicts all non-daemonset pods gracefully
    │             waits for completion before proceeding
    │
    └── Step 3: Job on hub → direct Redfish power-off
                  curl -X POST https://<bmc>/redfish/v1/Systems/<id>/Actions/
                       ComputerSystem.Reset -d '{"ResetType":"GracefulShutdown"}'
```

### 6.2 Restore sequence

```
ACM Policy (enabled by EDA when loadshedding window ends)
    │
    ├── Step 1: Job on hub → direct Redfish power-on
    │             curl -X POST ... -d '{"ResetType":"On"}'
    │
    ├── Step 2: Wait for node to boot and API server to become healthy
    │
    └── Step 3: ConfigurationPolicy → uncordon node
                  sets node.spec.unschedulable: false
```

### 6.3 Graceful shutdown confirmation

The shutdown remains **fully graceful**. The change from `BMH spec.online` to direct
Redfish only affects the final hardware power-off step. Steps 1 and 2 — cordon and
drain — are pure Kubernetes operations that are completely unaffected by the BMH
ownership issue. Workloads are always evicted cleanly before the power-off command
is issued.

---

## 7. Lab Environment — Virtual BMC via sushy

In this lab environment, the physical BMC is replaced by `sushy-emulator`, an
OpenStack project that provides a Redfish-compatible API backed by libvirt/KVM. This
means:

- The Redfish endpoint for lab1 is:
  `https://192.168.22.157:8000/redfish/v1/Systems/bca393c5-d932-42ab-9c37-a6f19d4322f8`
- Power on/off commands are translated by sushy into `virsh start` / `virsh destroy`
  calls on the KVM hypervisor
- The behaviour is identical to a physical Redfish BMC from ACM's perspective
- In production with physical servers, the only change would be the endpoint URL
  pointing to the real iLO, iDRAC, or other BMC

---

## 8. Impact Assessment

| Aspect | Original design | Revised design |
|--------|----------------|----------------|
| Power off mechanism | BMH spec.online via baremetal-operator | Direct Redfish API call |
| Graceful drain | ConfigurationPolicy Job | ConfigurationPolicy Job (unchanged) |
| Cordon | ConfigurationPolicy | ConfigurationPolicy (unchanged) |
| Works with Assisted Installer | No | Yes |
| Works with IPI provisioned | Yes | Yes |
| Dependency on baremetal-operator | Yes | No |
| Dependency on BMH ownership | Yes | No |
| Production ready | No (for this setup) | Yes |

---

## 9. Conclusion

The change from `BareMetalHost spec.online` to direct Redfish power control is not a
workaround — it is the architecturally correct approach for SNO clusters provisioned
via the ACM Assisted Installer. The Assisted Service's deliberate ownership of the
BMH after provisioning is a design feature, not a bug. Working around it would
risk interfering with ACM's day-2 management capabilities.

The revised policy maintains full graceful shutdown behaviour through the Kubernetes
cordon and drain steps, and achieves reliable hardware power control through the
industry-standard direct Redfish interface — the same approach used in production
telco 5G RAN deployments at scale.

---

## 10. References

- Red Hat ACM documentation: Managing bare metal clusters
- Red Hat OpenShift 4.x: Deploying distributed units at scale (RAN/ZTP)
- OpenStack sushy-tools: Virtual Redfish BMC documentation
- Metal3 project: BareMetalHost detached annotation specification
- Red Hat Assisted Installer: Post-installation BMH lifecycle management
EOF
