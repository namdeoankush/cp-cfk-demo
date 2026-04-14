#!/bin/bash
set -e

echo "🔐 Generating certificates for Confluent Platform with KRaft and Control Center Next-Gen..."
echo ""

# Clean up old files
rm -f *.pem *.jks *.p12 *.jksPassword.txt *.csr *.conf *.srl

# Step 1: Generate CA (Certificate Authority)
echo "📜 Step 1: Creating Certificate Authority (CA)..."
openssl genrsa -out ca-key.pem 2048
openssl req -new -x509 -key ca-key.pem -out ca-cert.pem -days 365 \
    -subj "/CN=confluent-root-ca/OU=TEST/O=CONFLUENT/L=San Francisco/ST=Ca/C=US"
echo "✅ CA certificate created"
echo ""

# Function to create JKS keystore and truststore for Kafka components
create_jks_cert() {
    local component=$1
    local sans=$2

    echo "🔑 Creating certificate for: $component"

    # Generate private key
    openssl genrsa -out ${component}-key.pem 2048

    # Create certificate signing request with SANs
    openssl req -new \
        -key ${component}-key.pem \
        -out ${component}.csr \
        -subj "/CN=${component}/OU=TEST/O=CONFLUENT/L=PaloAlto/ST=Ca/C=US" \
        -addext "subjectAltName=${sans}"

    # Sign the certificate with CA
    openssl x509 -req \
        -in ${component}.csr \
        -CA ca-cert.pem \
        -CAkey ca-key.pem \
        -CAcreateserial \
        -out ${component}-cert.pem \
        -days 365 \
        -sha256 \
        -extfile <(printf "subjectAltName=${sans}")

    # Create PKCS12 file
    openssl pkcs12 -export \
        -in ${component}-cert.pem \
        -inkey ${component}-key.pem \
        -name ${component} \
        -out ${component}.p12 \
        -password pass:confluent

    # Convert to JKS keystore
    keytool -importkeystore \
        -srckeystore ${component}.p12 \
        -srcstoretype pkcs12 \
        -srcstorepass confluent \
        -destkeystore ${component}.keystore.jks \
        -deststoretype jks \
        -deststorepass confluent \
        -destkeypass confluent \
        -noprompt 2>/dev/null

    # Create truststore with CA
    keytool -import \
        -alias CARoot \
        -file ca-cert.pem \
        -keystore ${component}.truststore.jks \
        -storepass confluent \
        -noprompt 2>/dev/null

    # Create password file
    echo -n "jksPassword=confluent" > ${component}.jksPassword.txt

    # Cleanup intermediate files
    rm ${component}.csr ${component}.p12

    echo "✅ ${component} certificates created (JKS format)"
}

# Function to create PEM certificates for Control Center embedded services
create_pem_cert() {
    local component=$1
    local cn=$2
    local sans=$3

    echo "🔑 Creating certificate for: $component"

    # Generate private key
    openssl genrsa -out ${component}-key.pem 2048

    # Create config file with EKU extensions
    cat > ${component}.conf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = ${cn}
OU = TEST
O = CONFLUENT
L = PaloAlto
ST = Ca
C = US

[v3_req]
keyUsage = keyEncipherment, dataEncipherment, digitalSignature
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
${sans}
EOF

    # Create CSR
    openssl req -new -key ${component}-key.pem -out ${component}.csr -config ${component}.conf

    # Sign certificate with CA
    openssl x509 -req -in ${component}.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
        -out ${component}-cert.pem -days 365 -sha256 -extensions v3_req -extfile ${component}.conf

    # Cleanup
    rm ${component}.csr ${component}.conf

    echo "✅ ${component} certificate created (PEM format with EKU)"
}

echo "📦 Step 2: Generating KRaft Controller certificates..."
create_jks_cert "kraftcontroller" \
    "DNS:kraftcontroller,DNS:kraftcontroller.confluent.svc.cluster.local,DNS:*.kraftcontroller.confluent.svc.cluster.local,DNS:kraftcontroller-0.kraftcontroller.confluent.svc.cluster.local,DNS:kraftcontroller-1.kraftcontroller.confluent.svc.cluster.local,DNS:kraftcontroller-2.kraftcontroller.confluent.svc.cluster.local"
echo ""

echo "📦 Step 3: Generating Kafka Broker certificates..."
create_jks_cert "kafka" \
    "DNS:kafka,DNS:kafka.confluent.svc.cluster.local,DNS:*.kafka.confluent.svc.cluster.local,DNS:kafka-0.kafka.confluent.svc.cluster.local,DNS:kafka-1.kafka.confluent.svc.cluster.local,DNS:kafka-2.kafka.confluent.svc.cluster.local"
echo ""

echo "📦 Step 4: Generating Control Center certificates..."
create_jks_cert "controlcenter" \
    "DNS:controlcenter,DNS:controlcenter.confluent.svc.cluster.local,DNS:*.controlcenter.confluent.svc.cluster.local"
echo ""

echo "📦 Step 5: Generating Prometheus certificates (with EKU)..."
create_pem_cert "prometheus" "prometheus" \
    "DNS.1 = prometheus
DNS.2 = controlcenter
DNS.3 = controlcenter.confluent.svc.cluster.local
DNS.4 = localhost
IP.1 = 127.0.0.1"
echo ""

echo "📦 Step 6: Generating AlertManager certificates (with EKU)..."
create_pem_cert "alertmanager" "alertmanager" \
    "DNS.1 = alertmanager
DNS.2 = controlcenter
DNS.3 = controlcenter.confluent.svc.cluster.local
DNS.4 = localhost
IP.1 = 127.0.0.1"
echo ""

echo "📦 Step 7: Generating Prometheus CLIENT certificates (for Control Center)..."
create_pem_cert "prometheus-client" "controlcenter-prometheus-client" \
    "DNS.1 = controlcenter
DNS.2 = controlcenter.confluent.svc.cluster.local
DNS.3 = controlcenter-0.controlcenter.confluent.svc.cluster.local
DNS.4 = localhost
IP.1 = 127.0.0.1"
echo ""

echo "📦 Step 8: Generating AlertManager CLIENT certificates (for Control Center)..."
create_pem_cert "alertmanager-client" "controlcenter-alertmanager-client" \
    "DNS.1 = controlcenter
DNS.2 = controlcenter.confluent.svc.cluster.local
DNS.3 = controlcenter-0.controlcenter.confluent.svc.cluster.local
DNS.4 = localhost
IP.1 = 127.0.0.1"
echo ""

echo "🎉 All certificates generated successfully!"
echo ""
echo "📋 Summary of generated files:"
echo "   CA certificates:"
echo "   - ca-cert.pem, ca-key.pem"
echo ""
echo "   KRaft Controller (JKS):"
echo "   - kraftcontroller.keystore.jks, kraftcontroller.truststore.jks, kraftcontroller.jksPassword.txt"
echo ""
echo "   Kafka Broker (JKS):"
echo "   - kafka.keystore.jks, kafka.truststore.jks, kafka.jksPassword.txt"
echo ""
echo "   Control Center (JKS):"
echo "   - controlcenter.keystore.jks, controlcenter.truststore.jks, controlcenter.jksPassword.txt"
echo ""
echo "   Prometheus SERVER (PEM with EKU):"
echo "   - prometheus-cert.pem, prometheus-key.pem"
echo ""
echo "   AlertManager SERVER (PEM with EKU):"
echo "   - alertmanager-cert.pem, alertmanager-key.pem"
echo ""
echo "   Prometheus CLIENT (PEM with EKU - for Control Center):"
echo "   - prometheus-client-cert.pem, prometheus-client-key.pem"
echo ""
echo "   AlertManager CLIENT (PEM with EKU - for Control Center):"
echo "   - alertmanager-client-cert.pem, alertmanager-client-key.pem"
echo ""
echo "✅ Proper mTLS setup: Separate server and client certificates"
echo "Next step: Run ../scripts/deploy.sh to deploy to Kubernetes"
