# Kubernetes Quick Reference Card

## Before Deployment - Run This First

```bash
# Run the validation script
./scripts/validate-k8s.sh
```

---

## Storage Provisioner (Most Common Issue)

```bash
# Check if storage provisioner is running
kubectl get pods -n kube-system | grep storage

# Check storage addons
minikube addons list | grep storage

# Fix: Restart storage provisioner
minikube addons disable storage-provisioner
minikube addons enable storage-provisioner

# Check for orphaned PVs (blocks new volumes)
kubectl get pv | grep Released

# Clean up orphaned PVs
kubectl get pv | grep Released | awk '{print $1}' | xargs kubectl delete pv
```

---

## Pod Status Quick Check

```bash
# Quick status
kubectl get pods -n confluent

# Watch in real-time
kubectl get pods -n confluent -w

# Detailed status
kubectl get pods -n confluent -o wide

# Check specific pod
kubectl describe pod <pod-name> -n confluent
```

---

## When Pods Are Stuck

```bash
# Check WHY pod is stuck
kubectl describe pod <pod-name> -n confluent | grep -A 20 "Events:"

# Check logs
kubectl logs <pod-name> -n confluent

# For multi-container pods (like Control Center)
kubectl logs <pod-name> -c <container-name> -n confluent

# Previous logs (if container restarted)
kubectl logs <pod-name> -n confluent --previous
```

---

## Storage Issues Checklist

1. **Is storage provisioner running?**
   ```bash
   kubectl get pods -n kube-system | grep storage
   ```

2. **Are PVCs bound?**
   ```bash
   kubectl get pvc -n confluent
   ```
   All should show `Bound`, not `Pending`

3. **Any orphaned PVs?**
   ```bash
   kubectl get pv | grep Released
   ```
   If yes, delete them

4. **Storage class exists?**
   ```bash
   kubectl get sc
   ```
   Should see `standard (default)`

---

## CFK-Specific Checks

```bash
# Check CFK operator
kubectl get pods -n confluent | grep operator

# Check CFK resources
kubectl get kraftcontroller,kafka,controlcenter -n confluent

# Check operator logs
kubectl logs -f deployment/confluent-operator -n confluent

# Check secrets
kubectl get secrets -n confluent
```

---

## Events (Shows Recent Issues)

```bash
# Recent events in namespace
kubectl get events -n confluent --sort-by='.lastTimestamp' | tail -20

# Only warnings
kubectl get events -n confluent --field-selector type=Warning

# Only errors
kubectl get events -n confluent --field-selector type=Error
```

---

## Common Error Patterns

| Error in Events | Meaning | Fix |
|----------------|---------|-----|
| `pod has unbound immediate PersistentVolumeClaims` | PVC stuck Pending | Check storage provisioner, delete Released PVs |
| `waiting for a volume to be created` | Storage provisioner issue | Restart storage provisioner addon |
| `ImagePullBackOff` | Can't pull image | Check image name, internet connection |
| `CrashLoopBackOff` | Container keeps crashing | Check logs: `kubectl logs <pod>` |
| `no nodes available` | Scheduling issue | Check node status: `kubectl get nodes` |

---

## Full Health Check

```bash
# All-in-one health check
kubectl get nodes && \
kubectl get pods -n kube-system | grep storage && \
kubectl get sc && \
kubectl get pv && \
kubectl get pvc -n confluent && \
kubectl get pods -n confluent
```

---

## Clean Slate (Nuclear Option)

If everything is broken:

```bash
# 1. Clean up deployment
./scripts/cleanup.sh

# 2. Delete all PVs
kubectl delete pv --all

# 3. Restart minikube
minikube stop
minikube start

# 4. Enable storage
minikube addons enable storage-provisioner

# 5. Validate
./scripts/validate-k8s.sh

# 6. Deploy
./scripts/deploy.sh
```

---

## Access Control Center

```bash
# Port-forward (run in separate terminal)
kubectl port-forward -n confluent controlcenter-0 9021:9021

# Then open browser to:
# https://localhost:9021
```

---

## Useful Aliases (Add to ~/.zshrc)

```bash
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpc='kubectl get pods -n confluent'
alias kl='kubectl logs'
alias kd='kubectl describe'
alias kpvc='kubectl get pvc -A'
alias kpv='kubectl get pv'
```
