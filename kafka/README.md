# Test Kafka Producer and Consumer Locally
This directory contains `producer.py` and `consumer.py` that run in local Kafka service. The `producer.py` will write the data to a local Kafka topic by the interval of 60 seconds. The `consumer.py` will consume the streaming data that has been stored within the topic and print it to the terminal.

## How to reproduce
Assume that all the prerequisites listed in the root directory have been installed in your local machine, you can follow these following instructions,
1. Open terminal, and go to the `/kafka` directory. Assume you already in the root directory of this repository, run this command:
```bash
cd kafka
```
3. Create new python environment and install the dependencies:
```bash
pip install -r requirements.txt
```
4. Create `.envrc` file to store environmental variables:
```
export API_KEY=<your-openweather-api-key>
export LAT=6.1944
export LON=106.8229
export KAFKA_TOPIC=<topic-name>
export KAFKA_BROKER=<local-kafka-server>
```
  This variable will not be pushed to github, as it is already listed in the `.gitignore`.
5. Allow direnv to access the `.envrc` file:
```bash
direnv allow
```
5. Start the Kafka service locally by going inside and your local Kafka installation directory and run the Zookeeper:
```bash
cd ~/kafka-3.7.1-src
bin/zookeeper-server-start.sh config/zookeeper.properties
```
   Then, open new terminal tab, go inside your local Kafka installation directory again, and start the Kafka:
```
cd ~/kafka-3.7.1-src
bin/kafka-server-start.sh config/server.properties
```
6. Open 2 more terminal tabs, go back to the `/kafka` directory and run the `producer.py` and `consumer.py` in each tab:
```bash
python producer.py
```
```bash
python consumer.py
```
7. If the code ran successfully, the records from the Open Weather API will be printed in the terminal output of the `consumer.py`
