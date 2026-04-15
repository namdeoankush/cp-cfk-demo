# Prerequisites

This document outlines all the prerequisites and setup requirements for deploying Confluent Platform with KRaft mode and Control Center Next-Gen.

## Table of Contents
- [Local Development Prerequisites](#local-development-prerequisites)
- [Production Setup Requirements](#production-setup-requirements)
- [System Requirements](#system-requirements)
- [Verification Steps](#verification-steps)

---

## Local Development Prerequisites

### 1. Container Runtime

**Docker Desktop** (or equivalent container runtime)

- **What it does**: Provides the container runtime for Kubernetes
- **Installation**:
  - **macOS**: Download from [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/)
  - **Windows**: Download from [Docker Desktop for Windows](https://docs.docker.com/desktop/install/windows-install/)
  - **Linux**: Install Docker Engine from [Docker for Linux](https://docs.docker.com/engine/install/)

- **Verify installation**:
  ```bash
  docker --version
  docker ps
  ```

### 2. Kubernetes Cluster

**Minikube** (recommended for local development)

- **What it does**: Runs a local Kubernetes cluster on your machine
- **Installation**:
  ```bash
  # macOS
  brew install minikube
  
  # Linux
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  sudo install minikube-linux-amd64 /usr/local/bin/minikube
  
  # Windows (using Chocolatey)
  choco install minikube
  ```

- **Starting minikube**:
  ```bash
  # Start with sufficient resources
  minikube start --cpus=4 --memory=8192 --disk-size=20g
  
  # Verify it's running
  minikube status
  ```

- **Alternatives**: Docker Desktop (with Kubernetes enabled), kind, k3s

### 3. kubectl (Kubernetes CLI)

**kubectl** - Command-line tool for Kubernetes

- **What it does**: Allows you to run commands against Kubernetes clusters
- **Installation**:
  ```bash
  # macOS
  brew install kubectl
  
  # Linux
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  
  # Windows (using Chocolatey)
  choco install kubernetes-cli
  ```

- **Verify installation**:
  ```bash
  kubectl version --client
  kubectl cluster-info
  ```

### 4. Helm (Package Manager)

**Helm v3.x** - Kubernetes package manager

- **What it does**: Manages Kubernetes applications and installs the CFK operator
- **Installation**:
  ```bash
  # macOS
  brew install helm
  
  # Linux
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  
  # Windows (using Chocolatey)
  choco install kubernetes-helm
  ```

- **Verify installation**:
  ```bash
  helm version
  ```

### 5. OpenSSL

**openssl** - Cryptography toolkit

- **What it does**: Generates SSL/TLS certificates for secure communication
- **Installation**:
  ```bash
  # macOS (usually pre-installed)
  brew install openssl
  
  # Linux (usually pre-installed)
  sudo apt-get install openssl  # Ubuntu/Debian
  sudo yum install openssl       # RHEL/CentOS
  
  # Windows
  # Download from https://slproweb.com/products/Win32OpenSSL.html
  ```

- **Verify installation**:
  ```bash
  openssl version
  ```

### 6. Java JDK (for keytool)

**keytool** - Key and certificate management tool

- **What it does**: Creates JKS keystores and truststores for Kafka components
- **Installation**:
  ```bash
  # macOS
  brew install openjdk@11
  
  # Linux
  sudo apt-get install openjdk-11-jdk  # Ubuntu/Debian
  sudo yum install java-11-openjdk      # RHEL/CentOS
  
  # Windows
  # Download from https://www.oracle.com/java/technologies/downloads/
  ```

- **Verify installation**:
  ```bash
  keytool -help
  java -version
  ```

### 7. Bash Shell

**bash** - Unix shell

- **What it does**: Required to run the deployment scripts
- **Availability**:
  - **macOS/Linux**: Pre-installed
  - **Windows**: Use Git Bash or WSL (Windows Subsystem for Linux)

- **Verify installation**:
  ```bash
  bash --version
  ```

---

## Production Setup Requirements

### 1. Managed Kubernetes Service

**Instead of minikube, use a managed Kubernetes service:**

- **AWS**: Amazon EKS (Elastic Kubernetes Service)
- **Google Cloud**: Google GKE (Google Kubernetes Engine)
- **Azure**: Azure AKS (Azure Kubernetes Service)
- **Other**: Red Hat OpenShift, VMware Tanzu

**Minimum cluster configuration:**
- **Nodes**: 3-6 nodes (for high availability)
- **Node size**: 8 vCPUs, 32GB RAM per node
- **Kubernetes version**: 1.27 or later (tested on 1.31)
- **Network**: Private VPC with proper security groups

### 2. Certificate Management

**Production certificates (not self-signed):**

- **Certificate Authority**:
  - Use enterprise CA (Let's Encrypt, DigiCert, internal PKI)
  - Implement certificate rotation policies
  - Use cert-manager for automated certificate management

- **Secret Management**:
  - Use Kubernetes External Secrets Operator
  - Integrate with HashiCorp Vault, AWS Secrets Manager, or Azure Key Vault
  - Enable encryption at rest for Kubernetes secrets

### 3. Storage

**Persistent Storage Classes:**

- **Requirements**:
  - Production-grade storage (AWS EBS, GCP Persistent Disk, Azure Disk)
  - Automated snapshots and backups
  - Volume size: Minimum 100Gi per component (not 10Gi as in demo)
  - Storage class with `volumeBindingMode: WaitForFirstConsumer`

- **Example storage classes**:
  - AWS: `gp3` (recommended), `io1/io2` (high IOPS)
  - GCP: `pd-ssd` (recommended), `pd-balanced`
  - Azure: `managed-premium`

### 4. Networking

**Load Balancers and Ingress:**

- **External access**: 
  - Use cloud load balancers (AWS ALB/NLB, GCP Load Balancer, Azure Load Balancer)
  - Configure Ingress controllers (NGINX, Traefik, Istio)
  - TLS termination at load balancer

- **Internal networking**:
  - Service mesh for mTLS (Istio, Linkerd)
  - Network policies for pod-to-pod communication
  - Private endpoints for sensitive services

### 5. Resource Allocation

**Production resource limits (scale up from demo):**

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|-------------|-----------|----------------|--------------|---------|
| KRaft Controllers | 1000m | 2000m | 2Gi | 4Gi | 100Gi |
| Kafka Brokers | 2000m | 4000m | 4Gi | 8Gi | 500Gi-1Ti |
| Control Center | 2000m | 4000m | 4Gi | 8Gi | 100Gi |
| Prometheus | 1000m | 2000m | 2Gi | 4Gi | 500Gi |
| AlertManager | 500m | 1000m | 1Gi | 2Gi | 50Gi |

### 6. Monitoring and Observability

**Production monitoring stack:**

- **Metrics**:
  - Prometheus (already included in Control Center)
  - Grafana for visualization
  - Custom dashboards for Kafka metrics

- **Logging**:
  - Centralized logging (ELK stack, Splunk, CloudWatch)
  - Log aggregation from all components
  - Log retention policies

- **Alerting**:
  - AlertManager (already included)
  - PagerDuty/Opsgenie integration
  - Custom alert rules for Kafka-specific metrics

- **Tracing**:
  - Distributed tracing (Jaeger, Zipkin)
  - Request tracing across microservices

### 7. High Availability

**Multi-zone/region deployment:**

- **Topology**:
  - Deploy across multiple availability zones
  - Use pod anti-affinity rules
  - Configure topology spread constraints

- **Replication**:
  - Increase replication factor to 3 or 5
  - Configure `min.insync.replicas` appropriately
  - Enable rack awareness

- **Example configuration**:
  ```yaml
  configOverrides:
    server:
      - offsets.topic.replication.factor=3
      - transaction.state.log.replication.factor=3
      - min.insync.replicas=2
      - default.replication.factor=3
      - broker.rack=${RACK_ID}
  ```

### 8. Security

**Production security hardening:**

- **Network security**:
  - Network policies to restrict pod communication
  - VPN or private connectivity for cluster access
  - WAF (Web Application Firewall) for external endpoints

- **Authentication & Authorization**:
  - RBAC (Role-Based Access Control) in Kubernetes
  - SASL/SCRAM or LDAP for Kafka authentication
  - OAuth/OIDC integration for Control Center

- **Compliance**:
  - Data encryption in transit (mTLS)
  - Data encryption at rest
  - Audit logging enabled
  - Regular security scanning (container images, dependencies)

### 9. Backup and Disaster Recovery

**Backup strategy:**

- **Data backups**:
  - Kafka topic backups (Confluent Replicator, MirrorMaker 2)
  - Persistent volume snapshots
  - Configuration backups (GitOps recommended)

- **Disaster recovery**:
  - Multi-region setup for critical workloads
  - Documented recovery procedures
  - Regular DR drills
  - RTO/RPO objectives defined

### 10. Licensing

**Confluent Platform licensing:**

- **Enterprise license** required for production use
- **Features requiring license**:
  - Control Center
  - Replicator
  - Schema Registry (some features)
  - RBAC

- **Contact**: Confluent sales team for enterprise licensing

---

## System Requirements

### Minimum Local Development Requirements

- **CPU**: 4 cores
- **RAM**: 8 GB available
- **Disk**: 20 GB free space
- **Network**: Stable internet connection (for pulling images and charts)

### Minimum Production Requirements

- **CPU**: 24+ cores total across cluster
- **RAM**: 96+ GB total across cluster
- **Disk**: 1+ TB total persistent storage
- **Network**: 10 Gbps internal networking, DDoS protection

---

## Verification Steps

### Pre-Deployment Checklist

Run these commands to verify all prerequisites are met:

```bash
# 1. Check Docker
docker --version
docker ps

# 2. Check Kubernetes cluster
kubectl version --client
kubectl cluster-info
kubectl get nodes

# 3. Check Helm
helm version

# 4. Check OpenSSL
openssl version

# 5. Check keytool (Java)
keytool -help
java -version

# 6. Check cluster resources (for local)
kubectl top nodes  # Requires metrics-server

# 7. Verify namespace access
kubectl create namespace test-prereq --dry-run=client -o yaml
kubectl delete namespace test-prereq --ignore-not-found=true

# 8. Check Helm repository access
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
helm search repo confluent-for-kubernetes
```

### Resource Verification (Local)

```bash
# Check if minikube has sufficient resources
minikube ssh "free -h"  # Check memory
minikube ssh "df -h"    # Check disk
minikube ssh "nproc"    # Check CPU cores
```

### Common Issues

**Issue**: `minikube` won't start
- **Solution**: Increase resources: `minikube delete && minikube start --cpus=4 --memory=8192`

**Issue**: `kubectl` can't connect to cluster
- **Solution**: Check context: `kubectl config current-context`
- **Fix**: `kubectl config use-context minikube`

**Issue**: `keytool` not found
- **Solution**: Install Java JDK and ensure it's in your PATH

**Issue**: Certificate generation fails
- **Solution**: Verify OpenSSL version is 1.1.1 or later

**Issue**: Helm chart installation fails
- **Solution**: Update Helm repos: `helm repo update`

---

## Quick Start Summary

**For local development, ensure these are running:**

```bash
# 1. Start Docker Desktop (GUI application)

# 2. Start minikube
minikube start --cpus=4 --memory=8192 --disk-size=20g

# 3. Verify everything
kubectl get nodes
helm version
openssl version
keytool -help

# 4. You're ready to deploy!
cd /path/to/CPDemoWithCFK
./scripts/deploy.sh
```

**For production deployment:**

1. Provision managed Kubernetes cluster
2. Set up certificate management (cert-manager + enterprise CA)
3. Configure persistent storage classes
4. Set up monitoring and logging infrastructure
5. Implement backup and disaster recovery
6. Obtain Confluent Platform license
7. Review and apply security hardening
8. Deploy with production-grade configurations

---

## Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/home/)
- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [Confluent for Kubernetes Documentation](https://docs.confluent.io/operator/current/overview.html)
- [Confluent Platform Requirements](https://docs.confluent.io/platform/current/installation/system-requirements.html)

---

**Last Updated**: April 15, 2026
**Status**: ✅ Complete
