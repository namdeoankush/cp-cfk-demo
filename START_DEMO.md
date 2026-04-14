# How to Start the Demo

## Scenario 1: Cluster Still Running (Quick Start)

If your Kubernetes cluster is still running and the pods are already deployed:

```bash
# Just start port-forward
kubectl port-forward -n confluent controlcenter-0 9021:9021
```

Then open: **https://localhost:9021** (accept the certificate warning)

---

## Scenario 2: Fresh Deployment (From Scratch)

If you stopped minikube or need to redeploy everything:

### Step 1: Start Kubernetes Cluster
```bash
minikube start
# OR whatever Kubernetes cluster you're using
```

### Step 2: Generate Certificates (if not already done)
```bash
cd ~/Handson/CFK/certs
./generate-certs.sh
```

### Step 3: Deploy Everything
```bash
cd ~/Handson/CFK/scripts
./deploy.sh
```

This script will:
- Create the `confluent` namespace
- Install CFK operator 3.1.1
- Create all Kubernetes secrets
- Deploy KRaft controllers, Kafka brokers, and Control Center
- Wait for all components to be ready

### Step 4: Access Control Center
```bash
kubectl port-forward -n confluent controlcenter-0 9021:9021
```

Then open: **https://localhost:9021**

---

## Quick Check: Is Everything Running?

```bash
kubectl get pods -n confluent
```

Expected output:
```
NAME                  READY   STATUS    RESTARTS   AGE
controlcenter-0       3/3     Running   0          Xm
kafka-0               1/1     Running   0          Xm
kafka-1               1/1     Running   0          Xm
kafka-2               1/1     Running   0          Xm
kraftcontroller-0     1/1     Running   0          Xm
kraftcontroller-1     1/1     Running   0          Xm
kraftcontroller-2     1/1     Running   0          Xm
```

If all pods are `Running` → Go to Scenario 1 (just port-forward)
If no pods exist → Go to Scenario 2 (full deployment)

---

## Cleanup (When Done Testing)

```bash
cd ~/Handson/CFK/scripts
./cleanup.sh
```

This will safely remove all components with confirmation prompts.

---

## TL;DR - Most Common Usage

**Next time you want to demo:**
```bash
# Check if already running
kubectl get pods -n confluent

# If running, just port-forward:
kubectl port-forward -n confluent controlcenter-0 9021:9021

# If not running, deploy:
cd ~/Handson/CFK/scripts && ./deploy.sh

# Then port-forward:
kubectl port-forward -n confluent controlcenter-0 9021:9021

# Open: https://localhost:9021
```
