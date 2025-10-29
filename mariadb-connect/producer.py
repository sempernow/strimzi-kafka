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

