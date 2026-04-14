# Certificate Architecture - Visual Guide

## Quick Reference: Who Uses What Certificate?

### Server Certificates (What Services Present)

```
┌──────────────────┬─────────────────────────┬──────────────────────┐
│ Service          │ Server Certificate      │ Common Name (CN)     │
├──────────────────┼─────────────────────────┼──────────────────────┤
│ Prometheus       │ prometheus-cert.pem     │ prometheus           │
│ AlertManager     │ alertmanager-cert.pem   │ alertmanager         │
│ Control Center   │ controlcenter-cert.pem  │ controlcenter        │
│ Kafka Broker     │ kafka-cert.pem          │ kafka                │
│ KRaft Controller │ kraftcontroller-cert.pem│ kraftcontroller      │
└──────────────────┴─────────────────────────┴──────────────────────┘
```

### Client Certificates (What Clients Use to Connect)

```
┌────────────────────┬──────────────────────────────┬─────────────────────────────────┐
│ Client             │ Client Certificate           │ Common Name (CN)                │
├────────────────────┼──────────────────────────────┼─────────────────────────────────┤
│ Control Center →   │ prometheus-client-cert.pem   │ controlcenter-prometheus-client │
│   Prometheus       │ prometheus-client-key.pem    │                                 │
├────────────────────┼──────────────────────────────┼─────────────────────────────────┤
│ Control Center →   │ alertmanager-client-cert.pem │ controlcenter-alertmanager-     │
│   AlertManager     │ alertmanager-client-key.pem  │ client                          │
└────────────────────┴──────────────────────────────┴─────────────────────────────────┘
```

## mTLS Flow Diagram

### Control Center ↔ Prometheus Communication

```
┌───────────────────────────────────────────────────────────────────┐
│                      Control Center Pod                           │
│                                                                   │
│  ┌─────────────────────┐                 ┌──────────────────┐   │
│  │   Prometheus        │                 │ Control Center   │   │
│  │   (Server)          │                 │ (Client)         │   │
│  │   Port: 9090        │◄───────────────►│                  │   │
│  │                     │    mTLS         │                  │   │
│  │ PRESENTS:           │    Handshake    │ PRESENTS:        │   │
│  │ ┌─────────────────┐ │                 │ ┌──────────────┐ │   │
│  │ │ Server Cert:    │ │                 │ │ Client Cert: │ │   │
│  │ │ prometheus-     │ │                 │ │ prometheus-  │ │   │
│  │ │ cert.pem        │ │  Step 1: →      │ │ client-      │ │   │
│  │ │                 │ │  Server Hello   │ │ cert.pem     │ │   │
│  │ │ CN=prometheus   │ │                 │ │              │ │   │
│  │ └─────────────────┘ │  Step 2: ←      │ │ CN=          │ │   │
│  │                     │  Client Verify  │ │ controlcenter│ │   │
│  │ VERIFIES:           │                 │ │ -prometheus- │ │   │
│  │ ┌─────────────────┐ │  Step 3: ←      │ │ client       │ │   │
│  │ │ Client Cert     │ │  Client Hello   │ └──────────────┘ │   │
│  │ │ Against CA      │ │                 │                  │   │
│  │ └─────────────────┘ │  Step 4: →      │ VERIFIES:        │   │
│  │                     │  Server Verify  │ ┌──────────────┐ │   │
│  │                     │                 │ │ Server Cert  │ │   │
│  │                     │  Step 5: ✓      │ │ Against CA   │ │   │
│  │                     │  Encrypted      │ └──────────────┘ │   │
│  │                     │  Channel        │                  │   │
│  └─────────────────────┘                 └──────────────────┘   │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

### Key Points:

1. **Prometheus** uses `prometheus-cert.pem` (Server Certificate)
2. **Control Center** uses `prometheus-client-cert.pem` (Client Certificate)
3. **Different certificates** for different roles
4. **Both** signed by same CA → mutual trust

## Certificate Generation Flow

```
┌──────────────────────────────────────────────────────────────┐
│  generate-certs.sh                                           │
│                                                              │
│  Step 1: Generate CA                                        │
│  ┌──────────────────────────────────────┐                  │
│  │ ca-cert.pem + ca-key.pem             │                  │
│  │ (Root Certificate Authority)         │                  │
│  └──────────────────────────────────────┘                  │
│                    │                                         │
│                    │ Signs all certificates                  │
│                    ▼                                         │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Step 2-6: Generate Server Certificates                │ │
│  │                                                        │ │
│  │  ├─► kraftcontroller-cert.pem (JKS)                   │ │
│  │  ├─► kafka-cert.pem (JKS)                             │ │
│  │  ├─► controlcenter-cert.pem (JKS)                     │ │
│  │  ├─► prometheus-cert.pem (PEM + EKU) ◄─┐             │ │
│  │  └─► alertmanager-cert.pem (PEM + EKU) │             │ │
│  └────────────────────────────────────────┬─┘             │ │
│                                            │               │ │
│  ┌────────────────────────────────────────┼──────────────┐ │
│  │ Step 7-8: Generate Client Certificates │ NEW!         │ │
│  │                                         │              │ │
│  │  ├─► prometheus-client-cert.pem (PEM + EKU)          │ │
│  │  │    CN=controlcenter-prometheus-client              │ │
│  │  │    For: Control Center → Prometheus                │ │
│  │  │                                                     │ │
│  │  └─► alertmanager-client-cert.pem (PEM + EKU)        │ │
│  │       CN=controlcenter-alertmanager-client            │ │
│  │       For: Control Center → AlertManager              │ │
│  └───────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

## Complete Certificate Matrix

### Embedded Prometheus mTLS

| Direction | Who | Certificate | Private Key | CN |
|-----------|-----|-------------|-------------|-----|
| **Server** | Prometheus | prometheus-cert.pem | prometheus-key.pem | prometheus |
| **Client** | Control Center | prometheus-client-cert.pem | prometheus-client-key.pem | controlcenter-prometheus-client |
| **Trust** | Both | ca-cert.pem | - | - |

### Embedded AlertManager mTLS

| Direction | Who | Certificate | Private Key | CN |
|-----------|-----|-------------|-------------|-----|
| **Server** | AlertManager | alertmanager-cert.pem | alertmanager-key.pem | alertmanager |
| **Client** | Control Center | alertmanager-client-cert.pem | alertmanager-client-key.pem | controlcenter-alertmanager-client |
| **Trust** | Both | ca-cert.pem | - | - |

### Control Center ↔ Kafka mTLS

| Direction | Who | Certificate | Private Key | CN |
|-----------|-----|-------------|-------------|-----|
| **Server** | Kafka Broker | kafka-cert.pem | kafka-key.pem | kafka |
| **Client** | Control Center | controlcenter-cert.pem | controlcenter-key.pem | controlcenter |
| **Trust** | Both | ca-cert.pem | - | - |

## Kubernetes Secrets Mapping

```
prometheus-tls secret:
  ├─ fullchain.pem → prometheus-cert.pem (SERVER)
  ├─ privkey.pem → prometheus-key.pem
  └─ cacerts.pem → ca-cert.pem

prometheus-client-tls secret:
  ├─ fullchain.pem → prometheus-client-cert.pem (CLIENT) ◄── Different!
  ├─ privkey.pem → prometheus-client-key.pem
  └─ cacerts.pem → ca-cert.pem

alertmanager-tls secret:
  ├─ fullchain.pem → alertmanager-cert.pem (SERVER)
  ├─ privkey.pem → alertmanager-key.pem
  └─ cacerts.pem → ca-cert.pem

alertmanager-client-tls secret:
  ├─ fullchain.pem → alertmanager-client-cert.pem (CLIENT) ◄── Different!
  ├─ privkey.pem → alertmanager-client-key.pem
  └─ cacerts.pem → ca-cert.pem
```

## Verification Commands

### 1. Verify Server Certificate

```bash
cd ~/Handson/CFK/certs
openssl x509 -in prometheus-cert.pem -text -noout | grep "Subject:"
```
Expected: `Subject: CN = prometheus, OU = TEST...`

### 2. Verify Client Certificate

```bash
openssl x509 -in prometheus-client-cert.pem -text -noout | grep "Subject:"
```
Expected: `Subject: CN = controlcenter-prometheus-client, OU = TEST...`

### 3. Verify They Are Different

```bash
diff <(openssl x509 -in prometheus-cert.pem -noout -modulus) \
     <(openssl x509 -in prometheus-client-cert.pem -noout -modulus)
```
Expected: **Different** (non-zero exit code)

### 4. Verify Both Signed by Same CA

```bash
openssl verify -CAfile ca-cert.pem prometheus-cert.pem
openssl verify -CAfile ca-cert.pem prometheus-client-cert.pem
```
Expected: Both show `OK`

### 5. Verify EKU Extensions

```bash
openssl x509 -in prometheus-cert.pem -text -noout | grep -A 2 "Extended Key Usage"
```
Expected:
```
X509v3 Extended Key Usage:
    TLS Web Server Authentication, TLS Web Client Authentication
```

## Summary

✅ **Proper mTLS Implementation:**

1. **Separate Certificates**: Server and client use DIFFERENT certificates
2. **Common Trust**: All certificates signed by same CA
3. **Proper EKU**: Both serverAuth and clientAuth enabled
4. **Security**: Follows principle of least privilege
5. **Flexibility**: Can revoke client without affecting server

❌ **What We Avoid:**

1. ❌ Reusing server certificate as client certificate
2. ❌ Sharing private keys between roles
3. ❌ Missing EKU extensions
4. ❌ Using same CN for server and client

---

**For detailed security architecture**, see [SECURITY.md](SECURITY.md)  
**For deployment instructions**, see [README.md](README.md)
