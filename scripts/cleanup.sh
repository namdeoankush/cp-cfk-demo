#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

NAMESPACE="confluent"
MANIFEST_DIR="${PROJECT_DIR}/manifests"

echo "🧹 Cleaning up Confluent Platform deployment"
echo "============================================="
echo ""

read -p "⚠️  This will delete all Confluent Platform components in namespace '${NAMESPACE}'. Continue? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ Cleanup cancelled"
    exit 0
fi

echo "🗑️  Step 1: Deleting Confluent Platform components..."
if [ -f "${MANIFEST_DIR}/confluent-platform.yaml" ]; then
    kubectl delete -f ${MANIFEST_DIR}/confluent-platform.yaml --ignore-not-found=true
    echo "✅ Components deleted"
else
    echo "⚠️  Manifest file not found: ${MANIFEST_DIR}/confluent-platform.yaml"
    echo "   Attempting to delete components by label..."
    kubectl delete kraftcontroller,kafka,controlcenter -n ${NAMESPACE} --all --ignore-not-found=true
    echo "✅ Components deleted by label"
fi
echo ""

echo "🗑️  Step 2: Deleting secrets..."
kubectl delete secret \
    kraftcontroller-tls \
    kafka-tls \
    controlcenter-tls \
    prometheus-tls \
    alertmanager-tls \
    prometheus-client-tls \
    alertmanager-client-tls \
    -n ${NAMESPACE} --ignore-not-found=true
echo "✅ Secrets deleted"
echo ""

echo "🗑️  Step 3: Uninstalling CFK operator..."
helm uninstall confluent-operator -n ${NAMESPACE} 2>/dev/null || echo "   CFK operator not found"
echo "✅ CFK operator uninstalled"
echo ""

read -p "Delete namespace '${NAMESPACE}'? (yes/no): " -r
echo ""
if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "🗑️  Step 4: Deleting namespace..."
    kubectl delete namespace ${NAMESPACE} --ignore-not-found=true

    # Wait for namespace deletion with timeout
    echo "⏳ Waiting for namespace deletion..."
    for i in {1..30}; do
        if ! kubectl get namespace ${NAMESPACE} &>/dev/null; then
            echo "✅ Namespace deleted"
            break
        fi

        # Check if namespace is stuck in Terminating state
        NS_STATUS=$(kubectl get namespace ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$NS_STATUS" = "Terminating" ] && [ $i -gt 10 ]; then
            echo ""
            echo "⚠️  Namespace stuck in Terminating state. Running force cleanup..."
            echo ""
            ${SCRIPT_DIR}/force-cleanup-namespace.sh
            break
        fi

        echo "   Waiting... ($i/30)"
        sleep 2
    done
else
    echo "⏭️  Skipping namespace deletion"
fi
echo ""

echo "🎉 Cleanup complete!"
echo ""
echo "📝 To redeploy, run: ./scripts/deploy.sh"
