# Secrets index

This file documents every credential this project needs and where it is stored.
**No actual values belong here.** Update this file when you add, rotate, or retire a secret.

---

## AAP credential store

Create a single custom credential type called `loadshedding-credentials` in AAP
(Administration → Credential Types) with the following fields, then create one
credential of that type and attach it to both Job Templates.

| Field | Description | Where to get it |
|-------|-------------|-----------------|
| `eskomsepush_api_token` | EskomSePush API token | https://eskomsepush.gumroad.com/l/api |
| `acm_hub_url` | ACM hub API URL | `oc whoami --show-server` on the hub cluster |
| `acm_token` | Service account token with `policy-admin` on ACM hub | See "ACM service account" below |
| `ipmi_lab1_host` | IPMI IP address for lab1 | Your network/BIOS config |
| `ipmi_lab2_host` | IPMI IP address for lab2 | Your network/BIOS config |
| `ipmi_user` | IPMI username | Your BMC config |
| `ipmi_password` | IPMI password | Your BMC config |

---

## ACM service account setup

The AAP playbooks patch ACM Policy objects on the hub. Create a dedicated
service account with the minimum required RBAC:

```bash
# On the hub cluster
oc create serviceaccount loadshedding-eda -n open-cluster-management

oc create clusterrolebinding loadshedding-eda-policy-admin \
  --clusterrole=open-cluster-management:admin \
  --serviceaccount=open-cluster-management:loadshedding-eda

# Get the token (OCP 4.11+ requires a bound token)
oc create token loadshedding-eda \
  -n open-cluster-management \
  --duration=8760h   # 1 year — rotate annually
```

Store the output token in the AAP credential as `acm_token`.

---

## BareMetalHost IPMI credentials (on managed clusters)

The `baremetal-operator` on lab1 and lab2 already holds IPMI credentials in a
Secret referenced by each `BareMetalHost` CR. These are set at OCP install time
and do not need to be re-entered here — ACM drives the operator via
`BareMetalHost.spec.online`, so no additional IPMI secrets are needed in AAP
for the power on/off path.

To verify the existing BMH secret on each cluster:

```bash
BMH=$(oc get bmh -n openshift-machine-api -o jsonpath='{.items[0].metadata.name}')
SECRET=$(oc get bmh "$BMH" -n openshift-machine-api \
  -o jsonpath='{.spec.bmc.credentialsName}')
echo "BMH: $BMH  →  Secret: $SECRET"
oc get secret "$SECRET" -n openshift-machine-api
```

---

## EDA extra vars

Set these as extra variables on the EDA Rulebook Activation (not in source control):

| Variable | Description |
|----------|-------------|
| `eskomsepush_api_token` | Same token as above |
| `eskomsepush_area_id` | Your EskomSePush area ID (e.g. `capetown-10-atlantis`) |
| `warning_minutes` | Minutes before outage to trigger shutdown (default: `30`) |
| `poll_interval` | Seconds between API polls (default: `300`) |

---

## Secret rotation checklist

- [ ] EskomSePush token: update in AAP credential, update in EDA activation extra vars
- [ ] ACM service account token: re-run `oc create token`, update in AAP credential
- [ ] IPMI password: update BMC, update AAP credential, update BMH Secret on each cluster
- [ ] After any rotation: trigger a manual test run of both Job Templates to confirm
