# Q:

What resources must we create for a MariaDB to act as a sink of messages from topics of a Strimzi Kafka cluster?

# A:

To set up __MariaDB as a sink for messages from a Strimzi Kafka cluster__, 
you'll need to create several Kubernetes resources. Here's a complete breakdown:

## Required Resources

### 1. **KafkaConnect Cluster** (The runtime environment)
```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnect
metadata:
  name: mariadb-connect-cluster
  annotations:
    strimzi.io/use-connector-resources: "true"
spec:
  replicas: 2
  bootstrapServers: your-kafka-cluster-kafka-bootstrap:9092
  config:
    group.id: connect-cluster
    offset.storage.topic: connect-cluster-offsets
    config.storage.topic: connect-cluster-configs
    status.storage.topic: connect-cluster-status
    key.converter: org.apache.kafka.connect.json.JsonConverter
    value.converter: org.apache.kafka.connect.json.JsonConverter
    key.converter.schemas.enable: false
    value.converter.schemas.enable: false
  build:
    output: 
      type: docker
      image: your-registry/mariadb-connect-cluster:latest
    plugins:
      - name: kafka-connect-jdbc
        artifacts:
          - type: tgz
            url: https://repo1.maven.org/maven2/io/confluent/kafka-connect-jdbc/10.7.4/kafka-connect-jdbc-10.7.4.tar.gz
```

### 2. **MariaDB Connection Secret** (Database credentials)
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mariadb-credentials
type: Opaque
stringData:
  username: kafka_connect
  password: your-secure-password
  connection.url: jdbc:mysql://mariadb-service:3306/kafka_data
```

### 3. **KafkaConnector** (The actual sink job)
```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
  name: mariadb-sink-connector
  labels:
    strimzi.io/cluster: mariadb-connect-cluster
spec:
  class: io.confluent.connect.jdbc.JdbcSinkConnector
  tasksMax: 2
  config:
    # Connection configuration
    connection.url: "jdbc:mysql://mariadb-service:3306/kafka_data"
    connection.user: "${file:/opt/kafka/external-configuration/mariadb-credentials/username}"
    connection.password: "${file:/opt/kafka/external-configuration/mariadb-credentials/password}"
    
    # Topic and table mapping
    topics: "user-events,order-events"
    table.name.format: "kafka_${topic}"
    
    # Behavior configuration
    insert.mode: "upsert"
    pk.mode: "record_key"
    pk.fields: "id"
    
    # Auto-create tables if missing
    auto.create: "true"
    auto.evolve: "true"
    
    # Error handling
    errors.tolerance: "all"
    errors.deadletterqueue.topic.name: "mariadb-sink-errors"
    errors.log.enable: "true"
    
    # Maximum number of records per batch
    batch.size: 1000
    
    # Data mapping
    fields.whitelist: "id,name,email,amount,created_at"
    
    # For JSON payloads
    key.converter: "org.apache.kafka.connect.json.JsonConverter"
    value.converter: "org.apache.kafka.connect.json.JsonConverter"
    key.converter.schemas.enable: "false"
    value.converter.schemas.enable: "false"
```

### 4. **MariaDB Database Schema**

Create the database and user.

When using the __Kafka Connect JDBC Sink__ connector, 
the ___tables must exist before the connector starts___. 
The connector cannot operate without the target tables already being present.

```sql
-- Create database and user
CREATE DATABASE kafka_data;
CREATE USER 'kafka_connect'@'%' IDENTIFIED BY 'your-secure-password';
GRANT ALL PRIVILEGES ON kafka_data.* TO 'kafka_connect'@'%';
FLUSH PRIVILEGES;

-- Or let the connector auto-create tables, but for better control:
USE kafka_data;
CREATE TABLE kafka_user_events (
    id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255),
    email VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    _kafka_topic VARCHAR(255),
    _kafka_offset BIGINT,
    _kafka_timestamp TIMESTAMP
);

CREATE TABLE kafka_order_events (
    id VARCHAR(255) PRIMARY KEY,
    amount DECIMAL(10,2),
    user_id VARCHAR(255),
    status VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 5. **MariaDB Deployment** (If not already existing)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mariadb
spec:
  selector:
    matchLabels:
      app: mariadb
  template:
    metadata:
      labels:
        app: mariadb
    spec:
      containers:
      - name: mariadb
        image: mariadb:10.11
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mariadb-credentials
              key: root-password
        - name: MYSQL_DATABASE
          value: kafka_data
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: mariadb-credentials
              key: username
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mariadb-credentials
              key: password
        ports:
        - containerPort: 3306
---
apiVersion: v1
kind: Service
metadata:
  name: mariadb-service
spec:
  selector:
    app: mariadb
  ports:
  - port: 3306
    targetPort: 3306
```

## Deployment Order

1. **MariaDB Deployment** (if needed)
2. **Database Schema** setup
3. **KafkaConnect Cluster** with JDBC plugin
4. **MariaDB Connection Secret**
5. **KafkaConnector** resource

## Key Configuration Notes

- **JSON Converter**: Configured to handle JSON messages without schemas
- **Upsert Mode**: Will insert new records or update existing ones based on primary key
- **Auto-create**: The connector can create tables if they don't exist
- **Error Handling**: Configured to tolerate errors and send failed messages to a DLQ
- **Batch Processing**: Processes up to 1000 records at once for efficiency

## Message Format Example

Your Kafka messages should be in JSON format that maps to your MariaDB table structure:

```json
// Key (for determining primary key)
{"id": "user-123"}

// Value (for column data)
{"name": "John Doe", "email": "john@example.com", "created_at": "2023-10-01T12:00:00Z"}
```

This setup will automatically sink messages from your Kafka topics into corresponding MariaDB tables.


## Verify Setup

```bash
# Check if user was created
kubectl exec -it deployment/mariadb -- \
    mysql -u root -p -e "SELECT user, host FROM mysql.user WHERE user = 'kafka_connect';"

# Check if tables exist
kubectl exec -it deployment/mariadb -- \
    mysql -u kafka_connect -p -e "USE kafka_data; SHOW TABLES;"

# Check connector status
kubectl get kafkaconnector mariadb-sink-connector -o yaml
```

---

# SQL Issues

You're absolutely right to question this - my phrasing was misleading. 
Let me clarify the reality of table creation with Kafka Connect JDBC Sink.

## The Reality: Table Creation is **NOT Optional**

When using the Kafka Connect JDBC Sink connector, 
**the tables MUST exist before the connector starts**. 
The connector cannot operate without the target tables already being present.

### What "Auto-create" Actually Does

The `"auto.create": "true"` setting is often misunderstood. Here's what it really does:

```yaml
config:
  auto.create: "true"  # Attempts to create tables if missing
  auto.evolve: "true"  # Attempts to add new columns if needed
```

**But there are major limitations:**

1. **Only Works on First Run**: If tables don't exist when the connector starts, it will attempt to create them once.

2. **Very Basic Schema Inference**:
   - String fields become `VARCHAR(256)` 
   - Number fields become `DOUBLE`
   - Boolean fields become `TINYINT(1)`
   - No proper NULL constraints
   - No indexes beyond primary key
   - No foreign keys
   - Limited control over data types

3. **Often Fails in Production**:
   - Insufficient permissions for CREATE TABLE
   - Data type mismatches
   - Missing constraints
   - No proper indexes for performance

## The Correct Approach: Always Pre-create Tables

### Required SQL (Not Optional)
```sql
-- This is MANDATORY, not optional
CREATE DATABASE IF NOT EXISTS kafka_data;

USE kafka_data;

-- Table for user-events topic
CREATE TABLE IF NOT EXISTS kafka_user_events (
    id VARCHAR(255) NOT NULL PRIMARY KEY,
    name VARCHAR(500),
    email VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- Kafka metadata (optional but useful)
    _kafka_topic VARCHAR(255),
    _kafka_partition INT,
    _kafka_offset BIGINT,
    _kafka_timestamp TIMESTAMP,
    _processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table for order-events topic  
CREATE TABLE IF NOT EXISTS kafka_order_events (
    id VARCHAR(255) NOT NULL PRIMARY KEY,
    user_id VARCHAR(255),
    amount DECIMAL(15,2),
    currency VARCHAR(3) DEFAULT 'USD',
    status ENUM('pending', 'completed', 'cancelled'),
    items JSON, -- For complex nested data
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_created_at (created_at)
);

-- Grant permissions to the connector user
GRANT SELECT, INSERT, UPDATE ON kafka_data.* TO 'kafka_connect'@'%';
```

### Why Pre-creation is Essential

1. **Data Type Control**:
   ```sql
   -- Auto-create might make this VARCHAR(256)
   -- You want proper constraints:
   CREATE TABLE proper_table (
       id VARCHAR(255) NOT NULL PRIMARY KEY,
       email VARCHAR(255) NOT NULL UNIQUE,
       age TINYINT UNSIGNED,
       price DECIMAL(10,2) NOT NULL,
       metadata JSON,
       created_at DATETIME(6) NOT NULL  -- Microsecond precision
   );
   ```

2. **Performance Optimization**:
   ```sql
   -- Proper indexes that auto-create won't add
   CREATE INDEX idx_composite ON kafka_user_events (created_at, status);
   CREATE INDEX idx_email_domain ON kafka_user_events (SUBSTRING_INDEX(email, '@', -1));
   ```

3. **Data Integrity**:
   ```sql
   -- Constraints that auto-create won't add
   ALTER TABLE kafka_order_events 
   ADD CONSTRAINT fk_order_user 
   FOREIGN KEY (user_id) REFERENCES kafka_user_events(id);
   ```

## Complete Deployment Workflow

### 1. First: Database Setup (Mandatory)
```sql
-- 1. Create database and user
CREATE DATABASE kafka_data;
CREATE USER 'kafka_connect'@'%' IDENTIFIED BY 'secure-password';
GRANT ALL PRIVILEGES ON kafka_data.* TO 'kafka_connect'@'%';

-- 2. Create tables with proper schema
USE kafka_data;
-- [Add the CREATE TABLE statements from above]
```

### 2. Second: Kubernetes Resources
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mariadb-schema-setup
data:
  init.sql: |
    CREATE DATABASE IF NOT EXISTS kafka_data;
    USE kafka_data;
    CREATE TABLE IF NOT EXISTS kafka_user_events (
      id VARCHAR(255) NOT NULL PRIMARY KEY,
      name VARCHAR(500),
      email VARCHAR(255),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    -- ... more tables
```

### 3. Updated Connector Configuration
```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
  name: mariadb-sink-connector
spec:
  class: io.confluent.connect.jdbc.JdbcSinkConnector
  config:
    connection.url: "jdbc:mysql://mariadb-service:3306/kafka_data"
    connection.user: "${file:/opt/kafka/external-configuration/mariadb-credentials/username}"
    connection.password: "${file:/opt/kafka/external-configuration/mariadb-credentials/password}"
    
    topics: "user-events,order-events"
    table.name.format: "kafka_${topic}"
    
    # CRITICAL: These assume tables already exist
    insert.mode: "upsert"
    pk.mode: "record_key"
    pk.fields: "id"
    
    # Safety: Disable auto-create in production
    auto.create: "false"
    auto.evolve: "false"
    
    # Error if tables don't exist (fail fast)
    errors.tolerance: "none"
```

## When Auto-create Might Be Acceptable

Only in **development** environments where:
- Data loss is acceptable
- Performance doesn't matter
- Schema changes are frequent
- You're just testing the data flow

## Production Best Practice

**Always pre-create tables** with:
- Proper data types
- Appropriate indexes
- Constraints and validations
- Foreign key relationships (if needed)
- Comment documentation

The SQL schema definition is a **required component** of your infrastructure, not an optional extra. Treat it with the same importance as your Kubernetes manifests.

---

# Arvo Converter

**Avro converter** is used for **schema enforcement and efficient serialization** in Kafka. It's a fundamental tool for building reliable, evolvable data pipelines.

## What Avro Solves

### Without Avro (JSON problems):
```json
// Producer A sends:
{"id": "user-1", "name": "John", "email": "john@test.com"}

// Producer B sends:
{"id": "user-2", "name": "Jane", "email": "jane@test.com", "age": 30}

// Consumer breaks! Unexpected field 'age'
// No validation, no compatibility checking
```

### With Avro:
```java
// Schema defined and enforced
{
  "type": "record",
  "name": "User",
  "fields": [
    {"name": "id", "type": "string"},
    {"name": "name", "type": "string"},
    {"name": "email", "type": "string"}
  ]
}

// All messages MUST conform to this schema
// Automatic validation and compatibility checking
```

## How Avro Converter Works

### 1. **Schema Registry Integration**
Avro converter works with a **Schema Registry** (like Confluent Schema Registry):

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnect
metadata:
  name: my-connect-cluster
spec:
  config:
    # Avro configuration
    key.converter: io.confluent.connect.avro.AvroConverter
    key.converter.schema.registry.url: http://schema-registry:8081
    value.converter: io.confluent.connect.avro.AvroConverter
    value.converter.schema.registry.url: http://schema-registry:8081
```

### 2. **Message Format**
Instead of raw JSON, messages contain **schema ID + binary data**:

```
[Magic Byte][Schema ID][Avro Binary Data]
```

## Benefits for Your MariaDB Example

### 1. **Schema Evolution**
Your `kafka_user_events` table schema can evolve safely:

```avro
// Version 1: Initial schema
{
  "type": "record",
  "name": "UserEvent",
  "fields": [
    {"name": "id", "type": "string"},
    {"name": "name", "type": "string"},
    {"name": "email", "type": "string"}
  ]
}

// Version 2: Add new field (BACKWARD compatible)
{
  "type": "record", 
  "name": "UserEvent",
  "fields": [
    {"name": "id", "type": "string"},
    {"name": "name", "type": "string"},
    {"name": "email", "type": "string"},
    {"name": "phone", "type": ["null", "string"], "default": null}
  ]
}
```

### 2. **Data Validation**

```avro
// Schema for order-events
{
  "type": "record",
  "name": "OrderEvent", 
  "fields": [
    {"name": "id", "type": "string"},
    {"name": "user_id", "type": "string"},
    {"name": "amount", "type": "double"},
    {"name": "currency", "type": "string", "default": "USD"},
    {"name": "status", "type": {"type": "enum", "name": "OrderStatus", "symbols": ["pending", "completed", "cancelled"]}},
    {"name": "items", "type": {"type": "array", "items": {
      "type": "record",
      "name": "OrderItem",
      "fields": [
        {"name": "product_id", "type": "string"},
        {"name": "product_name", "type": "string"},
        {"name": "quantity", "type": "int"},
        {"name": "price", "type": "double"}
      ]
    }}}
  ]
}
```

**Invalid data is rejected automatically:**
- Wrong enum value (`"status": "shipped"` → rejected)
- Missing required field (`"amount"` missing → rejected)
- Wrong data type (`"amount": "high"` → rejected)

## Practical Example with Your Schema

### Avro Configuration
```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
  name: mariadb-sink-connector
spec:
  class: io.confluent.connect.jdbc.JdbcSinkConnector
  config:
    # Avro serialization
    key.converter: io.confluent.connect.avro.AvroConverter
    key.converter.schema.registry.url: http://schema-registry:8081
    value.converter: io.confluent.connect.avro.AvroConverter  
    value.converter.schema.registry.url: http://schema-registry:8081
    
    # JDBC configuration
    connection.url: "jdbc:mysql://mariadb-service:3306/kafka_data"
    topics: "user-events,order-events"
    table.name.format: "kafka_${topic}"
    pk.mode: "record_key"
    pk.fields: "id"
```

### Producer Code (Java Example)
```java
// User Event Schema
public class UserEvent extends SpecificRecordBase {
    private String id;
    private String name; 
    private String email;
    
    // Constructors, getters, setters
    // Avro schema definition
}

// Send message
UserEvent user = new UserEvent("user-123", "John Doe", "john@example.com");
ProducerRecord<GenericRecord, GenericRecord> record = 
    new ProducerRecord<>("user-events", user.getKeyAvroRecord(), user.getValueAvroRecord());
producer.send(record);
```

## When to Use Avro vs JSON

### Use Avro When:
- **✅ Production systems** needing reliability
- **✅ Evolving schemas** (adding/removing fields over time)
- **✅ Large volumes** (better performance than JSON)
- **✅ Multiple teams** (enforced contracts between services)
- **✅ Regulatory compliance** (data validation requirements)

### Use JSON When:
- **✅ Development/Prototyping** (faster iteration)
- **✅ Simple use cases** (no schema evolution needed)
- **✅ Human-readable** debugging needed
- **✅ Limited infrastructure** (no Schema Registry available)

## Complete Setup with Strimzi

### 1. Deploy Schema Registry
```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnect
metadata:
  name: avro-connect-cluster
spec:
  # ... other config ...
  config:
    key.converter: io.confluent.connect.avro.AvroConverter
    key.converter.schema.registry.url: http://schema-registry:8081
    value.converter: io.confluent.connect.avro.AvroConverter
    value.converter.schema.registry.url: http://schema-registry:8081
```

### 2. Benefits for MariaDB Sink
- **No data corruption** from malformed messages
- **Automatic schema validation** before hitting database
- **Schema evolution** as business requirements change
- **Compact binary format** (better performance than JSON)

## Summary

**Avro converter + Schema Registry** provides:
- 🛡️ **Data validation** and quality enforcement
- 🔄 **Schema evolution** with compatibility checking
- 📉 **Efficient serialization** (smaller than JSON)
- 🤝 **Contract enforcement** between producers/consumers
- 🚀 **Better performance** in high-throughput systems

For enterprise-grade data pipelines with MariaDB, 
Avro is strongly recommended over plain JSON for production workloads.

---

# Debezium : Source

**Debezium** and the **JDBC Sink Connector** solve fundamentally different problems - they're actually complementary rather than alternatives! Let me clarify:

## They Work in **Opposite Directions**

### JDBC Sink Connector: **Kafka → Database**
- Moves data **FROM Kafka topics TO** databases
- **Sink** connector - "sinks" data into databases
- Used in your MariaDB example

### Debezium: **Database → Kafka** 
- Moves data **FROM databases TO** Kafka topics  
- **Source** connector - "sources" data from databases
- Captures database change events

## Debezium's Unique Capabilities

### 1. **Change Data Capture (CDC)**
Debezium reads database **transaction logs** (binlog in MySQL/MariaDB, WAL in PostgreSQL) to capture:

```sql
-- When this happens in database:
INSERT INTO users VALUES ('user-123', 'John', 'john@email.com');
UPDATE users SET email = 'new@email.com' WHERE id = 'user-123';
DELETE FROM users WHERE id = 'user-123';
```

**Debezium produces to Kafka:**
```json
// Insert event
{
  "before": null,
  "after": {
    "id": "user-123", 
    "name": "John",
    "email": "john@email.com"
  },
  "op": "c",  // create
  "ts_ms": 1633456789000
}

// Update event  
{
  "before": {
    "id": "user-123",
    "name": "John",
    "email": "john@email.com"
  },
  "after": {
    "id": "user-123",
    "name": "John", 
    "email": "new@email.com"
  },
  "op": "u",  // update
  "ts_ms": 1633456790000
}

// Delete event
{
  "before": {
    "id": "user-123",
    "name": "John",
    "email": "new@email.com"
  },
  "after": null,
  "op": "d",  // delete
  "ts_ms": 1633456791000
}
```

### 2. **Real-time, Low-Impact Capture**
- **No application changes** needed - works at database level
- **Near real-time** - milliseconds latency
- **Low overhead** - reads existing transaction logs, doesn't query tables
- **Exactly-once** semantics

### 3. **Full History and Tombstones**
```json
// Debezium captures the entire change history
{
  "op": "d",
  "before": { /* full row state */ },
  "after": null,  // Tombstone for compaction
  "source": {
    "connector": "mysql",
    "snapshot": "false",
    "ts_ms": 1633456791000
  }
}
```

## Complete Comparison

| Feature | JDBC Sink Connector | Debezium Source Connector |
|---------|---------------------|---------------------------|
| **Direction** | Kafka → Database | Database → Kafka |
| **Use Case** | Sink processed data to DB | Capture DB changes to Kafka |
| **Data Flow** | Topics → Tables | Tables → Topics |
| **Real-time** | Near real-time | Real-time (log-based) |
| **Overhead** | Standard consumer | Minimal (reads existing logs) |
| **Captures** | Only new messages | Inserts, Updates, Deletes |
| **Schema** | Simple message mapping | Full before/after state |

## Practical Scenarios

### Scenario 1: Complete Data Pipeline (Using Both!)
```
Application → Kafka (processed data) → JDBC Sink → MariaDB
                                              ↓
Debezium ← MariaDB (change events) ← Kafka ← Other consumers
```

### Scenario 2: Debezium Configuration
```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector
metadata:
  name: debezium-mysql-source
spec:
  class: io.debezium.connector.mysql.MySqlConnector
  config:
    # Database connection
    database.hostname: mariadb-service
    database.port: 3306
    database.user: debezium
    database.password: ${file:/opt/kafka/external-configuration/db-credentials/password}
    database.server.id: 184054
    
    # What to capture
    database.include.list: kafka_data
    table.include.list: kafka_data.kafka_user_events,kafka_data.kafka_order_events
    
    # Output topics
    topic.prefix: debezium
    include.schema.changes: false
    
    # Snapshot behavior
    snapshot.mode: when_needed
```

### Scenario 3: JDBC Sink Configuration (Your Original Use Case)
```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaConnector  
metadata:
  name: mariadb-sink-connector
spec:
  class: io.confluent.connect.jdbc.JdbcSinkConnector
  config:
    # Sinking data TO database
    connection.url: jdbc:mysql://mariadb-service:3306/kafka_data
    topics: processed-user-events,processed-order-events
    insert.mode: upsert
    pk.mode: record_key
```

## When to Use Each

### Use JDBC Sink Connector When:
- ✅ You have processed data in Kafka that needs persistence
- ✅ Writing results from stream processing to databases
- ✅ Sinking analytics or aggregated data
- ✅ Your MariaDB use case - storing final processed events

### Use Debezium When:
- ✅ You need to capture database changes in real-time
- ✅ Building event-driven architectures from existing databases
- ✅ Database replication to other systems
- ✅ Audit trails and change tracking
- ✅ Migrating from monolith to microservices

## They Work Together!

A common pattern:
```bash
# 1. Debezium captures raw database changes
Debezium → Kafka topic: `debezium.kafka_data.kafka_user_events`

# 2. Stream processing cleans/enriches data
Kafka Streams/Flink → Kafka topic: `processed-user-events`

# 3. JDBC Sink writes final results back to DB
JDBC Sink → MariaDB table: `enriched_user_profiles`
```

## Summary

- **JDBC Sink Connector**: **Writes to databases** from Kafka
- **Debezium**: **Reads from databases** into Kafka

They're not competitors - they're partners in building complete, bidirectional data pipelines between Kafka and databases!

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
