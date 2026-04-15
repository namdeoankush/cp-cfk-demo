#!/bin/bash
# Kubernetes Validation Script
# Run this before deploying to check if your cluster is healthy

set +e  # Don't exit on errors, we want to show all checks

NAMESPACE="confluent"
FAILED_CHECKS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Kubernetes Cluster Validation"
echo "=================================="
echo ""

# Check 1: kubectl connectivity
echo -n "1. Checking kubectl connectivity... "
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✓ OK${NC}"
else
    echo -e "${RED}✗ FAILED${NC} - Cannot connect to cluster"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 2: Nodes ready
echo -n "2. Checking node status... "
NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready " | wc -l | tr -d ' ')
if [ "$NOT_READY" = "0" ]; then
    echo -e "${GREEN}✓ OK${NC} - All nodes ready"
else
    echo -e "${RED}✗ FAILED${NC} - $NOT_READY nodes not ready"
    kubectl get nodes
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 3: Storage provisioner
echo -n "3. Checking storage provisioner... "
if kubectl get pods -n kube-system 2>/dev/null | grep -q "storage-provisioner.*Running"; then
    echo -e "${GREEN}✓ OK${NC} - Storage provisioner running"
elif minikube addons list 2>/dev/null | grep "storage-provisioner" | grep -q "enabled"; then
    echo -e "${YELLOW}⚠ WARNING${NC} - Addon enabled but pod not found, restarting..."
    minikube addons disable storage-provisioner &>/dev/null
    minikube addons enable storage-provisioner &>/dev/null
    sleep 3
    if kubectl get pods -n kube-system 2>/dev/null | grep -q "storage-provisioner.*Running"; then
        echo -e "   ${GREEN}✓ FIXED${NC} - Storage provisioner now running"
    else
        echo -e "   ${RED}✗ FAILED${NC} - Storage provisioner still not running"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
else
    echo -e "${RED}✗ FAILED${NC} - Storage provisioner not available"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 4: Storage class
echo -n "4. Checking storage class... "
if kubectl get storageclass 2>/dev/null | grep -q "standard"; then
    echo -e "${GREEN}✓ OK${NC} - Default storage class exists"
else
    echo -e "${RED}✗ FAILED${NC} - No storage class found"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 5: Old PVs in Released state
echo -n "5. Checking for orphaned PersistentVolumes... "
RELEASED_PVS=$(kubectl get pv 2>/dev/null | grep Released | wc -l | tr -d ' ')
if [ "$RELEASED_PVS" = "0" ]; then
    echo -e "${GREEN}✓ OK${NC} - No orphaned PVs"
else
    echo -e "${YELLOW}⚠ WARNING${NC} - Found $RELEASED_PVS Released PVs (may block new deployments)"
    echo "   Run this to clean up: kubectl get pv | grep Released | awk '{print \$1}' | xargs kubectl delete pv"
fi

# Check 6: Helm installed
echo -n "6. Checking Helm installation... "
if command -v helm &>/dev/null; then
    HELM_VERSION=$(helm version --short 2>/dev/null)
    echo -e "${GREEN}✓ OK${NC} - Helm installed ($HELM_VERSION)"
else
    echo -e "${RED}✗ FAILED${NC} - Helm not installed"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Check 7: Helm repo
echo -n "7. Checking Confluent Helm repo... "
if helm repo list 2>/dev/null | grep -q "confluentinc"; then
    echo -e "${GREEN}✓ OK${NC} - Confluent repo configured"
else
    echo -e "${YELLOW}⚠ WARNING${NC} - Confluent repo not found, adding..."
    helm repo add confluentinc https://packages.confluent.io/helm &>/dev/null
    helm repo update confluentinc &>/dev/null
    echo -e "   ${GREEN}✓ FIXED${NC} - Repo added"
fi

# Check 8: Namespace
echo -n "8. Checking namespace '${NAMESPACE}'... "
if kubectl get namespace ${NAMESPACE} &>/dev/null; then
    echo -e "${YELLOW}⚠ WARNING${NC} - Namespace exists (may be from previous deployment)"
    PODS=$(kubectl get pods -n ${NAMESPACE} --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$PODS" != "0" ]; then
        echo "   Found $PODS pods in namespace. Consider running cleanup.sh first."
    fi
else
    echo -e "${GREEN}✓ OK${NC} - Namespace doesn't exist (will be created)"
fi

# Check 9: Certificates
echo -n "9. Checking certificates... "
if [ -f "../certs/ca-cert.pem" ] && [ -f "../certs/kraftcontroller.keystore.jks" ]; then
    echo -e "${GREEN}✓ OK${NC} - Certificates exist"
elif [ -f "certs/ca-cert.pem" ] && [ -f "certs/kraftcontroller.keystore.jks" ]; then
    echo -e "${GREEN}✓ OK${NC} - Certificates exist"
else
    echo -e "${YELLOW}⚠ INFO${NC} - Certificates not found (will be generated)"
fi

# Check 10: CFK CRDs
echo -n "10. Checking CFK CRDs... "
if kubectl get crd kraftcontrollers.platform.confluent.io &>/dev/null; then
    CRD_COUNT=$(kubectl get crd 2>/dev/null | grep "platform.confluent.io" | wc -l | tr -d ' ')
    echo -e "${GREEN}✓ OK${NC} - CFK CRDs installed ($CRD_COUNT found)"
else
    echo -e "${YELLOW}⚠ INFO${NC} - CFK CRDs not installed (will be installed by operator)"
fi

# Summary
echo ""
echo "=================================="
if [ $FAILED_CHECKS -eq 0 ]; then
    echo -e "${GREEN}✓ Validation PASSED${NC} - Cluster is ready for deployment"
    echo ""
    echo "Run: ./scripts/deploy.sh"
    exit 0
else
    echo -e "${RED}✗ Validation FAILED${NC} - Found $FAILED_CHECKS critical issue(s)"
    echo ""
    echo "Please fix the issues above before deploying."
    exit 1
fi
