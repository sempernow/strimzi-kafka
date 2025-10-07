# [strimzi.io](https://strimzi.io "___") | ArtifactHUB : [`strimzi-kafka-operator`](https://artifacthub.io/packages/helm/strimzi-kafka-operator/strimzi-kafka-operator)

## TL;DR

```bash
bash make.strimzi-kafka.sh 

```

## [Deploying](https://strimzi.io/docs/operators/latest/deploying)

- __Cluster Operator__ : Manages Kafka clusters and related components:  
    - Kafka (including Entity Operator, Kafka Exporter, and Cruise Control)
    - [Kafka Connect](https://strimzi.io/docs/operators/latest/deploying#kafka-connect-str) : 
    an integration toolkit for streaming data between Kafka brokers and other systems using connector plugins. Kafka Connect provides a framework for integrating Kafka with an external data source or target, such as a database or messaging system, for import or export of data using connectors. 
        - __Connectors__ are plugins that provide the connection configuration needed.
    - Kafka MirrorMaker
    - Kafka Bridge
- __Entity Operator__
    - __Topic Operator__ : Creates, configures, and deletes Kafka topics
    - __User Operator__  : Manages Kafka users and their authentication credentials


### Node pools

A Kafka cluster consists of __nodes assigned KRaft roles__. These roles can be __brokers__, responsible for message streaming and storage, or __controllers__, which manage cluster state and metadata. While a node can perform both roles, separating them in production simplifies cluster management.

## Delete Terminating 

Pods stuck  in Terminating status due to finalizers

If Strimzi CRs already deleted

```bash
ns=sko
kubectl get pods -n $ns --field-selector=status.phase=Terminating -o name |
    xargs -I {} kubectl patch -n $ns {} -p '{"metadata":{"finalizers":[]}}' --type=merge

kubectl get pods -n $ns --field-selector=status.phase=Running -o name |
    xargs -I {} kubectl patch -n $ns {} -p '{"metadata":{"finalizers":[]}}' --type=merge
  
```

## [Client Access](https://strimzi.io/docs/operators/latest/deploying#deploy-client-access-str)

__Verify cluster deployment__, by [deploying producer and consumer clients](https://strimzi.io/docs/operators/latest/deploying#deploying-example-clients-str). 


```bash
img=quay.io/strimzi/kafka:0.48.0-kafka-4.1.0
cluster=cluster-1
topic=topic-1
```

Producer @ Terminal 1

```bash
kubectl run kafka-producer -ti --image=$img --rm=true --restart=Never -- \
    bin/kafka-console-producer.sh \
        --bootstrap-server ${cluster}-kafka-bootstrap:9092 \
        --topic $topic

```

Consumer @ Terminal 2

```bash
kubectl run kafka-consumer -ti --image=$img --rm=true --restart=Never -- \
    bin/kafka-console-consumer.sh \
        --bootstrap-server ${cluster}-kafka-bootstrap:9092 \
        --topic $topic \
        --from-beginning

```

Otherwise, [create listeners](https://strimzi.io/docs/operators/latest/deploying#configuration-points-listeners-str) that provide client access within or outside the Kubernetes cluster.

### [External Access via NodePorts](https://strimzi.io/docs/operators/latest/deploying#proc-accessing-kafka-using-nodeports-str)

```yaml
---
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  labels:
    app: cluster-1
  name: cluster-1
  namespace: strimzi
spec:
  kafka:
    # ...
    listeners:
      - name: external1
        port: 9094
        type: nodeport
        tls: true
        authentication:
          type: tls
        # ...
    # ...
```

Retrieve bootstrap address from `kafka.status`

```bash
kubectl get kafka $cluster -o=jsonpath='{.status.listeners[?(@.name=="external1")].bootstrapServers}{"\n"}'
```

Extract cluster CA (`ca.crt`)

```bash
kubectl get secret ${cluster}-cluster-ca-cert -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt

```

### [External Access via Ingress NGINX](https://strimzi.io/docs/operators/latest/deploying#proc-accessing-kafka-using-ingress-str)




## [Client AuthN](https://strimzi.io/docs/operators/latest/deploying#con-securing-kafka-authentication-str)

- [__mTLS__ authentication](https://strimzi.io/docs/operators/latest/deploying#mtls_authentication) (only on the listeners with TLS enabled encryption)
- __SCRAM-SHA-512__ authentication (password)
- __OAuth 2.0__ token-based authentication


### [Using mTLS](https://strimzi.io/docs/operators/latest/deploying#mtls_authentication) 

```yaml
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: cluster-1-user
  labels:
    strimzi.io/cluster: cluster-1
spec:
  authentication:
    type: tls
  # ...
```

Secret is generated automatically by a KafkaUser:

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: cluster-1-user
  labels:
    strimzi.io/kind: KafkaUser
    strimzi.io/cluster: cluster-1
type: Opaque
data:
  ca.crt: <public_key> # Public key of the clients CA used to sign this user certificate
  user.crt: <user_certificate> # Public key of the user
  user.key: <user_private_key> # Private key of the user
  user.p12: <store> # PKCS #12 store for user certificates and keys
  user.password: <password_for_store> # Protects the PKCS #12 store
```

Client (`producer`, `consumer`) `*.properties` for mTLS

#### PKCS #12 format

```ini
bootstrap.servers=<kafka_cluster_name>-kafka-bootstrap:9093 # (1)
security.protocol=SSL # (2)
ssl.truststore.location=/tmp/ca.p12 # (3)
ssl.truststore.password=<truststore_password> # (4)
ssl.keystore.location=/tmp/user.p12 # (5)
ssl.keystore.password=<keystore_password> # (6)
```
1. The bootstrap server address to connect to the Kafka cluster.
2. The security protocol option when using TLS for encryption.
3. The truststore location contains the public key certificate (`ca.p12`) for the Kafka cluster. A cluster CA certificate and password is generated by the Cluster Operator in the `<cluster_name>-cluster-ca-cert` secret when the Kafka cluster is created.
4. The password (`ca.password`) for accessing the truststore.
5. The keystore location contains the public key certificate (`user.p12`) for the Kafka user.
6. The password (`user.password`) for accessing the keystore.


#### PEM format

__UPDATE__ : Not even `cat` will work here. 
Must be "`\n`" delimited string. 

__This project is malware.__


```bash
tee /tmp/producer.properties <<EOH
security.protocol=SSL
ssl.keystore.type=PEM
ssl.truststore.type=PEM
ssl.truststore.certificates="$(cat /etc/kafka/secrets/ca.crt)"
ssl.keystore.certificate.chain="$(cat /etc/kafka/secrets/user.crt)"
ssl.keystore.key="$(cat /etc/kafka/secrets/user.key)"
EOH
```
- PEM must be inline string containing your client's certificate and any intermediate certificates. Each certificate must be a single line with "`\n`" to represent newlines.

How to extract those PKI parameters from their Secret source:

```bash
cluster=cluster-1
user=${cluster}-user

kubectl get secret ${cluster}-cluster-ca-cert -o jsonpath='{.data.ca\.crt}' |
    base64 -d > ca.crt

kubectl get secret $user -o jsonpath='{.data.user\.crt}' |
    base64 -d > user.crt

kubectl get secret $user -o jsonpath='{.data.user\.key}' |
    base64 -d > user.key

```
### [mTLS AuthN](https://strimzi.io/docs/operators/latest/deploying#certificates-and-secrets-formats-str) using __PEM__ *or* __PKCS #12__

1. Configure Kafka (cluster) for mTLS
2. Create KafkaUser that provides client credentials for mTLS

#### Client Configuration

Choose a format that is suitable for the client application.

__PKCS #12 is supported by Java__, so you can _add the values of the certificates directly to your Java client configuration_. With PEM files, you __must add the certificates directly to the client configuration in single-line format__. 

If using __PEM__ format

- __Truststore__
    - `ca.crt` from the `<cluster_name>-cluster-ca-cert` secret, 
      which is the CA certificate for the cluster.
- __Keystore__
    - `user.crt` from the `<kafka_user_name>` secret, 
      which is the public certificate of the user.
    - `user.key` from the `<kafka_user_name>` secret, 
       which is the private key of the user.


If using __PKCS #12__ format

- __Truststore__
    - `ca.p12` from the `<cluster_name>-cluster-ca-cert` secret, 
       which is the CA certificate for the cluster.
    - `ca.password` from the `<cluster_name>-cluster-ca-cert` secret, 
      which is the password to access the public cluster CA certificate.
- __Keystore__
    - `user.p12` from the `<kafka_user_name>` secret, 
      which is the public key certificate of the user.
    - `user.password` from the `<kafka_user_name>` secret, 
      which is the password to access the public key certificate of the Kafka user.


### [Cluster CA Secrets](https://strimzi.io/docs/operators/latest/deploying#cluster_ca_secrets)

Cluster CA secrets are managed by the __Cluster Operator__ in a Kafka cluster.

Only the `<cluster_name>-cluster-ca-cert` secret is required by clients. All other cluster secrets are accessed by Strimzi components. You can enforce this using Kubernetes role-based access controls, if necessary.

#### Secret : `<cluster_name>-cluster-ca`

- `ca.key` 
    The current private key for the cluster CA.
- `ca.p12`  
    PKCS #12 __store for storing certificates and keys__.
- `ca.password`  
    Password for protecting the PKCS #12 store.
- `ca.crt`  
    The current certificate for the cluster CA.  
    __This is required by clients__.

### [Clients CA Secrets](https://strimzi.io/docs/operators/latest/deploying#clients_ca_secrets)

Clients CA secrets are managed by the __Cluster Operator__ in a Kafka cluster.

The certificates in `<cluster_name>-clients-ca-cert` are those which the Kafka brokers trust.

The `<cluster_name>-clients-ca` secret is used to sign the certificates of client applications. This secret must be accessible to the Strimzi components and for administrative access if you are intending to issue application certificates without using the User Operator. You can enforce this using Kubernetes role-based access controls, if necessary.

#### Secret : `<cluster_name>-clients-ca`

- `ca.key` 
    The current private key for the clients CA.
- `ca.p12`  
    PKCS #12 __store for storing certificates and keys__.
- `ca.password`  
    Password for protecting the PKCS #12 store.
- `ca.crt`  
    The current certificate for the clients CA.  

### [User Secrets](https://strimzi.io/docs/operators/latest/deploying#user_secrets_generated_by_the_user_operator)

User secrets are managed by the User Operator.

When a user is created using the User Operator, a secret is generated using the name of the user.

#### Secret : `<user-name>`

- `user.p12`  
    PKCS #12 store for storing certificates and keys.
- `user.password`  
    Password for protecting the PKCS #12 store.
- `user.crt`  
    Certificate for the user, signed by the clients CA
- `user.key`  
    Private key for the user

## Configuring Clients to trust Cluster CA

- [Internal Clients](https://strimzi.io/docs/operators/latest/deploying#configuring-internal-clients-to-trust-cluster-ca-str)

- [External Clients](https://strimzi.io/docs/operators/latest/deploying#configuring-external-clients-to-trust-cluster-ca-str)


## [Client AuthZ](https://strimzi.io/docs/operators/latest/deploying#con-securing-kafka-authorization-str)

- __Simple__ authorization
- __OAuth 2.0__ authorization (if you are using OAuth 2.0 token based authentication)
- Open Policy Agent (__OPA__) authorization
- __Custom__ authorization

### Kafka Bridge 

The Kafka Bridge provides __a RESTful interface__ that allows HTTP-based clients to interact with a Kafka cluster. 

## [Deploy Strimzi using Helm](https://strimzi.io/docs/operators/latest/deploying#deploying-cluster-operator-helm-chart-str)

helm install strimzi-cluster-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator
helm install strimzi-cluster-operator --set replicas=2 --version 0.35.0 oci://quay.io/strimzi-helm/strimzi-kafka-operator




---

# 2025-10-01

## Q:

Regarding a Strimzi kafka already installed with a kafka cluster already created with internal tls enabled, running on a kubeadm K8s cluster, configured for NodePort (TLS passthrough), how to configure and demo messaging between external clients (producer and consumer)?

## A:

Here’s a step-by-step way to get **external clients talking to your Strimzi Kafka cluster** 
when you’ve already deployed it with:

* **kubeadm-based K8s cluster**
* **TLS enabled (internal)**
* **External access via NodePort (TLS passthrough)**

---

## 1. Understand the setup

With **NodePort + TLS passthrough**, the Strimzi Kafka operator doesn’t terminate TLS at the cluster edge.
Instead:

* External clients must connect using the **broker’s advertised addresses** (`host:nodeport`).
* Clients need the **cluster’s CA certificate** to verify the broker identity.
* Authentication depends on whether you’ve enabled **TLS client auth** or **SASL** (you said internal TLS enabled → at least CA trust is required).

---

## 2. Check Kafka listener config

Look at your `Kafka` custom resource (CR):

```yaml
---
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: my-cluster
spec:
  kafka:
    replicas: 3
    listeners:
      - name: external
        port: 9094
        type: nodeport
        tls: true
        configuration:
          bootstrap:
            nodePort: 31090   # static for bootstrap
          brokers:
          - broker: 0
            nodePort: 31091   # static per-broker
          - broker: 1
            nodePort: 31092
          - broker: 2
            nodePort: 31093

```

Strimzi will create:

* A `ClusterIP` for internal pods.
* A `NodePort` service per broker (`my-cluster-kafka-0`, etc.).
* A `my-cluster-kafka-bootstrap` service for convenience.

---

## 3. Get external addresses

Run:

```bash
kubectl get svc -n kafka
```

Example output:

```
my-cluster-kafka-bootstrap   NodePort   10.96.123.45   <none>   9094:31090/TCP
my-cluster-kafka-0           NodePort   10.96.234.56   <none>   9094:31091/TCP
my-cluster-kafka-1           NodePort   10.96.234.57   <none>   9094:31092/TCP
```

External address = `<NodeIP>:<NodePort>`
For demo: `192.168.11.21:31090` (bootstrap).

---

## 4. Export the cluster CA

Strimzi stores the cluster CA in a secret:

```bash
kubectl get secret my-cluster-cluster-ca-cert -n kafka -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
```

This `ca.crt` must be given to clients.

---

## 5. External producer/consumer demo

You can use either:

* **Kafka CLI tools** from the Strimzi Kafka image (`bin/kafka-console-producer.sh`, `bin/kafka-console-consumer.sh`)
* Or **Confluent client binaries**.

### Producer

```bash
./bin/kafka-console-producer.sh \
    --broker-list 192.168.11.21:31090 \
    --topic demo-topic \
    --producer-property security.protocol=SSL \
    --producer-property ssl.truststore.location=ca.truststore.jks \
    --producer-property ssl.truststore.password=changeit
```

*(if you prefer PEM, use `ssl.truststore.type=PEM` and point to `ca.crt`)*

Type some messages, press enter.

### Consumer

```bash
./bin/kafka-console-consumer.sh \
  --bootstrap-server 192.168.11.21:31090 \
  --topic demo-topic \
  --from-beginning \
  --consumer-property security.protocol=SSL \
  --consumer-property ssl.truststore.location=ca.truststore.jks \
  --consumer-property ssl.truststore.password=changeit
```

You should see the messages typed in producer’s console.

---

## 6. If using client TLS auth

If Strimzi is configured with `authentication: tls`, you’ll also need to generate a client cert:

```bash
kubectl get secret my-user -n kafka -o jsonpath='{.data.user\.crt}' | base64 -d > user.crt
kubectl get secret my-user -n kafka -o jsonpath='{.data.user\.key}' | base64 -d > user.key
```

Then set:

```properties
security.protocol=SSL
ssl.truststore=ca.crt
ssl.keystore=user.p12
ssl.keystore.password=changeit
```

---

## 7. Quick sanity test (without Kafka CLI)

You can at least test TLS connectivity:

```bash
openssl s_client -connect 192.168.11.21:31090 -CAfile ca.crt
```

If it verifies and shows Kafka’s cert → NodePort passthrough is working.

---

✅ That’s all you need for a working external producer/consumer demo:

* NodeIP + NodePort
* CA cert (always)
* Client certs (if TLS client auth enabled)

---


## Q: 

No KafkaUser ???

## A:  

Great question 👌 — and this is where Strimzi’s design sometimes confuses folks.

---

## 🔹 KafkaUser in Strimzi

The `KafkaUser` CRD is **Strimzi’s way of managing authentication and ACLs** declaratively.

* When you create a `KafkaUser`, Strimzi:

  * Generates TLS credentials or SASL credentials (depending on your config).
  * Stores them in a `Secret`.
  * Optionally applies ACLs on the Kafka cluster (if `authorization` is enabled).

Example (TLS user):

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: my-client
  labels:
    strimzi.io/cluster: my-cluster
spec:
  authentication:
    type: tls
```

This creates a secret `my-client` with `user.crt` and `user.key` that you mount in your client pod or container.

---

## 🔹 When you *don’t* need KafkaUser

* If your cluster is configured for **TLS only for encryption**, and **authentication is disabled** (i.e. `authentication: none` on the listener).
* If you are okay with **anonymous clients** (not typical for production).

In that case:

* You only need the **cluster CA cert** to trust the brokers (`ca.crt`).
* No per-user certificates or SASL creds required.

---

## 🔹 When you *do* need KafkaUser

* If you configured `authentication: tls` on the external listener:

  * Each external client needs a unique TLS cert/key pair (comes from a `KafkaUser`).
* If you configured `authentication: scram-sha-512`:

  * Each client needs username/password (also comes from a `KafkaUser`).
* If you enabled **authorization** (RBAC/ACLs), then `KafkaUser` is also how you declare who can produce/consume on which topics.

---

## 🔹 Typical demo setups

* **Quick demo / POC**:

  * External listener with `tls: true`, `authentication: none`
  * Only `ca.crt` is required → clients can produce/consume.
* **Production-like demo**:

  * Create `KafkaUser` resources → mount certs/keys in clients.
  * Explicit ACLs → demo restricted access.

---

✅ So to answer directly:

* **No, a KafkaUser resource is not strictly required** if you are only encrypting with TLS.
* **Yes, it is typical** in real deployments where you want proper authentication and access control.

---

Would you like me to give you **two demo flows** side by side:

1. “Anonymous TLS only” (simplest).
2. “TLS client auth with KafkaUser” (more production realistic)?


<!-- 

… ⋮ ︙ • ● – — ™ ® © ± ° ¹ ² ³ ¼ ½ ¾ ÷ × ₽ € ¥ £ ¢ ¤ ♻ ⚐ ⚑ ✪ ❤  \ufe0f
☢ ☣ ☠ ¦ ¶ § † ‡ ß µ Ø ƒ Δ ☡ ☈ ☧ ☩ ✚ ☨ ☦ ☓ ♰ ♱ ✖  ☘  웃 𝐀𝐏𝐏 🡸 🡺 ➔
ℹ️ ⚠️ ✅ ⌛ 🚀 🚧 🛠️ 🔧 🔍 🧪 👈 ⚡ ❌ 💡 🔒 📊 📈 🧩 📦 🥇 ✨️ 🔚

# Markdown Cheatsheet

[Markdown Cheatsheet](https://github.com/adam-p/markdown-here/wiki/Markdown-Cheatsheet "Wiki @ GitHub")

# README HyperLink

README ([MD](__PATH__/README.md)|[HTML](__PATH__/README.html)) 

# Bookmark

- Target
<a name="foo"></a>

- Reference
[Foo](#foo)

-->
