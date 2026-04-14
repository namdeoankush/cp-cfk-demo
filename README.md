# Confluent Platform 7.9.4 with KRaft and Control Center Next-Gen

This repository contains a working deployment of **Confluent Platform 7.9.4** running in **KRaft mode** (no ZooKeeper) with **Control Center Next-Gen 2.0** including embedded Prometheus and AlertManager monitoring services.

## 📋 What's Included

- **KRaft Controllers** - 3 replicas with mTLS authentication
- **Kafka Brokers** - 3 replicas (CP 7.9.4) with mTLS authentication
- **Control Center Next-Gen 2.0** with:
  - Embedded Prometheus for metrics collection
  - Embedded AlertManager for alerting
  - Full mTLS security between all components

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Control Center Next-Gen                │
│  ┌─────────────┐  ┌─────────────┐  ┌───────────────┐  │
│  │ Control     │  │ Prometheus  │  │ AlertManager  │  │
│  │ Center      │  │ (embedded)  │  │ (embedded)    │  │
│  │ :9021       │  │ :9090       │  │ :9093         │  │
│  └─────────────┘  └─────────────┘  └───────────────┘  │
└───────────────────────────┬─────────────────────────────┘
                            │ mTLS
        ┌───────────────────┼───────────────────┐
        │                   │                   │
┌───────▼────────┐  ┌───────▼────────┐  ┌──────▼─────────┐
│ Kafka Broker 0 │  │ Kafka Broker 1 │  │ Kafka Broker 2 │
│    :9071       │  │    :9071       │  │    :9071       │
└────────────────┘  └────────────────┘  └────────────────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            │ mTLS
        ┌───────────────────┼───────────────────┐
        │                   │                   │
┌───────▼────────┐  ┌───────▼────────┐  ┌──────▼─────────┐
│ KRaft Ctrl 0   │  │ KRaft Ctrl 1   │  │ KRaft Ctrl 2   │
│    :9074       │  │    :9074       │  │    :9074       │
└────────────────┘  └────────────────┘  └────────────────┘
```

## 🔧 Prerequisites

- **Kubernetes cluster** (tested with minikube)
- **kubectl** configured to access your cluster
- **helm** version 3.x
- **openssl** for certificate generation
- **keytool** (comes with Java JDK)

## 🚀 Quick Start

### 1. Generate Certificates

```bash
cd certs
./generate-certs.sh
cd ..
```

This creates:
- CA certificates
- JKS keystores/truststores for Kafka components
- PEM certificates with Extended Key Usage (EKU) for Prometheus/AlertManager

### 2. Deploy Confluent Platform

```bash
cd scripts
./deploy.sh
```

This will:
1. Create the `confluent` namespace
2. Install CFK operator 3.1.1
3. Create all required Kubernetes secrets
4. Deploy KRaft controllers, Kafka brokers, and Control Center
5. Wait for all components to be ready

### 3. Access Control Center

```bash
kubectl port-forward -n confluent controlcenter-0 9021:9021
```

Then open: **https://localhost:9021**

> ⚠️ **Note**: The deployment uses self-signed certificates. You'll need to accept the security warning in your browser.

## 📊 Verify Deployment

### Check Pod Status

```bash
kubectl get pods -n confluent
```

Expected output:
```
NAME                  READY   STATUS    RESTARTS   AGE
controlcenter-0       3/3     Running   0          5m
kafka-0               1/1     Running   0          6m
kafka-1               1/1     Running   0          6m
kafka-2               1/1     Running   0          6m
kraftcontroller-0     1/1     Running   0          7m
kraftcontroller-1     1/1     Running   0          7m
kraftcontroller-2     1/1     Running   0          7m
```

### Check Component Status

```bash
kubectl get kraftcontroller,kafka,controlcenter -n confluent
```

### View Logs

```bash
# Control Center main container
kubectl logs -n confluent controlcenter-0 -c controlcenter

# Prometheus container
kubectl logs -n confluent controlcenter-0 -c prometheus

# AlertManager container
kubectl logs -n confluent controlcenter-0 -c alertmanager
```

## 🔐 Security Configuration

### mTLS Authentication

All components communicate using **proper mutual TLS (mTLS)** with **separate client and server certificates**:
- KRaft Controllers ↔️ Kafka Brokers
- Control Center ↔️ Kafka Brokers
- Control Center ↔️ Prometheus (embedded) - **Separate client cert**
- Control Center ↔️ AlertManager (embedded) - **Separate client cert**

> 📖 **See [SECURITY.md](SECURITY.md) and [CERTIFICATE_ARCHITECTURE.md](CERTIFICATE_ARCHITECTURE.md)** for detailed certificate architecture and mTLS design.

### Certificate Details

| Component | Format | Usage | Secret Name |
|-----------|--------|-------|-------------|
| KRaft Controllers | JKS | Server & Client | `kraftcontroller-tls` |
| Kafka Brokers | JKS | Server & Client | `kafka-tls` |
| Control Center | JKS | Server & Client | `controlcenter-tls` |
| **Prometheus (Server)** | PEM with EKU | Server | `prometheus-tls` |
| **Prometheus (Client)** | PEM with EKU | Client (Control Center) | `prometheus-client-tls` ⭐ |
| **AlertManager (Server)** | PEM with EKU | Server | `alertmanager-tls` |
| **AlertManager (Client)** | PEM with EKU | Client (Control Center) | `alertmanager-client-tls` ⭐ |

> ⭐ **Proper mTLS**: Client and server use **different certificates**, following security best practices.  
> **Important**: All certificates include Extended Key Usage (EKU) extensions for `serverAuth` and `clientAuth`.

## 🎛️ Configuration

### Key Settings

- **Confluent Platform Version**: 7.9.4
- **Control Center Next-Gen Version**: 2.0.0
- **CFK Operator Version**: 3.1.1 (chart 0.1351.59)
- **Init Container Version**: 2.11.1
- **Prometheus Version**: 2.0.0
- **AlertManager Version**: 2.0.0

### Resource Limits

#### KRaft Controllers
- Memory: 512Mi (request) / 2Gi (limit)
- CPU: 200m (request) / 1000m (limit)
- Storage: 10Gi

#### Kafka Brokers
- Memory: 1Gi (request) / 2Gi (limit)
- CPU: 500m (request) / 1000m (limit)
- Storage: 10Gi

#### Control Center
- Memory: 2Gi (request) / 4Gi (limit)
- CPU: 500m (request) / 2000m (limit)
- Storage: 10Gi (data) + 10Gi (prometheus) + 10Gi (alertmanager)

### Kafka Settings

```yaml
configOverrides:
  server:
    - sni.host.check.enabled=false
    - offsets.topic.replication.factor=3
    - transaction.state.log.replication.factor=3
    - min.insync.replicas=2
```

## 🧹 Cleanup

To remove the entire deployment:

```bash
cd scripts
./cleanup.sh
```

This will prompt you to confirm deletion of:
1. Confluent Platform components
2. Kubernetes secrets
3. CFK operator
4. Namespace (optional)

## 📁 Directory Structure

```
CFK/
├── README.md                    # This file
├── certs/
│   └── generate-certs.sh        # Certificate generation script
├── manifests/
│   └── confluent-platform.yaml  # Kubernetes manifests
└── scripts/
    ├── deploy.sh                # Deployment automation script
    └── cleanup.sh               # Cleanup script
```

## 🐛 Troubleshooting

### Control Center Pod Not Starting

Check all three containers:

```bash
kubectl describe pod controlcenter-0 -n confluent
kubectl logs -n confluent controlcenter-0 -c controlcenter --tail=100
kubectl logs -n confluent controlcenter-0 -c prometheus --tail=100
kubectl logs -n confluent controlcenter-0 -c alertmanager --tail=100
```

### Certificate Issues

If you see TLS handshake errors:

1. Verify EKU extensions in Prometheus/AlertManager certs:
   ```bash
   cd certs
   openssl x509 -in prometheus-cert.pem -text -noout | grep -A 3 "Extended Key Usage"
   ```

2. Regenerate certificates:
   ```bash
   cd certs
   rm -f *.pem *.jks *.p12 *.txt
   ./generate-certs.sh
   ```

3. Update secrets:
   ```bash
   cd scripts
   ./cleanup.sh
   ./deploy.sh
   ```

### CFK Operator CrashLooping

This is a known issue with CFK 3.1.1 - the operator may crash periodically but the deployed resources continue to function normally. This can be safely ignored.

## 📚 Key Learnings

### Why CFK 3.1.1 and Not 3.2.1?

- **CFK 3.2.1**: Has issues with Control Center Next-Gen deployment. The operator doesn't create the required run scripts for embedded Prometheus/AlertManager sidecars (`/mnt/config/prometheus/bin/run`).

- **CFK 3.1.1**: Works correctly with Control Center Next-Gen 2.0.0, properly initializing all three containers.

### Certificate Format Requirements

- **Kafka Components** (KRaft, Kafka, Control Center main): Use JKS format
- **Embedded Services** (Prometheus, AlertManager): Require PEM format with **Extended Key Usage (EKU)** extensions
  - Without EKU: `Extended key usage does not permit use for TLS server authentication`
  - With EKU: Successful TLS handshake

### No ZooKeeper Required

This deployment uses **KRaft mode** exclusively:
- No ZooKeeper dependencies
- Simpler architecture
- Better performance
- Future-proof (ZooKeeper removal is the future of Kafka)

## 📖 References

- [Confluent Platform Documentation](https://docs.confluent.io/platform/current/overview.html)
- [Confluent for Kubernetes](https://docs.confluent.io/operator/current/overview.html)
- [Control Center Next-Gen](https://docs.confluent.io/control-center/current/index.html)
- [KRaft Mode](https://docs.confluent.io/platform/current/kafka-metadata/kraft.html)

## 📝 License

This demo is for educational purposes. Confluent Platform requires appropriate licensing for production use.

## 🤝 Contributing

Feel free to submit issues or pull requests to improve this demo.

---

**Last Updated**: April 14, 2026  
**Tested On**: minikube v1.x, Kubernetes v1.31  
**Status**: ✅ Working
