# SNO Loadshedding Dashboard

A lightweight status dashboard for the SNO loadshedding automation system.
Shows real cluster power state, EskomSePush schedule, and countdown to the
next loadshedding window.

Deployed as a static HTML file served by a Python http.server pod on the hub cluster.

---

## What it shows

- **lab1** — real power state checked via OCP API health endpoint
- **lab2** — shown as `Not deployed` until provisioned
- **Next loadshedding window** — live countdown timer
- **Today's outage timeline** — visual bar showing the day's schedule
- **Upcoming events** — table from EskomSePush schedule

---

## How the data is collected

| Data | Source | How | Interval |
|------|--------|-----|----------|
| lab1 power state | `api.lab1.abreu.io:6443/readyz` | Direct browser fetch (no-cors) | Every 2 minutes |
| EskomSePush schedule | EskomSePush API via allorigins.win CORS proxy | Browser fetch | Every 60 minutes |
| Countdown timer | Local JS calculation from schedule data | No API call | Every second |

The EskomSePush API is polled every **60 minutes** — matching the EDA rulebook
poll interval — to avoid consuming your API quota.

> **Security note:** The EskomSePush API token is embedded in the client-side
> JavaScript of `index.html`. Keep the dashboard URL internal to your network.
> For a public dashboard, move the token to a backend proxy.

---

## Before deploying — set your EskomSePush API token

Open `dashboard/index.html` and find this line near the bottom of the file:

```javascript
eskomToken: 'YOUR_ESKOMSEPUSH_TOKEN_HERE',
```

Replace `YOUR_ESKOMSEPUSH_TOKEN_HERE` with your real EskomSePush API token.
Get one at https://eskomsepush.gumroad.com/l/api

Also verify the area ID matches your location:

```javascript
areaId: 'capetown-10-atlantis',
```

Find your area ID by searching the EskomSePush API:

```bash
curl -H "Token: YOUR_TOKEN" \
  "https://developer.sepush.co.za/business/2.0/areas_search?text=your+suburb"
```

---

## Deploy to OpenShift hub cluster

### Prerequisites

- Logged into the hub cluster (`oc login https://api.sno.abreu.io:6443`)
- `oc` CLI available
- EskomSePush token added to `index.html`

### Step 1 — Create the namespace

```bash
oc new-project loadshedding-dashboard
```

### Step 2 — Create ConfigMap from the HTML file

```bash
oc create configmap loadshedding-dashboard \
  --from-file=index.html=dashboard/index.html \
  -n loadshedding-dashboard
```

### Step 3 — Deploy the pod, Service and Route

```bash
oc apply -n loadshedding-dashboard -f dashboard/deploy.yml
```

### Step 4 — Get the dashboard URL

```bash
oc get route loadshedding-dashboard \
  -n loadshedding-dashboard \
  -o jsonpath='https://{.spec.host}{"\n"}'
```

---

## Update the dashboard

When you change `index.html`, update the ConfigMap and restart:

```bash
oc create configmap loadshedding-dashboard \
  --from-file=index.html=dashboard/index.html \
  -n loadshedding-dashboard \
  --dry-run=client -o yaml | oc apply -f -

oc rollout restart deployment/loadshedding-dashboard \
  -n loadshedding-dashboard

oc rollout status deployment/loadshedding-dashboard \
  -n loadshedding-dashboard
```

---

## Remove the dashboard

```bash
oc delete project loadshedding-dashboard
```

---

## File structure

```
dashboard/
├── index.html    # Single-file dashboard — HTML, CSS and JS inline
│                 # ⚠ Add your EskomSePush token before deploying
├── deploy.yml    # OpenShift Deployment + Service + Route
└── README.md     # This file
```

---

## Simulating a loadshedding event for demo

The EDA source plugin (`eskomsepush_source.py`) supports a `test_mode` variable
that tells the EskomSePush API to return fake test data instead of the real schedule.

### To simulate an approaching loadshedding event

In the EDA Rulebook Activation variables, change:

```yaml
# Before (production — real schedule)
poll_interval: 3600
test_mode: ""

# After (simulate approaching event)
poll_interval: 3600
test_mode: "future"
```

With `test_mode: "future"` the EskomSePush API returns a fake event starting
soon. EDA will detect it as `loadshedding_approaching` and trigger
`Notify ACM: Shutdown` automatically — lab1 will cordon, drain and power off.

### To simulate an active loadshedding event

```yaml
test_mode: "current"
```

This returns a fake event that is currently active. EDA will trigger
`loadshedding_active` which also fires `Notify ACM: Shutdown`.

### To simulate the restore (loadshedding ended)

After the shutdown completes, change back to production mode:

```yaml
test_mode: ""
```

On the next poll EDA will see no active events, detect `loadshedding_ended`
and trigger `Notify ACM: Restore` — lab1 powers back on and uncordons.

### Manual demo (without waiting for EDA poll)

If you need an instant demo without waiting 60 minutes for EDA to poll,
trigger the AAP job templates directly:

**Shutdown:**
```bash
# In AAP UI → Templates → Notify ACM: Shutdown → Launch
# Or on HUB:
oc patch policy loadshedding-shutdown-policy \
  -n open-cluster-management \
  --type=merge -p '{"spec":{"disabled":false}}'
oc patch policy loadshedding-poweroff-hub-policy \
  -n open-cluster-management \
  --type=merge -p '{"spec":{"disabled":false}}'
```

**Restore:**
```bash
# In AAP UI → Templates → Notify ACM: Restore → Launch
# Or on HUB:
oc patch policy loadshedding-shutdown-policy \
  -n open-cluster-management \
  --type=merge -p '{"spec":{"disabled":true}}'
oc patch policy loadshedding-poweroff-hub-policy \
  -n open-cluster-management \
  --type=merge -p '{"spec":{"disabled":true}}'
oc patch policy loadshedding-restore-policy \
  -n open-cluster-management \
  --type=merge -p '{"spec":{"disabled":false}}'
oc patch policy loadshedding-poweron-hub-policy \
  -n open-cluster-management \
  --type=merge -p '{"spec":{"disabled":false}}'
```

The dashboard will reflect the real state within 2 minutes.
