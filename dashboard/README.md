# SNO Loadshedding Dashboard

A lightweight status dashboard for the SNO loadshedding automation system.
Shows cluster power state, EskomSePush schedule, and countdown to the next
loadshedding window.

Deployed as a static HTML file served by nginx on the hub cluster.

---

## What it shows

- **lab1 / lab2** power state and OCP API health
- **Next loadshedding window** with live countdown timer
- **Schedule** for the next 24 hours
- **System status** — which ACM policies are active

---

## Current state

The dashboard currently uses **mock data** — it simulates an upcoming loadshedding
event 90 minutes from now so you can see the full UI without needing a live backend.

To connect it to real data, uncomment the `fetch` call in `index.html` and point
`CONFIG.apiBase` at a backend proxy that returns EskomSePush data. The API key
must be proxied server-side to avoid CORS and to keep the token secret.

---

## Deploy to OpenShift hub cluster

### Prerequisites

- Logged into the hub cluster (`oc login https://api.sno.abreu.io:6443`)
- `oc` CLI available

### Step 1 — Create the namespace

```bash
oc new-project loadshedding-dashboard
```

### Step 2 — Create a ConfigMap from the HTML file

```bash
oc create configmap loadshedding-dashboard \
  --from-file=index.html=dashboard/index.html \
  -n loadshedding-dashboard
```

### Step 3 — Deploy nginx, Service and Route

```bash
oc apply -n loadshedding-dashboard -f dashboard/deploy.yml
```

### Step 4 — Get the dashboard URL

```bash
oc get route loadshedding-dashboard \
  -n loadshedding-dashboard \
  -o jsonpath='https://{.spec.host}{"\n"}'
```

Open the URL in your browser.

---

## Update the dashboard

When you change `index.html`, update the ConfigMap and restart the pod:

```bash
# Update the ConfigMap
oc create configmap loadshedding-dashboard \
  --from-file=index.html=dashboard/index.html \
  -n loadshedding-dashboard \
  --dry-run=client -o yaml | oc apply -f -

# Restart the pod to pick up the new ConfigMap
oc rollout restart deployment/loadshedding-dashboard \
  -n loadshedding-dashboard

# Watch the rollout
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
├── index.html    # Single-file dashboard — all HTML, CSS and JS inline
├── deploy.yml    # OpenShift Deployment + Service + Route
└── README.md     # This file
```
