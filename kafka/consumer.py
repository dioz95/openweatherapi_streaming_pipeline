from kafka import KafkaConsumer
import json
import os

# Define local kafka topic and broker
KAFKA_TOPIC = os.environ["KAFKA_TOPIC"]
KAFKA_BROKER = os.environ["KAFKA_BROKER"]

# Set up Kafka consumer
consumer = KafkaConsumer(
    KAFKA_TOPIC,
    bootstrap_servers=KAFKA_BROKER,
    value_deserializer=lambda m: json.loads(m.decode('utf-8'))
)

# Function to consume streaming weather data from the Kafka topic
def consume():
    for message in consumer:
        data = message.value
        print(f'Consumed: {data}')

if __name__ == "__main__":
    consume()