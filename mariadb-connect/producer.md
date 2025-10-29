# Producer

Here's a complete deployment for a Python client that produces messages for your MariaDB-sinked topics:

## 1. Python Producer Application

### producer.py
```python
import json
import time
import random
from datetime import datetime, timezone
from kafka import KafkaProducer
from kafka.errors import KafkaError

class MariaDBEventProducer:
    def __init__(self, bootstrap_servers):
        # Configure JSON serializer
        self.producer = KafkaProducer(
            bootstrap_servers=bootstrap_servers,
            key_serializer=lambda k: json.dumps(k).encode('utf-8'),
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            acks='all',  # Ensure messages are persisted
            retries=3
        )
        
        # Topic names matching your MariaDB tables
        self.user_events_topic = "user-events"
        self.order_events_topic = "order-events"
    
    def produce_user_event(self, user_id, name, email):
        """Produce a user event that maps to kafka_user_events table"""
        
        # Key - used as primary key in MariaDB
        key = {
            "id": user_id
        }
        
        # Value - maps to table columns
        value = {
            "name": name,
            "email": email,
            "created_at": datetime.now(timezone.utc).isoformat()
        }
        
        try:
            future = self.producer.send(
                self.user_events_topic, 
                key=key, 
                value=value
            )
            
            # Wait for confirmation
            record_metadata = future.get(timeout=10)
            
            print(f"✅ User event produced: user_id={user_id}, "
                  f"topic={record_metadata.topic}, "
                  f"partition={record_metadata.partition}, "
                  f"offset={record_metadata.offset}")
                  
            return True
                  
        except KafkaError as e:
            print(f"❌ Failed to produce user event: {e}")
            return False
    
    def produce_order_event(self, order_id, user_id, amount, status="pending", items=None):
        """Produce an order event that maps to kafka_order_events table"""
        
        if items is None:
            items = []
        
        # Key - used as primary key in MariaDB
        key = {
            "id": order_id
        }
        
        # Value - maps to table columns
        value = {
            "user_id": user_id,
            "amount": float(amount),
            "currency": "USD",
            "status": status,
            "items": items,
            "created_at": datetime.now(timezone.utc).isoformat()
        }
        
        try:
            future = self.producer.send(
                self.order_events_topic, 
                key=key, 
                value=value
            )
            
            record_metadata = future.get(timeout=10)
            
            print(f"✅ Order event produced: order_id={order_id}, "
                  f"amount=${amount}, status={status}, "
                  f"topic={record_metadata.topic}")
                  
            return True
                  
        except KafkaError as e:
            print(f"❌ Failed to produce order event: {e}")
            return False
    
    def generate_sample_data(self):
        """Generate sample data for testing"""
        
        # Sample user events
        users = [
            ("user-001", "Alice Johnson", "alice@example.com"),
            ("user-002", "Bob Smith", "bob@example.com"),
            ("user-003", "Carol Davis", "carol@example.com"),
            ("user-004", "David Wilson", "david@example.com")
        ]
        
        # Sample order events
        orders = [
            ("order-1001", "user-001", 149.99, "completed", [
                {"product_id": "prod-001", "product_name": "Wireless Headphones", "quantity": 1, "price": 149.99}
            ]),
            ("order-1002", "user-002", 87.50, "pending", [
                {"product_id": "prod-002", "product_name": "Phone Case", "quantity": 2, "price": 15.00},
                {"product_id": "prod-003", "product_name": "Screen Protector", "quantity": 1, "price": 12.50},
                {"product_id": "prod-004", "product_name": "Charging Cable", "quantity": 1, "price": 45.00}
            ]),
            ("order-1003", "user-001", 29.99, "completed", [
                {"product_id": "prod-005", "product_name": "USB-C Adapter", "quantity": 1, "price": 29.99}
            ])
        ]
        
        print("🚀 Starting to produce sample events...")
        
        # Produce user events
        for user_id, name, email in users:
            self.produce_user_event(user_id, name, email)
            time.sleep(1)  # Small delay between messages
        
        # Produce order events  
        for order_id, user_id, amount, status, items in orders:
            self.produce_order_event(order_id, user_id, amount, status, items)
            time.sleep(1)
        
        print("✅ Sample data production completed!")
    
    def close(self):
        """Close the producer connection"""
        self.producer.flush()
        self.producer.close()
        print("🔌 Producer closed")

if __name__ == "__main__":
    # Bootstrap servers from environment variable
    import os
    bootstrap_servers = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'my-kafka-cluster-kafka-bootstrap:9092')
    
    producer = MariaDBEventProducer(bootstrap_servers)
    
    try:
        # Generate sample data
        producer.generate_sample_data()
        
        # Keep running for continuous production (optional)
        # print("🔄 Starting continuous production...")
        # while True:
        #     producer.produce_random_event()
        #     time.sleep(5)
            
    except KeyboardInterrupt:
        print("⏹️ Stopping producer...")
    finally:
        producer.close()
```

### requirements.txt
```txt
kafka-python==2.0.2
```

## 2. Kubernetes Deployment

### kafka-producer-deployment.yaml
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-producer-script
data:
  producer.py: |
    # [Insert the entire producer.py content here]
    # For brevity in this example, we'll mount it as a file
  requirements.txt: |
    kafka-python==2.0.2
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: producer-config
data:
  KAFKA_BOOTSTRAP_SERVERS: "my-kafka-cluster-kafka-bootstrap:9092"
  USER_EVENTS_TOPIC: "user-events"
  ORDER_EVENTS_TOPIC: "order-events"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-producer
  labels:
    app: kafka-producer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-producer
  template:
    metadata:
      labels:
        app: kafka-producer
    spec:
      containers:
      - name: producer
        image: python:3.9-slim
        command: ["/bin/sh", "-c"]
        args:
          - |
            pip install -r /app/requirements.txt &&
            python /app/producer.py
        env:
        - name: KAFKA_BOOTSTRAP_SERVERS
          valueFrom:
            configMapKeyRef:
              name: producer-config
              key: KAFKA_BOOTSTRAP_SERVERS
        - name: USER_EVENTS_TOPIC
          valueFrom:
            configMapKeyRef:
              name: producer-config
              key: USER_EVENTS_TOPIC
        - name: ORDER_EVENTS_TOPIC
          valueFrom:
            configMapKeyRef:
              name: producer-config
              key: ORDER_EVENTS_TOPIC
        volumeMounts:
        - name: producer-scripts
          mountPath: /app
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: producer-scripts
        configMap:
          name: kafka-producer-script
---
# Optional: Service for health checks or management
apiVersion: v1
kind: Service
metadata:
  name: kafka-producer-service
spec:
  selector:
    app: kafka-producer
  ports:
  - port: 8000
    targetPort: 8000
```

## 3. Alternative: CronJob for Scheduled Production

### kafka-producer-cronjob.yaml
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: kafka-producer-cron
spec:
  schedule: "*/5 * * * *"  # Run every 5 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: producer
            image: python:3.9-slim
            command: ["/bin/sh", "-c"]
            args:
              - |
                pip install kafka-python==2.0.2 &&
                python /app/producer.py
            env:
            - name: KAFKA_BOOTSTRAP_SERVERS
              value: "my-kafka-cluster-kafka-bootstrap:9092"
            volumeMounts:
            - name: producer-scripts
              mountPath: /app
          volumes:
          - name: producer-scripts
            configMap:
              name: kafka-producer-script
          restartPolicy: OnFailure
```

## 4. Enhanced Producer with Health Checks

### producer-with-healthcheck.py (additional)
```python
import http.server
import threading
from http import HTTPStatus

class HealthHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(HTTPStatus.OK)
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(HTTPStatus.NOT_FOUND)
            self.end_headers()

def start_health_server():
    server = http.server.HTTPServer(('0.0.0.0', 8000), HealthHandler)
    print("🩺 Health check server running on port 8000")
    server.serve_forever()

# Start health server in background thread
health_thread = threading.Thread(target=start_health_server, daemon=True)
health_thread.start()
```

## 5. Deployment Steps

### Step 1: Create the ConfigMap and Deployment
```bash
# Create ConfigMap with producer script
kubectl create configmap kafka-producer-script --from-file=producer.py --from-file=requirements.txt

# Create the deployment
kubectl apply -f kafka-producer-deployment.yaml
```

### Step 2: Verify Deployment
```bash
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
```

## 6. Expected Output

When running, you should see:
```
🚀 Starting to produce sample events...
✅ User event produced: user_id=user-001, topic=user-events, partition=0, offset=15
✅ User event produced: user_id=user-002, topic=user-events, partition=0, offset=16
✅ Order event produced: order_id=order-1001, amount=$149.99, status=completed, topic=order-events
✅ Sample data production completed!
🔌 Producer closed
```

## 7. Verification in MariaDB

After running, check your MariaDB tables:
```sql
SELECT * FROM kafka_user_events;
-- Should show: user-001, user-002, user-003, user-004

SELECT id, user_id, amount, status FROM kafka_order_events;
-- Should show the sample orders with correct amounts and statuses
```

This Python client will produce messages that perfectly match your MariaDB table schema and will be automatically sunk into the database by your Kafka Connect JDBC Sink connector!


---

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
