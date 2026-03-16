#This is a hack script and will be remove soon do not rely on it.

#!/bin/bash

# Configuration
NAMESPACE="home"
BMH_NAME="sno-spoke"
ASSISTED_NAMESPACE="multicluster-engine"

echo "Starting monitoring loop for $BMH_NAME..."
echo "Press [CTRL+C] to stop."

while true; do
    # 1. Check if assisted-service is running
    REPLICAS=$(oc get deployment assisted-service -n $ASSISTED_NAMESPACE -o jsonpath='{.spec.replicas}')

    if [ "$REPLICAS" -ne 0 ]; then
        echo "[$(date +%T)] Assisted Service detected at $REPLICAS replicas. Scaling down..."
        oc scale deployment assisted-service -n $ASSISTED_NAMESPACE --replicas=0
    fi

    # 2. Clear the annotations if they exist
    # We use --overwrite=true to ensure the removal command triggers a reconciliation
    echo "[$(date +%T)] Clearing paused and detached locks..."
    oc annotate bmh $BMH_NAME -n $NAMESPACE baremetalhost.metal3.io/paused- --overwrite=true 2>/dev/null
    oc annotate bmh $BMH_NAME -n $NAMESPACE baremetalhost.metal3.io/detached- --overwrite=true 2>/dev/null

    # 3. Brief sleep to prevent CPU spiking
    sleep 5
done
