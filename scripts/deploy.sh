#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

NAMESPACE="confluent"
CFK_VERSION="0.1351.59"  # CFK 3.1.1
CERT_DIR="${PROJECT_DIR}/certs"
MANIFEST_DIR="${PROJECT_DIR}/manifests"

echo "🚀 Deploying Confluent Platform 7.9.4 with KRaft and Control Center Next-Gen"
echo "============================================================================="
echo ""

# Step 1: Create namespace
echo "📁 Step 1: Creating namespace '${NAMESPACE}'..."
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Namespace ready"
echo ""

# Step 2: Install CFK Operator
echo "🔧 Step 2: Installing Confluent for Kubernetes (CFK) operator version ${CFK_VERSION}..."
helm repo add confluentinc https://packages.confluent.io/helm 2>/dev/null || true
helm repo update confluentinc

if helm list -n ${NAMESPACE} | grep -q confluent-operator; then
    echo "   Upgrading existing CFK operator..."
    helm upgrade confluent-operator confluentinc/confluent-for-kubernetes \
        --version ${CFK_VERSION} \
        --namespace ${NAMESPACE} \
        --set namespaced=true
else
    echo "   Installing CFK operator..."
    helm install confluent-operator confluentinc/confluent-for-kubernetes \
        --version ${CFK_VERSION} \
        --namespace ${NAMESPACE} \
        --set namespaced=true
fi
echo "✅ CFK operator installed"
echo ""

# Step 3: Wait for operator
echo "⏳ Step 3: Waiting for CFK operator to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/confluent-operator -n ${NAMESPACE}
echo "✅ CFK operator is ready"
echo ""

# Step 4: Generate certificates if needed
echo "🔐 Step 4: Checking certificates..."
if [ ! -f "${CERT_DIR}/ca-cert.pem" ] || [ ! -f "${CERT_DIR}/kraftcontroller.keystore.jks" ]; then
    echo "   Certificates not found. Generating..."
    (cd ${CERT_DIR} && ./generate-certs.sh)
else
    echo "   Certificates already exist. Skipping generation."
fi
echo ""

# Step 5: Create Kubernetes secrets
echo "🔑 Step 5: Creating Kubernetes secrets..."

# KRaft Controller secrets
kubectl create secret generic kraftcontroller-tls \
    --from-file=fullchain.pem=${CERT_DIR}/kraftcontroller-cert.pem \
    --from-file=privkey.pem=${CERT_DIR}/kraftcontroller-key.pem \
    --from-file=cacerts.pem=${CERT_DIR}/ca-cert.pem \
    --from-file=keystore.jks=${CERT_DIR}/kraftcontroller.keystore.jks \
    --from-file=truststore.jks=${CERT_DIR}/kraftcontroller.truststore.jks \
    --from-file=jksPassword.txt=${CERT_DIR}/kraftcontroller.jksPassword.txt \
    --namespace ${NAMESPACE} \
    --dry-run=client -o yaml | kubectl apply -f -

# Kafka secrets
kubectl create secret generic kafka-tls \
    --from-file=fullchain.pem=${CERT_DIR}/kafka-cert.pem \
    --from-file=privkey.pem=${CERT_DIR}/kafka-key.pem \
    --from-file=cacerts.pem=${CERT_DIR}/ca-cert.pem \
    --from-file=keystore.jks=${CERT_DIR}/kafka.keystore.jks \
    --from-file=truststore.jks=${CERT_DIR}/kafka.truststore.jks \
    --from-file=jksPassword.txt=${CERT_DIR}/kafka.jksPassword.txt \
    --namespace ${NAMESPACE} \
    --dry-run=client -o yaml | kubectl apply -f -

# Control Center secrets
kubectl create secret generic controlcenter-tls \
    --from-file=fullchain.pem=${CERT_DIR}/controlcenter-cert.pem \
    --from-file=privkey.pem=${CERT_DIR}/controlcenter-key.pem \
    --from-file=cacerts.pem=${CERT_DIR}/ca-cert.pem \
    --from-file=keystore.jks=${CERT_DIR}/controlcenter.keystore.jks \
    --from-file=truststore.jks=${CERT_DIR}/controlcenter.truststore.jks \
    --from-file=jksPassword.txt=${CERT_DIR}/controlcenter.jksPassword.txt \
    --namespace ${NAMESPACE} \
    --dry-run=client -o yaml | kubectl apply -f -

# Prometheus server secrets (PEM format with EKU)
kubectl create secret generic prometheus-tls \
    --from-file=fullchain.pem=${CERT_DIR}/prometheus-cert.pem \
    --from-file=privkey.pem=${CERT_DIR}/prometheus-key.pem \
    --from-file=cacerts.pem=${CERT_DIR}/ca-cert.pem \
    --namespace ${NAMESPACE} \
    --dry-run=client -o yaml | kubectl apply -f -

# AlertManager server secrets (PEM format with EKU)
kubectl create secret generic alertmanager-tls \
    --from-file=fullchain.pem=${CERT_DIR}/alertmanager-cert.pem \
    --from-file=privkey.pem=${CERT_DIR}/alertmanager-key.pem \
    --from-file=cacerts.pem=${CERT_DIR}/ca-cert.pem \
    --namespace ${NAMESPACE} \
    --dry-run=client -o yaml | kubectl apply -f -

# Prometheus client secrets (for Control Center to connect to Prometheus)
# IMPORTANT: Uses SEPARATE client certificate, not the server certificate
kubectl create secret generic prometheus-client-tls \
    --from-file=fullchain.pem=${CERT_DIR}/prometheus-client-cert.pem \
    --from-file=privkey.pem=${CERT_DIR}/prometheus-client-key.pem \
    --from-file=cacerts.pem=${CERT_DIR}/ca-cert.pem \
    --namespace ${NAMESPACE} \
    --dry-run=client -o yaml | kubectl apply -f -

# AlertManager client secrets (for Control Center to connect to AlertManager)
# IMPORTANT: Uses SEPARATE client certificate, not the server certificate
kubectl create secret generic alertmanager-client-tls \
    --from-file=fullchain.pem=${CERT_DIR}/alertmanager-client-cert.pem \
    --from-file=privkey.pem=${CERT_DIR}/alertmanager-client-key.pem \
    --from-file=cacerts.pem=${CERT_DIR}/ca-cert.pem \
    --namespace ${NAMESPACE} \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✅ All secrets created"
echo ""

# Step 6: Deploy Confluent Platform
echo "🎯 Step 6: Deploying Confluent Platform components..."
kubectl apply -f ${MANIFEST_DIR}/confluent-platform.yaml
echo "✅ Manifests applied"
echo ""

# Step 7: Wait for components
echo "⏳ Step 7: Waiting for components to be ready..."
echo ""

# Wait for KRaftController CRD to create pods
echo "   Waiting for KRaft Controller resource to be created..."
for i in {1..30}; do
    if kubectl get kraftcontroller kraftcontroller -n ${NAMESPACE} &>/dev/null; then
        echo "   ✅ KRaft Controller resource exists"
        break
    fi
    echo "   Waiting for KRaft Controller resource... ($i/30)"
    sleep 2
done
echo ""

echo "   Waiting for KRaft Controllers (3/3 pods)..."
kubectl wait --for=condition=ready pod -l platform.confluent.io/type=kraftcontroller -n ${NAMESPACE} --timeout=600s 2>/dev/null || \
    kubectl wait --for=condition=ready pod -l statefulset.kubernetes.io/pod-name -n ${NAMESPACE} --timeout=600s 2>/dev/null || \
    (echo "   Waiting for pods to be created..." && sleep 30 && kubectl wait --for=condition=ready pod -l platform.confluent.io/type=kraftcontroller -n ${NAMESPACE} --timeout=600s)
echo "   ✅ KRaft Controllers ready"
echo ""

echo "   Waiting for Kafka Brokers (3/3 pods)..."
kubectl wait --for=condition=ready pod -l platform.confluent.io/type=kafka -n ${NAMESPACE} --timeout=600s 2>/dev/null || \
    (echo "   Waiting for Kafka pods to be created..." && sleep 30 && kubectl wait --for=condition=ready pod -l platform.confluent.io/type=kafka -n ${NAMESPACE} --timeout=600s)
echo "   ✅ Kafka Brokers ready"
echo ""

echo "   Waiting for Control Center (may take a few minutes)..."
# Wait for the pod to exist first
for i in {1..60}; do
    if kubectl get pod controlcenter-0 -n ${NAMESPACE} &>/dev/null; then
        echo "   Control Center pod exists, waiting for readiness..."
        break
    fi
    echo "   Waiting for Control Center pod to be created... ($i/60)"
    sleep 5
done

# Control Center has 3 containers, so we need to be patient
for i in {1..60}; do
    READY=$(kubectl get pod controlcenter-0 -n ${NAMESPACE} -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null | grep -o "true" | wc -l | tr -d ' ')
    if [ "$READY" = "3" ]; then
        echo "   ✅ Control Center ready (all 3 containers running)"
        break
    fi
    echo "   Waiting... ($i/60) - $READY/3 containers ready"
    sleep 5
done
echo ""

# Step 8: Display status
echo "📊 Step 8: Deployment Status"
echo "=============================="
echo ""
kubectl get pods -n ${NAMESPACE}
echo ""
echo "🎉 Deployment complete!"
echo ""
echo "📝 Next steps:"
echo "   1. Access Control Center:"
echo "      kubectl port-forward -n ${NAMESPACE} controlcenter-0 9021:9021"
echo "      Then open: https://localhost:9021"
echo ""
echo "   2. Check component status:"
echo "      kubectl get kraftcontroller,kafka,controlcenter -n ${NAMESPACE}"
echo ""
echo "   3. View logs:"
echo "      kubectl logs -n ${NAMESPACE} controlcenter-0 -c controlcenter"
echo "      kubectl logs -n ${NAMESPACE} controlcenter-0 -c prometheus"
echo "      kubectl logs -n ${NAMESPACE} controlcenter-0 -c alertmanager"
echo ""
