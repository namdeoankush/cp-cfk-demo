# Quick Start Guide

Get Confluent Platform 7.9.4 with KRaft and Control Center Next-Gen running in **3 simple steps**.

## Prerequisites Check

```bash
# Verify tools are installed
kubectl version --client
helm version
openssl version
keytool -help
```

## Step 1: Generate Certificates (5 minutes)

```bash
cd certs
./generate-certs.sh
```

**Expected output:**
```
🔐 Generating certificates for Confluent Platform...
📜 Step 1: Creating Certificate Authority (CA)...
✅ CA certificate created
📦 Step 2: Generating KRaft Controller certificates...
✅ kraftcontroller certificates created (JKS format)
...
🎉 All certificates generated successfully!
```

## Step 2: Deploy (10-15 minutes)

```bash
cd ../scripts
./deploy.sh
```

**What it does:**
- Creates `confluent` namespace
- Installs CFK operator 3.1.1
- Creates Kubernetes secrets
- Deploys KRaft, Kafka, and Control Center
- Waits for all components to be ready

**Expected final output:**
```
NAME                  READY   STATUS    RESTARTS   AGE
controlcenter-0       3/3     Running   0          5m
kafka-0               1/1     Running   0          6m
kafka-1               1/1     Running   0          6m
kafka-2               1/1     Running   0          6m
kraftcontroller-0     1/1     Running   0          7m
kraftcontroller-1     1/1     Running   0          7m
kraftcontroller-2     1/1     Running   0          7m

🎉 Deployment complete!
```

## Step 3: Access Control Center

```bash
kubectl port-forward -n confluent controlcenter-0 9021:9021
```

Open in browser: **https://localhost:9021**

> ⚠️ Accept the security warning (self-signed certificate)

## Verify Everything Works

### Check All Pods Running

```bash
kubectl get pods -n confluent
```

All pods should show `Running` status with the correct `READY` count:
- `controlcenter-0`: `3/3` (controlcenter + prometheus + alertmanager)
- `kafka-*`: `1/1`
- `kraftcontroller-*`: `1/1`

### Test Kafka Connectivity

```bash
# Create a test topic
kubectl exec -it -n confluent kafka-0 -- kafka-topics \
  --create \
  --topic test-topic \
  --bootstrap-server kafka.confluent.svc.cluster.local:9071 \
  --command-config /opt/confluentinc/etc/kafka/kafka.properties \
  --replication-factor 3 \
  --partitions 6
```

### View Component Status in Control Center

In the Control Center UI (https://localhost:9021), you should see:
- **3 Kafka brokers** online
- **Cluster health** showing green
- **Topics** list (including internal topics)
- **Prometheus metrics** being collected

## Common Issues

### Pods Not Starting

```bash
# Check operator logs
kubectl logs -n confluent deployment/confluent-operator

# Check specific pod
kubectl describe pod <pod-name> -n confluent
```

### Can't Access Control Center

```bash
# Verify port-forward is running
ps aux | grep port-forward

# Check Control Center is ready
kubectl get pod controlcenter-0 -n confluent
# Should show 3/3 READY

# Check logs
kubectl logs -n confluent controlcenter-0 -c controlcenter --tail=50
```

### Certificate Errors

```bash
# Regenerate certificates
cd certs
rm -f *.pem *.jks *.p12 *.txt *.csr *.conf *.srl
./generate-certs.sh

# Redeploy
cd ../scripts
./cleanup.sh
./deploy.sh
```

## Next Steps

- **Create topics**: Use Control Center UI or kafka-topics CLI
- **Produce/Consume messages**: Test with kafka-console-producer/consumer
- **Monitor metrics**: Explore Prometheus integration in Control Center
- **Configure alerts**: Set up AlertManager rules

## Clean Up

When you're done:

```bash
cd scripts
./cleanup.sh
```

This will remove all deployed resources.

---

**Need more details?** See [README.md](README.md) for complete documentation.
