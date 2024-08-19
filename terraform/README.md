# Deployment with Terraform
In this project, Terraform is used to deploy the whole infrastructure used to enable the streaming data pipeline. The complete deployed infrastructure can be seen in this following diagram,

<p align="center"><img src="https://github.com/dioz95/openweatherapi_streaming_pipeline/blob/main/assets/flow_diagram.png" width="600" height="500" /></p>
<p align="center"><strong>Fig 1.</strong>Infrastructure Diagram</p>

The working data pipeline is built on top of these main AWS instances:
1. **AWS Managed Streaming for Kafka (MSK)**. AWS MSK is used to store the streaming data from Open Weather API. This MSK service is created with `kafka.t3.small` instance type and 3 bootstrap servers:

```tf
resource "aws_msk_cluster" "kafka" {
  cluster_name           = var.global_prefix
  kafka_version          = "2.8.1"
  number_of_broker_nodes = length(data.aws_availability_zones.available.names)
  broker_node_group_info {
    instance_type = "kafka.t3.small" # default value
    storage_info {
      ebs_storage_info {
        volume_size = 1000
      }
    }
    client_subnets = [aws_subnet.private_subnet[0].id,
      aws_subnet.private_subnet[1].id,
    aws_subnet.private_subnet[2].id]
    security_groups = [aws_security_group.kafka.id]
  }
  encryption_info {
    encryption_in_transit {
      client_broker = "PLAINTEXT"
    }
    encryption_at_rest_kms_key_arn = aws_kms_key.kafka_kms_key.arn
  }
  configuration_info {
    arn      = aws_msk_configuration.kafka_config.arn
    revision = aws_msk_configuration.kafka_config.latest_revision
  }
  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }
  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.kafka_log_group.name
      }
    }
  }
}
```

2. **AWS Elastic Compute Cloud (EC2)**. AWS EC2 instance is used as bastion host to let the user interact with the Kafka service (via ssh) in the MSK since the MSK is located inside a private subnet to ensure the security aspect of the infrastructure. The bastion host created with `t2.micro` instance type and linux operating system. The `bastion.tftpl` is used as a template file to install required packages to run the producer and consumer code.

```tf
resource "aws_instance" "bastion_host" {
  depends_on             = [aws_msk_cluster.kafka]
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.private_key.key_name
  subnet_id              = aws_subnet.bastion_host_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_host.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name
  user_data = templatefile("bastion.tftpl", {
    bootstrap_server_1 = split(",", aws_msk_cluster.kafka.bootstrap_brokers)[0]
    bootstrap_server_2 = split(",", aws_msk_cluster.kafka.bootstrap_brokers)[1]
    bootstrap_server_3 = split(",", aws_msk_cluster.kafka.bootstrap_brokers)[2]
    api_key            = var.api_key
    lat                = var.lat
    lon                = var.lon
    kafka_topic        = var.kafka_topic
    s3_bucket          = var.s3_bucket
  })
  root_block_device {
    volume_type = "gp2"
    volume_size = 100
  }
  tags = {
    Name = "bastion-host"
  }

}
```

3. **AWS Simple Storage Service (S3)**. AWS S3 is used as a storage to write the consumed data from the Kafka topic located inside the MSK cluster. The data will be written continuously while the consumer code is running as a single json file inside the bucket, specifically inside the `data/` directory. Moreover, output from the Athena (will be explained later) query also stored in the same bucket inside the `output/` directory.

```tf
resource "aws_s3_bucket" "weather_bucket" {
  bucket = var.s3_bucket

  tags = {
    Name        = "Weather bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_object" "data" {
  bucket = aws_s3_bucket.weather_bucket.id
  key    = "data/"
}

resource "aws_s3_object" "output" {
  bucket = aws_s3_bucket.weather_bucket.id
  key    = "output/"
}
```

4. **AWS Glue**. AWS Glue is a serverless ETL service from AWS that is used to create the database schema for the data stored in the S3 bucket, so the data can be queried from the `weather_table_007` table in the `weather_db` database.

```tf
resource "aws_glue_catalog_database" "weather_athena_db" {
  name = "weather_db"
}

resource "aws_glue_catalog_table" "weather_table" {
  database_name = aws_glue_catalog_database.weather_athena_db.name
  name          = "weather_table_007"
  description   = "table containing the data from OpenWeather API stored in S3"

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL = "TRUE"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.weather_bucket.bucket}/data/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.IgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "s3-stream"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"

      parameters = {
        "serialization.format"  = 1
        "ignore.malformed.json" = "TRUE"
        "dots.in.keys"          = "FALSE"
        "case.insensitive"      = "TRUE"
        "mapping"               = "TRUE"
      }
    }

    columns {
      name = "coord"
      type = "struct<lon:double,lat:double>"
    }

    columns {
      name = "weather"
      type = "array<struct<id:int,main:string,description:string,icon:string>>"
    }

    columns {
      name = "base"
      type = "string"
    }

    columns {
      name = "main"
      type = "struct<temp:double,feels_like:double,temp_min:double,temp_max:double,pressure:int,humidity:int,sea_level:int,grnd_level:int>"
    }

    columns {
      name = "visibility"
      type = "int"
    }

    columns {
      name = "wind"
      type = "struct<speed:double,deg:int,gust:double>"
    }

    columns {
      name = "rain"
      type = "struct<1h:double>"
    }

    columns {
      name = "clouds"
      type = "struct<all:int>"
    }

    columns {
      name = "dt"
      type = "int"
    }

    columns {
      name = "sys"
      type = "struct<type:int,id:int,country:string,sunrise:int,sunset:int>"
    }

    columns {
      name = "timezone"
      type = "int"
    }

    columns {
      name = "id"
      type = "int"
    }

    columns {
      name = "name"
      type = "string"
    }

    columns {
      name = "cod"
      type = "int"
    }
  }
}
```

5. **AWS Athena**. AWS Athena is a interactive query service that is used to to query the data from AWS Glue instance. To use Athena service, a working group with specific name must be defined in the terraform file:

```tf
resource "aws_athena_workgroup" "athena_wg" {
  name = "athena"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.weather_bucket.bucket}/output/"

    }
  }
}
```

## How to reproduce
Assume that all the prerequisites listed in the root directory have been installed in your local machine, you can follow these following instructions,

1. Open terminal, and go to the `/terraform` directory. Assume you already in the root directory of this repository, run this command:

```bash
cd terraform
```

2. Create `.envrc` file to store environmental variables:

```bash
export AWS_ACCESS_KEY_ID=<your-aws-access-key-idy>
export AWS_SECRET_ACCESS_KEY=<your-aws-secret-access-key>
export TF_VAR_api_key=<your-openweather-api-key>
```

3. Validate the terraform files:

```bash
terraform validate
```

4. Check the infrastructure that will be deployed:

```bash
terraform plan
```

5. Deploy the infrastructure:

```bash
terraform apply -auto-approve
```

## Documentation of a working system
After running `terraform apply` and the infrastructure is successfully deployed, the working system can be tested in these following steps:
1. Go to Athena service and set the `Workgroup` to `athena` on the top right of the screen,

<p align="center"><img src="https://github.com/dioz95/openweatherapi_streaming_pipeline/blob/main/assets/set_athena_wg.png" /></p>
<p align="center"><strong>Fig 2.</strong>Set Athena workgroup</p>

2. Try some query, e.g. to retrieve all the data in the table,

<p align="center"><img src="https://github.com/dioz95/openweatherapi_streaming_pipeline/blob/main/assets/query1.png" /></p>
<p align="center"><strong>Fig 3.</strong>Query to retrieve all the data in the table</p>

<p align="center"><img src="https://github.com/dioz95/openweatherapi_streaming_pipeline/blob/main/assets/query1_result.png" /></p>
<p align="center"><strong>Fig 4.</strong>Query result</p>

3. Or, to retrieve the average temperature by month,

<p align="center"><img src="https://github.com/dioz95/openweatherapi_streaming_pipeline/blob/main/assets/query2.png" /></p>
<p align="center"><strong>Fig 5.</strong>Query to retrieve the average temperature by month</p>

<p align="center"><img src="https://github.com/dioz95/openweatherapi_streaming_pipeline/blob/main/assets/query2_result.png" /></p>
<p align="center"><strong>Fig 6.</strong>Query result</p>

4. To see the data stored in the S3 bucket, go to `weather-data-bucket-007` in the S3 and go inside the `data/` directory,

<p align="center"><img src="https://github.com/dioz95/openweatherapi_streaming_pipeline/blob/main/assets/s3_data.png" /></p>
<p align="center"><strong>Fig 7.</strong>Data from the API stored in the S3</p>

5. To see the query history, go to the  `weather-data-bucket-007` in the S3 and go inside the `output/` directory,

<p align="center"><img src="https://github.com/dioz95/openweatherapi_streaming_pipeline/blob/main/assets/s3_output.png" /></p>
<p align="center"><strong>Fig 8.</strong>Output from the Athena query</p>
