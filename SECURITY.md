# Security Architecture - mTLS Certificate Design

## Overview

This deployment implements **proper mutual TLS (mTLS)** authentication where **client and server use DIFFERENT certificates**. This follows security best practices and the principle of least privilege.

## Certificate Architecture

### Certificate Authority (CA)

```
ca-cert.pem + ca-key.pem
└── Signs all component certificates
```

All certificates are signed by our self-signed CA, which establishes the trust chain.

### Component Certificates

#### 1. KRaft Controllers (JKS format)
- **Purpose**: Server authentication for KRaft metadata service
- **Certificate**: `kraftcontroller-cert.pem` / `kraftcontroller.keystore.jks`
- **Usage**: Both server and client (KRaft-to-KRaft communication)

#### 2. Kafka Brokers (JKS format)
- **Purpose**: Server authentication for Kafka service
- **Certificate**: `kafka-cert.pem` / `kafka.keystore.jks`
- **Usage**: Both server and client (broker-to-broker, broker-to-KRaft)

#### 3. Control Center Main (JKS format)
- **Purpose**: Server authentication for Control Center web UI
- **Certificate**: `controlcenter-cert.pem` / `controlcenter.keystore.jks`
- **Usage**: Server authentication on port 9021

## Embedded Services - Proper mTLS Separation

### Prometheus Communication

```
┌─────────────────────────────────────────────────────────┐
│                   Control Center Pod                    │
│                                                         │
│  ┌──────────────────────┐      ┌──────────────────┐   │
│  │   Prometheus         │◄────►│  Control Center  │   │
│  │   (Server)           │ mTLS │  (Client)        │   │
│  │                      │      │                  │   │
│  │ Server Cert:         │      │ Client Cert:     │   │
│  │ prometheus-cert.pem  │      │ prometheus-      │   │
│  │ prometheus-key.pem   │      │ client-cert.pem  │   │
│  │                      │      │ prometheus-      │   │
│  │ Port: 9090           │      │ client-key.pem   │   │
│  └──────────────────────┘      └──────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

**Prometheus Server Certificate:**
- **Files**: `prometheus-cert.pem`, `prometheus-key.pem`
- **Common Name**: `prometheus`
- **SANs**: prometheus, controlcenter, controlcenter.confluent.svc.cluster.local
- **EKU**: serverAuth, clientAuth
- **Secret**: `prometheus-tls`
- **Usage**: Prometheus authenticates itself to clients

**Prometheus Client Certificate (Control Center):**
- **Files**: `prometheus-client-cert.pem`, `prometheus-client-key.pem`
- **Common Name**: `controlcenter-prometheus-client`
- **SANs**: controlcenter, controlcenter.confluent.svc.cluster.local
- **EKU**: serverAuth, clientAuth
- **Secret**: `prometheus-client-tls`
- **Usage**: Control Center authenticates itself to Prometheus

### AlertManager Communication

```
┌─────────────────────────────────────────────────────────┐
│                   Control Center Pod                    │
│                                                         │
│  ┌──────────────────────┐      ┌──────────────────┐   │
│  │   AlertManager       │◄────►│  Control Center  │   │
│  │   (Server)           │ mTLS │  (Client)        │   │
│  │                      │      │                  │   │
│  │ Server Cert:         │      │ Client Cert:     │   │
│  │ alertmanager-        │      │ alertmanager-    │   │
│  │ cert.pem             │      │ client-cert.pem  │   │
│  │ alertmanager-        │      │ alertmanager-    │   │
│  │ key.pem              │      │ client-key.pem   │   │
│  │                      │      │                  │   │
│  │ Port: 9093           │      │                  │   │
│  └──────────────────────┘      └──────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

**AlertManager Server Certificate:**
- **Files**: `alertmanager-cert.pem`, `alertmanager-key.pem`
- **Common Name**: `alertmanager`
- **SANs**: alertmanager, controlcenter, controlcenter.confluent.svc.cluster.local
- **EKU**: serverAuth, clientAuth
- **Secret**: `alertmanager-tls`
- **Usage**: AlertManager authenticates itself to clients

**AlertManager Client Certificate (Control Center):**
- **Files**: `alertmanager-client-cert.pem`, `alertmanager-client-key.pem`
- **Common Name**: `controlcenter-alertmanager-client`
- **SANs**: controlcenter, controlcenter.confluent.svc.cluster.local
- **EKU**: serverAuth, clientAuth
- **Secret**: `alertmanager-client-tls`
- **Usage**: Control Center authenticates itself to AlertManager

## Why Separate Certificates?

### Security Benefits

1. **Principle of Least Privilege**
   - Each component has only the credentials it needs
   - Server certificate cannot be used to impersonate clients
   - Client certificate cannot be used to impersonate servers

2. **Certificate Revocation**
   - If a client certificate is compromised, only that client is affected
   - Server can continue operating with other clients
   - Easier to rotate individual certificates

3. **Audit Trail**
   - Can distinguish server vs. client actions in logs
   - Better tracking of who connected to whom
   - Clearer security boundaries

4. **Compliance**
   - Many security frameworks require separate client/server certs
   - Follows industry best practices (NIST, PCI-DSS)
   - Demonstrates proper separation of concerns

### What Would Be Wrong with Shared Certificates?

If we used the same certificate for both roles:

```
❌ BAD PRACTICE:
prometheus-tls (server) → prometheus-cert.pem
prometheus-client-tls (client) → prometheus-cert.pem  (SAME!)

Problems:
- If client cert is compromised, server is also compromised
- Cannot revoke client access without affecting server
- Violates principle of least privilege
- May fail strict TLS implementations
- Poor security posture
```

## Certificate File Summary

### Server Certificates (what each service presents)

| Service | Certificate Files | Secret Name | CN |
|---------|------------------|-------------|-----|
| KRaft | kraftcontroller-cert.pem, kraftcontroller-key.pem | kraftcontroller-tls | kraftcontroller |
| Kafka | kafka-cert.pem, kafka-key.pem | kafka-tls | kafka |
| Control Center | controlcenter-cert.pem, controlcenter-key.pem | controlcenter-tls | controlcenter |
| Prometheus | prometheus-cert.pem, prometheus-key.pem | prometheus-tls | prometheus |
| AlertManager | alertmanager-cert.pem, alertmanager-key.pem | alertmanager-tls | alertmanager |

### Client Certificates (what clients use to connect)

| Client | Connecting To | Certificate Files | Secret Name | CN |
|--------|--------------|------------------|-------------|-----|
| Control Center | Prometheus | prometheus-client-cert.pem, prometheus-client-key.pem | prometheus-client-tls | controlcenter-prometheus-client |
| Control Center | AlertManager | alertmanager-client-cert.pem, alertmanager-client-key.pem | alertmanager-client-tls | controlcenter-alertmanager-client |
| Control Center | Kafka | controlcenter-cert.pem, controlcenter-key.pem | controlcenter-tls | controlcenter |
| Kafka | KRaft | kafka-cert.pem, kafka-key.pem | kafka-tls | kafka |

## mTLS Handshake Flow

### Example: Control Center → Prometheus

1. **Connection Initiated**
   - Control Center connects to `https://controlcenter.confluent.svc.cluster.local:9090`

2. **Server Hello**
   - Prometheus presents its server certificate: `prometheus-cert.pem`
   - Signed by CA

3. **Client Verification**
   - Control Center verifies Prometheus certificate against `ca-cert.pem`
   - Checks: CN=prometheus, valid SANs, EKU includes serverAuth

4. **Client Hello**
   - Control Center presents its client certificate: `prometheus-client-cert.pem`
   - Signed by CA

5. **Server Verification**
   - Prometheus verifies client certificate against `ca-cert.pem`
   - Checks: CN=controlcenter-prometheus-client, valid signature, EKU includes clientAuth

6. **Handshake Complete**
   - Both parties authenticated
   - Encrypted channel established
   - Communication proceeds

## Extended Key Usage (EKU) Extensions

All certificates include both `serverAuth` and `clientAuth` EKU extensions:

```
X509v3 Extended Key Usage:
    TLS Web Server Authentication, TLS Web Client Authentication
```

This allows flexibility while still maintaining separate certificates. However, in production, you might want to restrict:
- Server certs: Only `serverAuth`
- Client certs: Only `clientAuth`

## Truststore Configuration

All components trust the same CA:

```
ca-cert.pem → Loaded into truststores of:
├── KRaft Controllers
├── Kafka Brokers
├── Control Center
├── Prometheus
└── AlertManager
```

This allows any component to verify any other component's certificate, as long as it's signed by our CA.

## Production Recommendations

For production deployments, consider:

1. **Use a proper CA** (not self-signed)
   - HashiCorp Vault
   - cert-manager with Let's Encrypt
   - Enterprise PKI

2. **Shorter certificate lifetimes**
   - Current: 365 days
   - Recommended: 90 days or less
   - Implement automated rotation

3. **Stricter EKU**
   - Server certs: Only `serverAuth`
   - Client certs: Only `clientAuth`

4. **Certificate pinning** (optional)
   - Pin specific certificates or public keys
   - Additional layer of security

5. **Monitoring**
   - Alert on certificate expiration
   - Monitor TLS handshake failures
   - Track certificate rotation

## Verification

To verify proper mTLS separation:

```bash
# Check server certificate
openssl x509 -in certs/prometheus-cert.pem -text -noout | grep -E "Subject:|CN="

# Check client certificate
openssl x509 -in certs/prometheus-client-cert.pem -text -noout | grep -E "Subject:|CN="

# They should have DIFFERENT Common Names
```

Expected output:
```
# Server cert
Subject: CN = prometheus, OU = TEST, O = CONFLUENT...

# Client cert  
Subject: CN = controlcenter-prometheus-client, OU = TEST, O = CONFLUENT...
```

## Summary

✅ **We implement proper mTLS**
- ✅ Separate server certificates for Prometheus and AlertManager
- ✅ Separate client certificates for Control Center
- ✅ All certificates signed by same CA
- ✅ All certificates include proper EKU extensions
- ✅ No certificate reuse between roles

This provides strong mutual authentication while following security best practices.
