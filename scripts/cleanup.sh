#!/bin/bash

NAMESPACE="confluent"

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
kubectl delete -f ../manifests/confluent-platform.yaml --ignore-not-found=true
echo "✅ Components deleted"
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
    echo "✅ Namespace deleted"
else
    echo "⏭️  Skipping namespace deletion"
fi
echo ""

echo "🎉 Cleanup complete!"
echo ""
echo "📝 To redeploy, run: ./deploy.sh"
