# Create ConfigMap with producer script
kubectl create configmap kafka-producer-script --from-file=producer.py --from-file=requirements.txt

# Create the deployment
kubectl apply -f kafka-producer-deploy.yaml

sleep 20

# Verify

# Check pod status
kubectl get pods -l app=kafka-producer

# View logs
kubectl logs -l app=kafka-producer -f

# Check if messages are appearing in MariaDB
kubectl exec -it deployment/mariadb -- mysql -u kafka_connect -p -e "
USE kafka_data;
SELECT * FROM kafka_user_events;
SELECT * FROM kafka_order_events;
"