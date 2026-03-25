# Makefile — sno-loadshedding
# Requires: oc, python3
# All targets that talk to the hub assume KUBECONFIG is set or
# you are already logged in via oc login.
#
# Policy structure (4 policies total):
#   shutdown-policy.yml  →  loadshedding-shutdown-policy     (targets lab1/lab2)
#                        →  loadshedding-poweroff-hub-policy  (targets local-cluster)
#   restore-policy.yml   →  loadshedding-restore-policy      (targets lab1/lab2)
#                        →  loadshedding-poweron-hub-policy   (targets local-cluster)

HUB_NS         := open-cluster-management
BMH_NS         := lab-infra
DASHBOARD_NS   := loadshedding-dashboard
SUSHY_URL      := https://192.168.22.157:8000
LAB1_SYSTEM_ID := bca393c5-d932-42ab-9c37-a6f19d4322f8
LAB2_SYSTEM_ID := replace-with-lab2-uuid

.PHONY: help \
        apply-policies delete-policies check-policies disable-all \
        shutdown-test restore-test \
        check-power-lab1 check-power-lab2 \
        check-bmh \
        check-jobs clean-jobs \
        check-cluster-lab1 \
        dashboard-deploy dashboard-delete \
        lint

# ---------------------------------------------------------------
help:
	@echo ""
	@echo "  sno-loadshedding Makefile"
	@echo ""
	@echo "  ACM policies"
	@echo "    make apply-policies      Apply all 4 policies to hub (all start disabled)"
	@echo "    make delete-policies     Remove all 4 policies from hub"
	@echo "    make check-policies      Show disabled/compliant status of all 4 policies"
	@echo "    make disable-all         Disable all 4 policies (safe reset)"
	@echo ""
	@echo "  Manual override (use with care)"
	@echo "    make shutdown-test       Enable shutdown pair — cordon+drain+power-off"
	@echo "    make restore-test        Enable restore pair  — power-on+uncordon"
	@echo ""
	@echo "  Power state checks (via sushy Redfish)"
	@echo "    make check-power-lab1    Show lab1 current power state"
	@echo "    make check-power-lab2    Show lab2 current power state"
	@echo ""
	@echo "  BMH checks"
	@echo "    make check-bmh           Show BMH status in lab-infra namespace"
	@echo ""
	@echo "  Job management"
	@echo "    make check-jobs          Show loadshedding Jobs on hub"
	@echo "    make clean-jobs          Delete completed loadshedding Jobs on hub"
	@echo ""
	@echo "  Cluster checks"
	@echo "    make check-cluster-lab1  Show lab1 managed cluster status"
	@echo ""
	@echo "  Dashboard"
	@echo "    make dashboard-deploy    Deploy dashboard to hub"
	@echo "    make dashboard-delete    Remove dashboard from hub"
	@echo ""
	@echo "  Lint"
	@echo "    make lint                Lint all YAML and Python files"
	@echo ""

# ---------------------------------------------------------------
# ACM policies
# ---------------------------------------------------------------
apply-policies:
	@echo "==> Applying all 4 ACM policies to hub..."
	oc apply -f acm-policies/shutdown-policy.yml -n $(HUB_NS)
	oc apply -f acm-policies/restore-policy.yml  -n $(HUB_NS)
	@echo ""
	@echo "==> Done. All 4 policies start disabled=true."
	@echo "    EDA/AAP enables the correct pair at runtime."
	@echo "    To test manually: make shutdown-test or make restore-test"

delete-policies:
	@echo "==> Removing all 4 ACM policies from hub..."
	oc delete -f acm-policies/shutdown-policy.yml -n $(HUB_NS) --ignore-not-found
	oc delete -f acm-policies/restore-policy.yml  -n $(HUB_NS) --ignore-not-found
	@echo "==> Done."

check-policies:
	@echo "==> All loadshedding policy states:"
	@echo ""
	@oc get policy -n $(HUB_NS) \
	  -o custom-columns="NAME:.metadata.name,DISABLED:.spec.disabled,COMPLIANT:.status.compliant" \
	  2>/dev/null | grep -E "NAME|loadshedding" || echo "  No loadshedding policies found"

disable-all:
	@echo "==> Disabling all 4 loadshedding policies..."
	-oc patch policy loadshedding-shutdown-policy \
	  -n $(HUB_NS) --type=merge -p '{"spec":{"disabled":true}}'
	-oc patch policy loadshedding-poweroff-hub-policy \
	  -n $(HUB_NS) --type=merge -p '{"spec":{"disabled":true}}'
	-oc patch policy loadshedding-restore-policy \
	  -n $(HUB_NS) --type=merge -p '{"spec":{"disabled":true}}'
	-oc patch policy loadshedding-poweron-hub-policy \
	  -n $(HUB_NS) --type=merge -p '{"spec":{"disabled":true}}'
	@echo "==> All policies disabled."

# ---------------------------------------------------------------
# Manual override — enables the correct PAIR of policies together
# ---------------------------------------------------------------
shutdown-test:
	@echo "==> WARNING: This will cordon, drain and power off lab1 and lab2."
	@read -p "Type YES to continue: " confirm && [ "$$confirm" = "YES" ]
	@echo "==> Disabling restore pair first..."
	-oc patch policy loadshedding-restore-policy \
	  -n $(HUB_NS) --type=merge -p '{"spec":{"disabled":true}}'
	-oc patch policy loadshedding-poweron-hub-policy \
	  -n $(HUB_NS) --type=merge -p '{"spec":{"disabled":true}}'
	@echo "==> Enabling shutdown pair..."
	oc patch policy loadshedding-shutdown-policy \
	  -n $(HUB_NS) --type=merge -p '{"spec":{"disabled":false}}'
	oc patch policy loadshedding-poweroff-hub-policy \
	  -n $(HUB_NS) --type=merge -p '{"spec":{"disabled":false}}'
	@echo ""
	@echo "==> Shutdown pair enabled. Monitor:"
	@echo "    make check-policies"
	@echo "    make check-jobs"
	@echo "    make check-power-lab1"

restore-test:
	@echo "==> WARNING: This will power on and uncordon lab1 and lab2."
	@read -p "Type YES to continue: " confirm && [ "$$confirm" = "YES" ]
	@echo "==> Disabling shutdown pair first..."
	-oc patch policy loadshedding-shutdown-policy \
	  -n $(HUB_NS) --type=merge -p '{"spec":{"disabled":true}}'
	-oc patch policy loadshedding-poweroff-hub-policy \
	  -n $(HUB_NS) --type=merge -p '{"spec":{"disabled":true}}'
	@echo "==> Enabling restore pair..."
	oc patch policy loadshedding-restore-policy \
	  -n $(HUB_NS) --type=merge -p '{"spec":{"disabled":false}}'
	oc patch policy loadshedding-poweron-hub-policy \
	  -n $(HUB_NS) --type=merge -p '{"spec":{"disabled":false}}'
	@echo ""
	@echo "==> Restore pair enabled. Monitor:"
	@echo "    make check-policies"
	@echo "    make check-jobs"
	@echo "    make check-cluster-lab1"

# ---------------------------------------------------------------
# Sushy / Redfish power state checks
# ---------------------------------------------------------------
check-power-lab1:
	@echo "==> lab1 power state (via sushy Redfish):"
	@curl -sk -u admin:admin \
	  $(SUSHY_URL)/redfish/v1/Systems/$(LAB1_SYSTEM_ID) \
	  | python3 -c "import sys,json; d=json.load(sys.stdin); \
	    print('  Name:', d.get('Name','?'), '| PowerState:', d.get('PowerState','unknown'))"

check-power-lab2:
	@echo "==> lab2 power state (via sushy Redfish):"
	@curl -sk -u admin:admin \
	  $(SUSHY_URL)/redfish/v1/Systems/$(LAB2_SYSTEM_ID) \
	  | python3 -c "import sys,json; d=json.load(sys.stdin); \
	    print('  Name:', d.get('Name','?'), '| PowerState:', d.get('PowerState','unknown'))"

# ---------------------------------------------------------------
# BMH checks
# ---------------------------------------------------------------
check-bmh:
	@echo "==> BareMetalHost in $(BMH_NS):"
	@oc get bmh -n $(BMH_NS) \
	  -o custom-columns="NAME:.metadata.name,STATE:.status.provisioning.state,ONLINE:.spec.online,POWERED:.status.poweredOn,ERROR:.status.errorMessage" \
	  2>/dev/null || echo "  No BMH found in $(BMH_NS)"

# ---------------------------------------------------------------
# Job management
# ---------------------------------------------------------------
check-jobs:
	@echo "==> Loadshedding Jobs on hub (openshift-machine-api):"
	@oc get jobs -n openshift-machine-api 2>/dev/null \
	  | grep -E "NAME|loadshedding" || echo "  No loadshedding jobs found"

clean-jobs:
	@echo "==> Deleting completed loadshedding Jobs from hub..."
	@oc get jobs -n openshift-machine-api \
	  -o jsonpath='{range .items[?(@.status.completionTime)]}{.metadata.name}{"\n"}{end}' \
	  2>/dev/null | grep loadshedding | while read job; do \
	    echo "  Deleting $$job"; \
	    oc delete job $$job -n openshift-machine-api; \
	  done
	@echo "==> Done."

# ---------------------------------------------------------------
# Cluster checks
# ---------------------------------------------------------------
check-cluster-lab1:
	@echo "==> lab1 managed cluster status:"
	@oc get managedcluster lab1 \
	  -o custom-columns="NAME:.metadata.name,HUB_ACCEPTED:.spec.hubAcceptsClient,JOINED:.status.conditions[?(@.type==\"ManagedClusterJoined\")].status,AVAILABLE:.status.conditions[?(@.type==\"ManagedClusterConditionAvailable\")].status" \
	  2>/dev/null || echo "  lab1 not found as managed cluster"

# ---------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------
dashboard-deploy:
	@echo "==> Deploying dashboard to hub cluster namespace $(DASHBOARD_NS)..."
	oc get namespace $(DASHBOARD_NS) 2>/dev/null || oc create namespace $(DASHBOARD_NS)
	oc create configmap loadshedding-dashboard \
	  --from-file=index.html=dashboard/index.html \
	  -n $(DASHBOARD_NS) \
	  --dry-run=client -o yaml | oc apply -f -
	oc apply -n $(DASHBOARD_NS) -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: loadshedding-dashboard
spec:
  replicas: 1
  selector:
    matchLabels:
      app: loadshedding-dashboard
  template:
    metadata:
      labels:
        app: loadshedding-dashboard
    spec:
      containers:
        - name: nginx
          image: registry.access.redhat.com/ubi9/nginx-120:latest
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: html
              mountPath: /opt/app-root/src
      volumes:
        - name: html
          configMap:
            name: loadshedding-dashboard
---
apiVersion: v1
kind: Service
metadata:
  name: loadshedding-dashboard
spec:
  selector:
    app: loadshedding-dashboard
  ports:
    - port: 8080
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: loadshedding-dashboard
spec:
  to:
    kind: Service
    name: loadshedding-dashboard
  port:
    targetPort: 8080
  tls:
    termination: edge
YAML
	@echo "==> Dashboard URL:"
	@oc get route loadshedding-dashboard -n $(DASHBOARD_NS) \
	  -o jsonpath='https://{.spec.host}{"\n"}'

dashboard-delete:
	oc delete namespace $(DASHBOARD_NS) --ignore-not-found

# ---------------------------------------------------------------
# Lint
# ---------------------------------------------------------------
lint:
	@echo "==> Linting YAML files..."
	@command -v yamllint >/dev/null 2>&1 || pip install yamllint -q
	yamllint -d "{extends: relaxed, rules: {line-length: {max: 160}}}" \
	  acm-policies/ aap/
	@echo "==> Linting Python source plugin..."
	@command -v flake8 >/dev/null 2>&1 || pip install flake8 -q
	flake8 aap/eda/sources/eskomsepush_source.py --max-line-length=120
	@echo "==> All checks passed."
