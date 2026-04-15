# Kubernetes Troubleshooting Guide

## Quick Health Check Commands

Run these commands to get a quick overview of your cluster health:

```bash
# 1. Check cluster info
kubectl cluster-info

# 2. Check node status
kubectl get nodes

# 3. Check all pods across all namespaces
kubectl get pods -A

# 4. Check pods in your namespace
kubectl get pods -n confluent

# 5. Check all resources in namespace
kubectl get all -n confluent
```

---

## Storage Provisioner Issues

### 1. Check if Storage Provisioner is Running

```bash
# Check storage addon status (minikube)
minikube addons list | grep storage

# Check for storage provisioner pod
kubectl get pods -A | grep storage
kubectl get pods -n kube-system | grep storage-provisioner

# Check storage classes available
kubectl get storageclass
kubectl get sc
```

**What to look for:**
- ✅ `storage-provisioner` addon should be **enabled**
- ✅ Storage provisioner pod should be **Running** in kube-system namespace
- ✅ At least one StorageClass should exist (usually `standard` for minikube)

### 2. Check PersistentVolumeClaims (PVC) Status

```bash
# List all PVCs in your namespace
kubectl get pvc -n confluent

# Detailed info about a specific PVC
kubectl describe pvc <pvc-name> -n confluent

# Check events for PVC issues
kubectl get events -n confluent --sort-by='.lastTimestamp' | grep -i pvc
```

**PVC Status meanings:**
- `Pending` - Volume not yet created (PROBLEM)
- `Bound` - Volume successfully created and attached (GOOD)
- `Released` - Volume was used but now released (needs cleanup)
- `Lost` - Volume is lost/corrupted

### 3. Check PersistentVolumes (PV) Status

```bash
# List all PVs (cluster-wide)
kubectl get pv

# Detailed info about a specific PV
kubectl describe pv <pv-name>
```

**PV Status meanings:**
- `Available` - Ready to be claimed (GOOD)
- `Bound` - Bound to a PVC (GOOD)
- `Released` - PVC deleted but volume still exists (needs cleanup)
- `Failed` - Volume creation failed (PROBLEM)

### 4. Common Storage Issues and Fixes

#### Issue: PVCs stuck in "Pending"

```bash
# Check why PVC is pending
kubectl describe pvc <pvc-name> -n confluent

# Look for events like:
# - "waiting for a volume to be created"
# - "no persistent volumes available"
```

**Fixes:**

```bash
# Option 1: Restart storage provisioner
minikube addons disable storage-provisioner
minikube addons enable storage-provisioner

# Option 2: Delete old Released PVs
kubectl get pv | grep Released
kubectl delete pv <pv-name>

# Option 3: Check if storage provisioner pod is healthy
kubectl logs -n kube-system storage-provisioner
kubectl describe pod -n kube-system storage-provisioner
```

#### Issue: Old PVs in "Released" state blocking new volumes

```bash
# List all Released PVs
kubectl get pv | grep Released

# Delete them (they're orphaned from deleted PVCs)
kubectl delete pv <pv-name>

# Or delete all Released PVs at once
kubectl get pv | grep Released | awk '{print $1}' | xargs kubectl delete pv
```

---

## Pod Troubleshooting

### 1. Check Pod Status

```bash
# Quick status
kubectl get pods -n confluent

# Detailed status with more info
kubectl get pods -n confluent -o wide

# Watch pods in real-time
kubectl get pods -n confluent -w
```

**Pod Status meanings:**
- `Pending` - Waiting to be scheduled (check events)
- `ContainerCreating` - Starting up (normal)
- `Running` - Running (check READY column)
- `CrashLoopBackOff` - Container keeps crashing (check logs)
- `Error` - Container exited with error
- `ImagePullBackOff` - Can't pull container image
- `Completed` - Job/task finished successfully

### 2. Deep Dive into Pod Issues

```bash
# Get detailed pod information
kubectl describe pod <pod-name> -n confluent

# Check pod events (bottom of describe output)
kubectl describe pod <pod-name> -n confluent | grep -A 20 "Events:"

# Get all events in namespace sorted by time
kubectl get events -n confluent --sort-by='.lastTimestamp'

# Filter for warnings/errors
kubectl get events -n confluent --field-selector type=Warning
```

### 3. Check Container Logs

```bash
# Get logs from a pod (single container)
kubectl logs <pod-name> -n confluent

# Get logs from specific container (multi-container pods)
kubectl logs <pod-name> -c <container-name> -n confluent

# Follow logs in real-time
kubectl logs -f <pod-name> -n confluent

# Get previous container logs (if container restarted)
kubectl logs <pod-name> -n confluent --previous

# Get last N lines
kubectl logs <pod-name> -n confluent --tail=50

# Example: Control Center has 3 containers
kubectl logs controlcenter-0 -c controlcenter -n confluent
kubectl logs controlcenter-0 -c prometheus -n confluent
kubectl logs controlcenter-0 -c alertmanager -n confluent
```

### 4. Check Pod Resource Usage

```bash
# Get resource usage (requires metrics-server)
kubectl top pods -n confluent
kubectl top nodes

# Enable metrics-server in minikube
minikube addons enable metrics-server
```

### 5. Check Container Readiness/Liveness

```bash
# See which containers are ready
kubectl get pod <pod-name> -n confluent -o jsonpath='{range .status.containerStatuses[*]}{.name}{": ready="}{.ready}{", restarts="}{.restartCount}{"\n"}{end}'

# Check readiness probe configuration
kubectl get pod <pod-name> -n confluent -o yaml | grep -A 10 readinessProbe
kubectl get pod <pod-name> -n confluent -o yaml | grep -A 10 livenessProbe
```

---

## CFK-Specific Troubleshooting

### 1. Check CFK Operator

```bash
# Check if operator is running
kubectl get pods -n confluent | grep operator

# Check operator logs
kubectl logs -f deployment/confluent-operator -n confluent

# Check operator version
helm list -n confluent
```

### 2. Check CFK Custom Resources

```bash
# Check KRaftController status
kubectl get kraftcontroller -n confluent
kubectl describe kraftcontroller kraftcontroller -n confluent

# Check Kafka status
kubectl get kafka -n confluent
kubectl describe kafka kafka -n confluent

# Check Control Center status
kubectl get controlcenter -n confluent
kubectl describe controlcenter controlcenter -n confluent
```

### 3. Check CFK Secrets

```bash
# List all secrets
kubectl get secrets -n confluent

# Check if TLS secrets exist
kubectl get secret kraftcontroller-tls -n confluent
kubectl get secret kafka-tls -n confluent
kubectl get secret controlcenter-tls -n confluent

# Describe a secret (shows keys but not values)
kubectl describe secret kraftcontroller-tls -n confluent

# Verify certificate files in secret
kubectl get secret kraftcontroller-tls -n confluent -o jsonpath='{.data}' | jq 'keys'
```

---

## Network Troubleshooting

### 1. Check Services

```bash
# List all services
kubectl get svc -n confluent

# Describe a service
kubectl describe svc <service-name> -n confluent

# Check service endpoints
kubectl get endpoints -n confluent
```

### 2. Test Connectivity

```bash
# Port-forward to test connectivity
kubectl port-forward -n confluent <pod-name> <local-port>:<pod-port>

# Example: Access Control Center
kubectl port-forward -n confluent controlcenter-0 9021:9021

# Run a test pod for debugging
kubectl run -it --rm debug --image=busybox --restart=Never -n confluent -- sh

# From inside the debug pod, test connectivity:
# wget -O- http://kafka.confluent.svc.cluster.local:9071
# nslookup kafka.confluent.svc.cluster.local
```

---

## Complete Health Check Script

Save this as `check-health.sh`:

```bash
#!/bin/bash

NAMESPACE="confluent"

echo "=== Kubernetes Cluster Health Check ==="
echo ""

echo "1. Cluster Info:"
kubectl cluster-info
echo ""

echo "2. Node Status:"
kubectl get nodes
echo ""

echo "3. Storage Provisioner:"
kubectl get pods -n kube-system | grep storage || echo "No storage provisioner found!"
echo ""

echo "4. Storage Classes:"
kubectl get sc
echo ""

echo "5. PersistentVolumes:"
kubectl get pv
echo ""

echo "6. PVCs in ${NAMESPACE}:"
kubectl get pvc -n ${NAMESPACE}
echo ""

echo "7. Pods in ${NAMESPACE}:"
kubectl get pods -n ${NAMESPACE}
echo ""

echo "8. CFK Resources:"
kubectl get kraftcontroller,kafka,controlcenter -n ${NAMESPACE}
echo ""

echo "9. Recent Events (last 20):"
kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | tail -20
echo ""

echo "10. Secrets:"
kubectl get secrets -n ${NAMESPACE}
echo ""

echo "=== Health Check Complete ==="
```

Make it executable:
```bash
chmod +x check-health.sh
./check-health.sh
```

---

## Common Issues Quick Reference

| Issue | Command to Check | Fix |
|-------|-----------------|-----|
| PVC stuck Pending | `kubectl describe pvc <name> -n confluent` | Restart storage provisioner or delete Released PVs |
| Pod CrashLoopBackOff | `kubectl logs <pod> -n confluent` | Check logs for errors, fix configuration |
| Pod Pending | `kubectl describe pod <name> -n confluent` | Check events for scheduling issues |
| Image Pull Error | `kubectl describe pod <name> -n confluent` | Check image name, registry access |
| Storage provisioner down | `kubectl get pods -n kube-system \| grep storage` | `minikube addons enable storage-provisioner` |
| Old Released PVs | `kubectl get pv \| grep Released` | Delete old PVs: `kubectl delete pv <name>` |
| Can't connect to service | `kubectl get svc -n confluent` | Check service exists, port-forward to test |
| Secrets missing | `kubectl get secrets -n confluent` | Re-run deployment script |

---

## Useful Kubectl Aliases

Add these to your `~/.bashrc` or `~/.zshrc`:

```bash
# General aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpw='kubectl get pods -w'
alias kgpa='kubectl get pods -A'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias klf='kubectl logs -f'

# Namespace-specific (adjust to your namespace)
alias kgpc='kubectl get pods -n confluent'
alias kgac='kubectl get all -n confluent'
alias kdc='kubectl describe -n confluent'
alias klc='kubectl logs -n confluent'

# Quick checks
alias kpvc='kubectl get pvc -A'
alias kpv='kubectl get pv'
alias ksc='kubectl get sc'
```

---

## Emergency Recovery

If everything is broken:

```bash
# 1. Clean up completely
./scripts/cleanup.sh

# 2. Delete all PVs
kubectl delete pv --all

# 3. Restart minikube (if using minikube)
minikube stop
minikube start

# 4. Re-enable addons
minikube addons enable storage-provisioner
minikube addons enable default-storageclass
minikube addons enable metrics-server

# 5. Re-deploy
./scripts/deploy.sh
```
