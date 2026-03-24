# Makefile — sno-loadshedding
# Requires: oc, kubectl, python3
# Set KUBECONFIG or pass KUBECONFIG=... to any target.

HUB_NS         := open-cluster-management
DASHBOARD_NS   := loadshedding-dashboard
DASHBOARD_IMG  := quay.io/yourorg/loadshedding-dashboard:latest

.PHONY: help apply-policies delete-policies check-policies \
        check-bmh-lab1 check-bmh-lab2 check-bmh \
        dashboard-build dashboard-deploy dashboard-delete \
        shutdown-test restore-test \
        lint

# ---------------------------------------------------------------
help:
	@echo ""
	@echo "  sno-loadshedding Makefile"
	@echo ""
	@echo "  ACM policies"
	@echo "    make apply-policies      Apply shutdown + restore policies to hub"
	@echo "    make delete-policies     Remove both policies from hub"
	@echo "    make check-policies      Show current policy compliance on hub"
	@echo ""
	@echo "  BareMetalHost checks"
	@echo "    make check-bmh-lab1      Show BMH status on lab1"
	@echo "    make check-bmh-lab2      Show BMH status on lab2"
	@echo "    make check-bmh           Show BMH status on both clusters"
	@echo ""
	@echo "  Dashboard"
	@echo "    make dashboard-deploy    Deploy dashboard to hub cluster"
	@echo "    make dashboard-delete    Remove dashboard from hub cluster"
	@echo ""
	@echo "  Manual override"
	@echo "    make shutdown-test       Enable shutdown policy manually (dry run test)"
	@echo "    make restore-test        Enable restore policy manually"
	@echo ""
	@echo "  Lint"
	@echo "    make lint                Lint all YAML files"
	@echo ""

# ---------------------------------------------------------------
# ACM policies
# ---------------------------------------------------------------
apply-policies:
	@echo "==> Applying ACM policies to hub..."
	oc apply -f acm-policies/shutdown-policy.yml -n $(HUB_NS)
	oc apply -f acm-policies/restore-policy.yml  -n $(HUB_NS)
	@echo "==> Done. Both policies start disabled — EDA enables them at runtime."

delete-policies:
	@echo "==> Removing ACM policies from hub..."
	oc delete -f acm-policies/shutdown-policy.yml -n $(HUB_NS) --ignore-not-found
	oc delete -f acm-policies/restore-policy.yml  -n $(HUB_NS) --ignore-not-found

check-policies:
	@echo "==> Shutdown policy status:"
	@oc get policy loadshedding-shutdown-policy -n $(HUB_NS) \
	  -o custom-columns=NAME:.metadata.name,DISABLED:.spec.disabled,COMPLIANT:.status.compliant \
	  2>/dev/null || echo "  Policy not found"
	@echo ""
	@echo "==> Restore policy status:"
	@oc get policy loadshedding-restore-policy -n $(HUB_NS) \
	  -o custom-columns=NAME:.metadata.name,DISABLED:.spec.disabled,COMPLIANT:.status.compliant \
	  2>/dev/null || echo "  Policy not found"

# ---------------------------------------------------------------
# BareMetalHost checks (pass KUBECONFIG_LAB1/LAB2 or set KUBECONFIG)
# ---------------------------------------------------------------
check-bmh-lab1:
	@echo "==> BareMetalHost on lab1:"
	oc get bmh -n openshift-machine-api \
	  --kubeconfig=$(KUBECONFIG_LAB1) \
	  -o custom-columns=NAME:.metadata.name,STATUS:.status.provisioning.state,ONLINE:.spec.online,POWER:.status.poweredOn

check-bmh-lab2:
	@echo "==> BareMetalHost on lab2:"
	oc get bmh -n openshift-machine-api \
	  --kubeconfig=$(KUBECONFIG_LAB2) \
	  -o custom-columns=NAME:.metadata.name,STATUS:.status.provisioning.state,ONLINE:.spec.online,POWER:.status.poweredOn

check-bmh: check-bmh-lab1 check-bmh-lab2

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
# Manual override targets (use with care)
# ---------------------------------------------------------------
shutdown-test:
	@echo "==> WARNING: This will enable the shutdown policy and trigger cluster drain + power-off."
	@read -p "Type YES to continue: " confirm && [ "$$confirm" = "YES" ]
	oc patch policy loadshedding-shutdown-policy -n $(HUB_NS) \
	  --type=merge -p '{"spec":{"disabled":false}}'
	oc patch policy loadshedding-restore-policy -n $(HUB_NS) \
	  --type=merge -p '{"spec":{"disabled":true}}'
	@echo "==> Shutdown policy enabled. Monitor with: make check-policies"

restore-test:
	@echo "==> Enabling restore policy — this will power on and uncordon lab1 and lab2."
	@read -p "Type YES to continue: " confirm && [ "$$confirm" = "YES" ]
	oc patch policy loadshedding-shutdown-policy -n $(HUB_NS) \
	  --type=merge -p '{"spec":{"disabled":true}}'
	oc patch policy loadshedding-restore-policy -n $(HUB_NS) \
	  --type=merge -p '{"spec":{"disabled":false}}'
	@echo "==> Restore policy enabled. Monitor with: make check-policies"

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
