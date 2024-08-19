# Streaming Weather Data Pipeline
This repository contains an effort to create a streaming data pipeline using AWS Managed Streaming for Apache Kafka (MSK) and Terraform. Current weather data from [Open Weather API](https://openweathermap.org/current) is used as a streaming data source to be written continuously to a Kafka topic. The end goal of this project is to make the data from the API query-able in the AWS Athena. 

This repository has 3 major directories that you can visit in the following order:
- `/kafka`: Demonstrate Kafka producer and consumer deployed in local environment.
- `/terraform`: Demonstrate a full end-to-end data pipeline that is built using AWS services, provisioned by Terraform.
- `/.github/workflows`: Demonstrate CI/CD pipeline using Github Actions.

The `/assets` directory contains a documented screenshot of a working system.

Detailed documentation of the code is written separately in each directory.

## Pre-requisites
This project is built and tested on top of this following dependencies:
- `python 3.10.5` --> the producer and consumer code is written using python 3.10.5
- `terraform 1.9.2` --> terraform 1.9.2 is used in `/terraform` to deploy the infrastructure
- `kafka 3.7.1` (local) and `kafka 3.4.0` (EC2) --> kafka 3.7.1 is installed in local computer to run the code in `/kafka` and kafka 3.4.0 is installed in the bastion host (EC2) to communicate with the brokers served by MSK service.
- `kafka-python 2.0.2` (pip) --> kafka--python 2.0.2 acts as SDK to work with Kafka using python programming language.
- `requests 2.32.3` (pip) --> request 2.32.3 is used to fetch the data from Open Weather API.
- `direnv 2.34.0` -->  direnv 2.34.0 is used as a shell extension that can load and unload environment variables depending on the current directory.
