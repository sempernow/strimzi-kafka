Here's how to configure your external Kafka client to connect via NodePort with mTLS authentication using Strimzi:

## Producer Configuration (`producer.config`)

```ini
bootstrap.servers=<NODE_IP>:<NODE_PORT>
security.protocol=SSL
ssl.truststore.location=/path/to/truststore.p12
ssl.truststore.password=truststore-password
ssl.truststore.type=PKCS12
ssl.keystore.location=/path/to/keystore.p12
ssl.keystore.password=keystore-password
ssl.keystore.type=PKCS12
ssl.key.password=key-password
```

```ini
security.protocol=SSL
ssl.truststore.location=/tmp/ca.p12
ssl.truststore.password=<truststore_password>
ssl.keystore.location=/tmp/user.p12
ssl.keystore.password=<keystore_password>
```


## Extract PKI from Secrets of Kafka and KafkaUser 


```bash
cluster=k1
```

### PKCS #12

```bash
# Truststore (Cluster CA)
kubectl get secret ${cluster}-cluster-ca-cert -o jsonpath='{.data.ca\.p12}' |
    base64 -d > ca.p12
kubectl get secret ${cluster}-cluster-ca-cert -o jsonpath='{.data.ca\.password}' |
    base64 -d > ca.password

# Keystore (User CA)
kubectl get secret ${cluster}-user -o jsonpath='{.data.ca\.p12}' |
    base64 -d > ca.p12
kubectl get secret ${cluster}-user -o jsonpath='{.data.user\.p12}' |
    base64 -d > user.p12
kubectl get secret ${cluster}-user -o jsonpath='{.data.user\.password}' |
    base64 -d > user.password

# Note k-user has same ca.crt as k1-clients-ca-cert; the CA that signs clients' certs
diff <(k get secret k1-user -o  jsonpath='{.data.ca\.crt}')  \
     <(k get secret k1-clients-ca-cert -o  jsonpath='{.data.ca\.crt}')
```

### PEM

```bash
# Truststore (Cluster CA)
kubectl get secret ${cluster}-cluster-ca-cert -o jsonpath='{.data.ca\.crt}' |
    base64 -d > ca.crt

# Keystore (User CA)
kubectl get secret ${cluster}-user -o jsonpath='{.data.ca\.crt}' |
    base64 -d > ca.crt
kubectl get secret ${cluster}-user -o jsonpath='{.data.user\.crt}' |
    base64 -d > user.crt
kubectl get secret ${cluster}-user -o jsonpath='{.data.user\.key}' |
    base64 -d > user.key

```


## Key Steps to Set Up:

### 1. Extract Certificates from Strimzi Secrets
```bash
# Get the cluster CA certificate
kubectl get secret <cluster-name>-cluster-ca-cert -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt

# Get user certificates
kubectl get secret <user-name> -o jsonpath='{.data.user\.crt}' | base64 -d > user.crt
kubectl get secret <user-name> -o jsonpath='{.data.user\.key}' | base64 -d > user.key
```

### 2. Create Java Keystores/Truststores
```bash
# Create PKCS12 truststore from CA certificate
openssl pkcs12 -export -in ca.crt -out truststore.p12 -name ca -passout pass:truststore-password

# Create PKCS12 keystore from user certificate and key
openssl pkcs12 -export -in user.crt -inkey user.key -out keystore.p12 -name user -passout pass:keystore-password
```

### 3. Find NodePort Information
```bash
kubectl get svc <cluster-name>-kafka-external-bootstrap -o jsonpath='{.spec.ports[0].nodePort}'
```

## Alternative Configuration Using PEM Files

If you prefer to use PEM files directly:

```properties
bootstrap.servers=<NODE_IP>:<NODE_PORT>
security.protocol=SSL
ssl.ca.location=/path/to/ca.crt
ssl.certificate.location=/path/to/user.crt
ssl.key.location=/path/to/user.key
```

## Complete Example

Assuming:
- Node IP: `192.168.1.100`
- NodePort: `31000`
- Cluster name: `my-kafka`
- User name: `my-producer`

```properties
bootstrap.servers=192.168.1.100:31000
security.protocol=SSL
ssl.truststore.location=/opt/kafka/truststore.p12
ssl.truststore.password=changeit
ssl.truststore.type=PKCS12
ssl.keystore.location=/opt/kafka/keystore.p12
ssl.keystore.password=changeit
ssl.keystore.type=PKCS12
```

## Strimzi KafkaUser Example

Make sure you have a KafkaUser configured for mTLS:

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: my-producer
  labels:
    strimzi.io/cluster: my-kafka
spec:
  authentication:
    type: tls
```

This configuration will allow your external producer to securely connect to your Strimzi Kafka cluster via NodePort using mTLS authentication.