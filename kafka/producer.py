import requests
import os
import json
from kafka import KafkaProducer
import time

# Define Open Weather API key
API_KEY = os.environ["API_KEY"]

# Define latitude and longitude of Jakarta, Indonesia
LAT = os.environ["LAT"]
LON = os.environ["LON"]

# Define local kafka topic and broker
KAFKA_TOPIC = os.environ["KAFKA_TOPIC"]
KAFKA_BROKER = os.environ["KAFKA_BROKER"]

# Set up Kafka producer
producer = KafkaProducer(
    bootstrap_servers=KAFKA_BROKER,
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

# Function to fetch weather data and publish to Kafka
def fetch_and_publish():
    url = f'https://api.openweathermap.org/data/2.5/weather?lat={LAT}&lon={LON}&appid={API_KEY}'
    response = requests.get(url)
    data = response.json()
    producer.send(KAFKA_TOPIC, value=data)
    print(f"Published: {data}")

if __name__ == "__main__":
    while True:
        fetch_and_publish()
        time.sleep(60)