# SNO Loadshedding Automation

Automated graceful shutdown and restore of OpenShift Single Node (SNO) lab clusters during Eskom load shedding, using EskomSePush API, Ansible Automation Platform (AAP) with Event-Driven Ansible (EDA), and Red Hat Advanced Cluster Management (ACM).

## Architecture

```
EskomSePush API
      │  poll every 5 min
      ▼
   EDA (hub)
      │  trigger
      ▼
AAP Playbook  ──► PATCH ACM policy (enable/disable)
                        │
                        ▼
                   ACM Hub
                   ├── cordon SNO node
                   ├── drain workloads (Job)
                   └── BareMetalHost.spec.online: false/true
                              │  IPMI
                              ▼
                     lab1 SNO   lab2 SNO
```

EDA/AAP only notify — ACM owns all cluster lifecycle including IPMI power via the `BareMetalHost` API and `baremetal-operator`.

## Repository layout

```
sno-loadshedding/
├── acm-policies/
│   ├── shutdown-policy.yml     # cordon + drain + BMH power-off
│   └── restore-policy.yml      # BMH power-on + uncordon + health check
├── aap/
│   ├── playbooks/
│   │   ├── notify_acm_shutdown.yml
│   │   └── notify_acm_restore.yml
│   └── eda/
│       ├── rulebook.yml
│       └── sources/
│           └── eskomsepush_source.py
├── dashboard/
│   └── index.html
├── docs/
│   ├── architecture.md
│   └── runbook.md
├── README.md
├── .gitignore
├── SECRETS.md          # credential index — no actual values
└── Makefile
```

## Prerequisites

| Component | Requirement |
|-----------|-------------|
| Hub cluster | OCP SNO, ACM 2.9+, AAP 2.4+ with EDA |
| lab1 / lab2 | OCP SNO on bare metal, `baremetal-operator` running |
| BareMetalHost | CR exists in `openshift-machine-api` on each managed cluster |
| IPMI | Accessible from `baremetal-operator` on each cluster |
| EskomSePush | API token from https://eskomsepush.gumroad.com/l/api |

## Quick start

### 1. Find your BareMetalHost name on each cluster

```bash
oc get bmh -n openshift-machine-api --kubeconfig=/path/to/lab1.kubeconfig
oc get bmh -n openshift-machine-api --kubeconfig=/path/to/lab2.kubeconfig
```

Update the BMH name in `acm-policies/shutdown-policy.yml` and `acm-policies/restore-policy.yml` if it differs from the cluster name.

### 2. Find your EskomSePush area ID

```bash
curl -H "Token: YOUR_TOKEN" \
  "https://developer.sepush.co.za/business/2.0/areas_search?text=your+suburb"
```

### 3. Apply ACM policies to the hub

```bash
make apply-policies
```

Both policies start with `disabled: true` — EDA enables them at runtime.

### 4. Create an AAP Project pointing at this repo

In AAP → Projects → Add:
- **SCM type**: Git
- **SCM URL**: `https://github.com/yourorg/sno-loadshedding`
- **SCM branch**: `main`

### 5. Create Job Templates in AAP

| Template name | Playbook |
|---------------|----------|
| `Notify ACM: Shutdown` | `aap/playbooks/notify_acm_shutdown.yml` |
| `Notify ACM: Restore`  | `aap/playbooks/notify_acm_restore.yml`  |

Add the `loadshedding-credentials` credential to both templates (see SECRETS.md).

### 6. Create an EDA Project and Rulebook Activation

- **EDA Project SCM URL**: same repo
- **Rulebook**: `aap/eda/rulebook.yml`
- **Decision environment**: must include `aiohttp` (for the custom source plugin)
- **Extra vars**: set `eskomsepush_api_token` and `eskomsepush_area_id`

### 7. Deploy the dashboard

```bash
make dashboard-deploy
```

## Day-2 operations

See `docs/runbook.md` for procedures covering:
- Manual shutdown/restore bypass
- EDA not triggering
- Cluster not coming back after a window
- Rotating credentials

## Branches

| Branch | Purpose |
|--------|---------|
| `main` | Production — synced to hub via ArgoCD/ACM Channel |
| `dev`  | Test changes before promoting to main |
