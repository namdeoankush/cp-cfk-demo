#!/bin/bash
set -e

NAMESPACE="confluent"

echo "🧹 Force cleaning up stuck namespace: ${NAMESPACE}"
echo "=================================================="
echo ""

# Function to remove finalizers from resources
remove_finalizers() {
    local resource_type=$1
    local display_name=$2

    echo "Removing finalizers from ${display_name}..."
    local count=0
    kubectl get ${resource_type} -n ${NAMESPACE} -o name 2>/dev/null | while read resource; do
        echo "  - Patching $resource"
        kubectl patch $resource -n ${NAMESPACE} -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        ((count++)) || true
    done
    if [ $count -eq 0 ]; then
        echo "  (none found)"
    fi
}

# 1. Remove Helm release secrets first (they can block cleanup)
echo "🗑️  Removing Helm release secrets..."
kubectl get secrets -n ${NAMESPACE} -o name 2>/dev/null | grep "sh.helm.release" | while read secret; do
    echo "  - Deleting $secret"
    kubectl delete $secret -n ${NAMESPACE} --ignore-not-found=true 2>/dev/null || true
done
echo ""

# 2. Remove finalizers from all Confluent Platform CRDs
echo "🔧 Cleaning up Confluent Platform resources..."
remove_finalizers "kraftcontroller" "KRaft Controllers"
remove_finalizers "kafka" "Kafka clusters"
remove_finalizers "controlcenter" "Control Centers"
remove_finalizers "connect" "Kafka Connect clusters"
remove_finalizers "schemaregistry" "Schema Registries"
remove_finalizers "ksqldb" "ksqlDB clusters"
remove_finalizers "kafkarestproxy" "Kafka REST Proxies"
remove_finalizers "zookeeper" "Zookeepers"
remove_finalizers "clusterlink" "Cluster Links"
remove_finalizers "connector" "Connectors"
remove_finalizers "kafkatopic" "Kafka Topics"
remove_finalizers "schema" "Schemas"
remove_finalizers "confluentrolebinding" "Confluent Role Bindings"
remove_finalizers "kraftmigrationjob" "KRaft Migration Jobs"
remove_finalizers "flinkapplication" "Flink Applications"
remove_finalizers "flinkenvironment" "Flink Environments"
echo ""

# 3. Remove finalizers from standard Kubernetes resources
echo "🗂️  Cleaning up Kubernetes resources..."
remove_finalizers "statefulset" "StatefulSets"
remove_finalizers "deployment" "Deployments"
remove_finalizers "replicaset" "ReplicaSets"
remove_finalizers "pod" "Pods"
remove_finalizers "pvc" "PersistentVolumeClaims"
remove_finalizers "service" "Services"
remove_finalizers "configmap" "ConfigMaps"
remove_finalizers "secret" "Secrets"
remove_finalizers "serviceaccount" "ServiceAccounts"
remove_finalizers "ingress" "Ingresses"
remove_finalizers "networkpolicy" "Network Policies"
echo ""

# 4. Force delete any remaining pods
echo "🔨 Force deleting any remaining pods..."
kubectl delete pods --all -n ${NAMESPACE} --force --grace-period=0 2>/dev/null || true
echo ""

# 5. Delete any stuck PVCs
echo "💾 Cleaning up PersistentVolumeClaims..."
kubectl get pvc -n ${NAMESPACE} -o name 2>/dev/null | while read pvc; do
    echo "  - Force deleting $pvc"
    kubectl patch $pvc -n ${NAMESPACE} -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    kubectl delete $pvc -n ${NAMESPACE} --force --grace-period=0 2>/dev/null || true
done
echo ""

# 6. Clean up orphaned PersistentVolumes (cluster-scoped)
echo "🗄️  Checking for orphaned PersistentVolumes..."
PV_COUNT=0
kubectl get pv -o json 2>/dev/null | jq -r --arg ns "${NAMESPACE}" '.items[] | select(.spec.claimRef.namespace == $ns) | .metadata.name' 2>/dev/null | while read pv; do
    if [ -n "$pv" ]; then
        echo "  - Removing finalizers from PV: $pv"
        kubectl patch pv $pv -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        kubectl delete pv $pv --force --grace-period=0 2>/dev/null || true
        ((PV_COUNT++)) || true
    fi
done
if [ $PV_COUNT -eq 0 ]; then
    echo "  (none found)"
fi
echo ""

echo "✅ All resource finalizers removed"
echo ""

# 7. Check if namespace exists and is terminating
if kubectl get namespace ${NAMESPACE} &>/dev/null; then
    NS_STATUS=$(kubectl get namespace ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    echo "📊 Namespace status: ${NS_STATUS}"

    if [ "$NS_STATUS" = "Terminating" ]; then
        echo "🔧 Namespace is stuck in Terminating state. Removing namespace finalizers..."
        kubectl get namespace ${NAMESPACE} -o json | \
            jq '.spec.finalizers = []' | \
            kubectl replace --raw /api/v1/namespaces/${NAMESPACE}/finalize -f - 2>/dev/null || \
            kubectl patch namespace ${NAMESPACE} -p '{"spec":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        echo ""
    fi

    echo "⏳ Waiting for namespace deletion..."
    echo ""

    # Wait for namespace to be deleted (max 60 seconds)
    for i in {1..60}; do
        if ! kubectl get namespace ${NAMESPACE} &>/dev/null; then
            echo "✅ Namespace ${NAMESPACE} successfully deleted!"
            echo ""
            exit 0
        fi
        echo "   Waiting for namespace deletion... ($i/60)"
        sleep 1
    done

    echo ""
    echo "⚠️  Namespace still exists after cleanup attempts."
    echo ""
    echo "Remaining resources:"
    kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n ${NAMESPACE} 2>/dev/null | head -20
    echo ""
    echo "You may need to:"
    echo "  1. Check if CFK operator is running: kubectl get pods -n ${NAMESPACE}"
    echo "  2. Manually force delete: kubectl delete namespace ${NAMESPACE} --force --grace-period=0"
    echo "  3. Edit namespace directly: kubectl edit namespace ${NAMESPACE}"
    exit 1
else
    echo "✅ Namespace ${NAMESPACE} does not exist (already cleaned up)"
    echo ""
    exit 0
fi
