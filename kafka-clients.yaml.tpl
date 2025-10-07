
---
apiVersion: v1
kind: Pod
metadata:
  name: ${KAFKA_CLUSTER}-producer1
  labels: 
    ## Clients are not labelled "strimzi.io/cluster: ..." 
    app: ${KAFKA_CLUSTER}-clients
spec:
  containers:
    - name: ${KAFKA_CLUSTER}-producer1
      image: $KAFKA_IMAGE
      command:
        - sh
        - -c
        - |
          ## PKI values must be inline strings if PEM format
          echo "Making /tmp/clients.properties file ..."
          tee /tmp/clients.properties <<EOH
          security.protocol=SSL
          ssl.keystore.type=PKCS12
          ssl.truststore.type=PKCS12
          ssl.truststore.location=/etc/kafka/secrets/cluster/ca.p12
          ssl.truststore.password=$(cat /etc/kafka/secrets/cluster/ca.password)
          ssl.keystore.location=/etc/kafka/secrets/clients/user.p12
          ssl.keystore.password=$(cat /etc/kafka/secrets/clients/user.password)
          EOH
          echo "Starting Producer ..."
          /opt/kafka/bin/kafka-console-producer.sh \
              --bootstrap-server ${KAFKA_CLUSTER}-kafka-external-bootstrap:$KAFKA_NODEPORT \
              --producer.config /tmp/clients.properties \
              --topic demo-topic
        
      volumeMounts:
        - name: cluster
          mountPath: /etc/kafka/secrets/cluster
          readOnly: true
        - name: clients
          mountPath: /etc/kafka/secrets/clients
          readOnly: true
  
  volumes:
    - name: cluster
      secret:
        secretName: ${KAFKA_CLUSTER}-cluster-ca-cert
    - name: clients
      secret:
        secretName: ${KAFKA_CLUSTER}-user

---
apiVersion: v1
kind: Pod
metadata:
  name: ${KAFKA_CLUSTER}-consumer1
  labels: 
    app: ${KAFKA_CLUSTER}-clients
spec:
  containers:
    - name: ${KAFKA_CLUSTER}-consumer1
      image: $KAFKA_IMAGE
      command:
        - sh
        - -c
        - |
          ## PKI values must be inline strings if PEM format
          echo "Making /tmp/clients.properties file ..."
          tee /tmp/clients.properties <<EOH
          security.protocol=SSL
          ssl.keystore.type=PKCS12
          ssl.truststore.type=PKCS12
          ssl.truststore.location=/etc/kafka/secrets/cluster/ca.p12
          ssl.truststore.password=$(cat /etc/kafka/secrets/cluster/ca.password)
          ssl.keystore.location=/etc/kafka/secrets/clients/user.p12
          ssl.keystore.password=$(cat /etc/kafka/secrets/clients/user.password)
          EOH
          echo "Starting Consumer ..."
          /opt/kafka/bin/kafka-console-consumer.sh \
            --bootstrap-server ${KAFKA_CLUSTER}-kafka-external-bootstrap:$KAFKA_NODEPORT \
            --consumer.config /tmp/clients.properties \
            --topic demo-topic \
            --from-beginning

      volumeMounts:
        - name: cluster
          mountPath: /etc/kafka/secrets/cluster
          readOnly: true
        - name: clients
          mountPath: /etc/kafka/secrets/clients
          readOnly: true
  
  volumes:
    - name: cluster
      secret:
        secretName: ${KAFKA_CLUSTER}-cluster-ca-cert
    - name: clients
      secret:
        secretName: ${KAFKA_CLUSTER}-user


