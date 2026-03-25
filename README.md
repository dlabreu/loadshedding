# SNO Loadshedding Automation

Automated graceful shutdown and restore of OpenShift Single Node (SNO) lab clusters
during Eskom load shedding events, using:

- **EskomSePush API** — schedule monitoring
- **Event-Driven Ansible (EDA)** — event detection and triggering
- **Ansible Automation Platform (AAP)** — notify ACM to act
- **Red Hat Advanced Cluster Management (ACM)** — cluster lifecycle (cordon, drain, power off/on)
- **sushy-emulator** — virtual Redfish BMC backed by libvirt/KVM

> See `docs/architecture.md` for the full design rationale, including why direct
> Redfish replaces the BareMetalHost `spec.online` approach for Assisted Installer
> deployed clusters.

---

## Architecture

```
EskomSePush API
      │  poll every 5 min
      ▼
   EDA (hub)
      │  trigger on approaching/ended events
      ▼
AAP Playbook
      │  PATCH ACM policy disabled=false
      ▼
ACM Hub — 4 policies
      ├── loadshedding-shutdown-policy    → lab1/lab2: cordon + drain Job
      ├── loadshedding-poweroff-hub-policy → hub: curl sushy Redfish power-off
      ├── loadshedding-restore-policy     → lab1/lab2: uncordon + operator check
      └── loadshedding-poweron-hub-policy  → hub: curl sushy Redfish power-on
                        │
                        ▼
               sushy-emulator (Redfish API)
                        │
                        ▼
               libvirt / KVM
               ├── lab1 VM  ← powers off / on
               └── lab2 VM  ← powers off / on (when provisioned)
```

EDA and AAP are notification-only — ACM owns all cluster lifecycle.
Power control uses direct Redfish API calls to sushy rather than
`BareMetalHost spec.online` because the Assisted Installer retains
permanent ownership of BMH objects after provisioning.

---

## Environment

| Component | Details |
|-----------|---------|
| Hub cluster | SNO — `api.sno.abreu.io` — ACM 2.16 + AAP 2.6 operator |
| lab1 | SNO KVM VM — `api.lab1.abreu.io` — `192.168.22.141` |
| lab2 | SNO KVM VM — to be provisioned |
| Fedora host | KVM hypervisor — `192.168.22.157` — sushy on port 8000 |
| sushy lab1 UUID | `bca393c5-d932-42ab-9c37-a6f19d4322f8` |
| Base domain | `abreu.io` |
| DNS | All records pointing to `192.168.22.141` |

---

## Repository layout

```
loadshedding/
├── acm-policies/
│   ├── shutdown-policy.yml     # loadshedding-shutdown-policy (lab1/lab2)
│   │                           # loadshedding-poweroff-hub-policy (hub)
│   └── restore-policy.yml      # loadshedding-restore-policy (lab1/lab2)
│                               # loadshedding-poweron-hub-policy (hub)
├── aap/
│   ├── playbooks/
│   │   ├── notify_acm_shutdown.yml   # enables shutdown policy pair
│   │   └── notify_acm_restore.yml    # enables restore policy pair
│   └── eda/
│       ├── rulebook.yml              # EDA rulebook watching EskomSePush
│       └── sources/
│           └── eskomsepush_source.py # custom EDA event source plugin
├── dashboard/
│   └── index.html              # web dashboard (power state + schedule)
├── docs/
│   ├── architecture.md         # design rationale — why direct Redfish
│   ├── SECRETS.md              # credential index (no actual values)
│   ├── create-sno-vm.md        # how to create lab VMs with KVM + sushy
│   └── install-sushy-emulator.md
├── hack/
│   └── hack.sh
├── README.md
├── .gitignore
└── Makefile
```

---

## Prerequisites

| Component | Requirement |
|-----------|-------------|
| Hub cluster | OCP SNO, ACM 2.16+, AAP 2.6+ operator |
| lab1 / lab2 | OCP SNO as KVM VMs provisioned via ACM Assisted Installer |
| sushy-emulator | Running on Fedora KVM host, SSL enabled, libvirt backend |
| Fedora host | libvirt/KVM, bridge0 on physical network |
| EskomSePush | API token from https://eskomsepush.gumroad.com/l/api |
| DNS | Three records per cluster (api, api-int, *.apps) |

---

## Quick start

### 1. Apply ACM policies to the hub

```bash
# Ensure you are logged into the hub
oc login https://api.sno.abreu.io:6443

make apply-policies
```

All 4 policies are created with `disabled: true` — nothing happens to the clusters yet.

### 2. Verify sushy is reachable from the hub network

```bash
make check-power-lab1
# Expected: PowerState: On
```

### 3. Test manual shutdown

```bash
make shutdown-test
# Type YES when prompted
# Then watch:
make check-policies
make check-jobs
make check-power-lab1
```

### 4. Test manual restore

```bash
make restore-test
# Type YES when prompted
# Then watch:
make check-cluster-lab1
```

### 5. Reset to standby state

```bash
make disable-all
make clean-jobs
```

### 6. Set up AAP (automation path)

See AAP setup steps in `docs/architecture.md`.

In AAP — `Automation Execution → Infrastructure → Credential Types` — create the
`Loadshedding Automation` credential type, then follow the full AAP setup guide.

| AAP Job Template | Playbook |
|-----------------|----------|
| `Notify ACM: Shutdown` | `aap/playbooks/notify_acm_shutdown.yml` |
| `Notify ACM: Restore` | `aap/playbooks/notify_acm_restore.yml` |

The notify playbooks enable/disable the correct policy pairs:

**Shutdown:** enables `loadshedding-shutdown-policy` + `loadshedding-poweroff-hub-policy`

**Restore:** enables `loadshedding-restore-policy` + `loadshedding-poweron-hub-policy`

### 7. Set up EDA

- **EDA Project**: point to this repo, `aap/eda/rulebook.yml`
- **Decision Environment**: must include `aiohttp`
- **Extra vars**:
  ```yaml
  eskomsepush_api_token: "your-token"
  eskomsepush_area_id: "capetown-10-atlantis"
  warning_minutes: 30
  poll_interval: 300
  ```

### 8. Deploy the dashboard

```bash
make dashboard-deploy
```

---

## Makefile reference

| Target | Description |
|--------|-------------|
| `make apply-policies` | Apply all 4 policies (disabled by default) |
| `make delete-policies` | Remove all 4 policies |
| `make check-policies` | Show disabled/compliant status |
| `make disable-all` | Emergency reset — disable all 4 policies |
| `make shutdown-test` | Manually trigger shutdown cycle |
| `make restore-test` | Manually trigger restore cycle |
| `make check-power-lab1` | Check lab1 power state via sushy |
| `make check-power-lab2` | Check lab2 power state via sushy |
| `make check-bmh` | Show BareMetalHost status in lab-infra |
| `make check-jobs` | Show running/complete loadshedding Jobs |
| `make clean-jobs` | Delete completed Jobs |
| `make check-cluster-lab1` | Show lab1 ManagedCluster status |
| `make dashboard-deploy` | Deploy dashboard to hub |
| `make lint` | Lint YAML and Python files |

---

## Key design decisions

**Why direct Redfish instead of BareMetalHost spec.online?**

The Assisted Installer / ACM Host Inventory provisioning path causes the Assisted
Service controller to permanently own the BareMetalHost after installation. It sets
`baremetalhost.metal3.io/detached` and `baremetalhost.metal3.io/paused` annotations
that are re-applied immediately if removed. The `baremetal-operator` therefore ignores
all changes to `spec.online`.

Direct Redfish calls to sushy bypass the BMH entirely and are the recommended approach
for Assisted Installer deployments. See `docs/architecture.md` for the full explanation.

**Why 4 policies instead of 2?**

ACM policies targeting managed clusters cannot create resources in the
`open-cluster-management` namespace because that namespace only exists on the hub.
The Redfish power-off/on Jobs must run on the hub (`local-cluster`), so they need
their own policies with a separate PlacementRule targeting `local-cluster`.

---

## Branches

| Branch | Purpose |
|--------|---------|
| `main` | Stable — apply to production |
| `aap` | Active development — AAP + EDA integration |

---

## Credentials

See `docs/SECRETS.md` for the full credential index — what is needed, where each
value lives, and how to rotate them. No actual credential values are stored in this repo.
