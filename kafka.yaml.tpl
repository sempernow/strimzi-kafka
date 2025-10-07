---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: controller
  labels:
    strimzi.io/cluster: $KAFKA_CLUSTER
spec:
  replicas: 2
  roles:
    - controller
  storage:
    type: jbod
    volumes:
      - id: 0
        type: ephemeral
        kraftMetadata: shared
        # type: persistent-claim
        # size: 100Gi
        # kraftMetadata: shared
        # deleteClaim: false
---

apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: broker
  labels:
    strimzi.io/cluster: $KAFKA_CLUSTER
spec:
  replicas: 3
  roles:
    - broker
  storage:
    type: jbod
    volumes:
      - id: 0
        type: ephemeral
        kraftMetadata: shared
        # type: persistent-claim
        # size: 100Gi
        # kraftMetadata: shared
        # deleteClaim: false
---
apiVersion: kafka.strimzi.io/v1beta2
## Configuration : https://strimzi.io/docs/operators/latest/deploying#con-config-kafka-kraft-str
kind: Kafka
metadata:
  name: $KAFKA_CLUSTER
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    version: $KAFKA_VERSION
    # metadataVersion: 4.0-IV3
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
      - name: external
        port: 9094
        type: nodeport
        tls: true   # TLS encrypted traffic
        authentication:
          type: tls # AuthN by mTLS
        configuration:
          bootstrap:
            nodePort: $KAFKA_NODEPORT
          brokers:
          - broker: 0
            nodePort: 32000
          - broker: 1
            nodePort: 32001
          - broker: 2
            nodePort: 32002
    authorization:
      ## AuthZ by Kafka’s built-in SimpleAuthorizer
      type: simple
      ## This is an ACL-based authorization model
      ## enforced at the broker level.
      ## This is managed by the KafkaUser CR,
      ## by declarations of who can Read, Write, Describe, Create, etc. 
      ## on topics, groups, transactional IDs, cluster, etc.
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      default.replication.factor: 3
      min.insync.replicas: 2
  entityOperator:
    topicOperator: {}
    userOperator: {}

---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: ${KAFKA_CLUSTER}-user 
  labels:
    strimzi.io/cluster: ${KAFKA_CLUSTER}
spec:
  authentication:
    ## By this setting, this resource creates a Secret having same name 
    ## that contains all PKI required for AuthN by mTLS.
    type: tls # AuthN by mTLS
