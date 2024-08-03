################################################################################
# Cluster
################################################################################
resource "aws_kms_key" "kafka_kms_key" {
  description = "Key for Apache Kafka"
}

resource "aws_cloudwatch_log_group" "kafka_log_group" {
  name = "kafka_broker_logs"
}

resource "aws_msk_configuration" "kafka_config" {
  kafka_versions    = ["2.8.1"] # the recomended one at https://docs.aws.amazon.com/msk/latest/developerguide/supported-kafka-versions.html
  name              = "${var.global_prefix}-config"
  server_properties = <<EOF
auto.create.topics.enable = true
delete.topic.enable = true
EOF
}

resource "aws_msk_cluster" "kafka" {
  cluster_name           = var.global_prefix
  kafka_version          = "2.8.1"
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
    arn      = aws_msk_configuration.kafka_config.arn
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
        enabled   = true
        log_group = aws_cloudwatch_log_group.kafka_log_group.name
      }
    }
  }
}

################################################################################
# General
################################################################################

resource "aws_vpc" "default" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
}

resource "aws_eip" "default" {
  depends_on = [aws_internet_gateway.default]
  domain     = "vpc"
}

resource "aws_route" "default" {
  route_table_id         = aws_vpc.default.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.default.id
}

resource "aws_route_table_association" "private_subnet_association" {
  count          = length(data.aws_availability_zones.available.names)
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  route_table_id = aws_route_table.private_route_table.id
}

################################################################################
# Subnets
################################################################################

resource "aws_subnet" "private_subnet" {
  count                   = length(var.private_cidr_blocks)
  vpc_id                  = aws_vpc.default.id
  cidr_block              = element(var.private_cidr_blocks, count.index)
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[count.index]
}

resource "aws_subnet" "bastion_host_subnet" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = var.cidr_blocks_bastion_host[0]
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]
}

################################################################################
# Security groups
################################################################################

resource "aws_security_group" "kafka" {
  name   = "${var.global_prefix}-kafka"
  vpc_id = aws_vpc.default.id
  ingress {
    from_port   = 0
    to_port     = 9092
    protocol    = "TCP"
    cidr_blocks = var.private_cidr_blocks
  }
  ingress {
    from_port   = 0
    to_port     = 9092
    protocol    = "TCP"
    cidr_blocks = var.cidr_blocks_bastion_host
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "bastion_host" {
  name   = "${var.global_prefix}-bastion-host"
  vpc_id = aws_vpc.default.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "private_key" {
  key_name   = var.global_prefix
  public_key = tls_private_key.private_key.public_key_openssh
}

resource "local_file" "private_key" {
  content  = tls_private_key.private_key.private_key_pem
  filename = "cert.pem"
}

resource "null_resource" "private_key_permissions" {
  depends_on = [local_file.private_key]
  provisioner "local-exec" {
    command     = "chmod 600 cert.pem"
    interpreter = ["bash", "-c"]
    on_failure  = continue
  }
}

################################################################################
# IAM
################################################################################
resource "aws_iam_role" "ec2_role" {
  name               = "${var.global_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "ec2_role_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

################################################################################
# Client Machine (EC2)
################################################################################

resource "aws_instance" "bastion_host" {
  depends_on             = [aws_msk_cluster.kafka]
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.private_key.key_name
  subnet_id              = aws_subnet.bastion_host_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_host.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name
  user_data = templatefile("bastion.tftpl", {
    bootstrap_server_1 = split(",", aws_msk_cluster.kafka.bootstrap_brokers)[0]
    bootstrap_server_2 = split(",", aws_msk_cluster.kafka.bootstrap_brokers)[1]
    bootstrap_server_3 = split(",", aws_msk_cluster.kafka.bootstrap_brokers)[2]
    api_key            = var.api_key
    lat                = var.lat
    lon                = var.lon
    kafka_topic        = var.kafka_topic
    s3_bucket          = var.s3_bucket
  })
  root_block_device {
    volume_type = "gp2"
    volume_size = 100
  }
  tags = {
    Name = "bastion-host"
  }

}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "${var.global_prefix}-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

################################################################################
# S3 Bucket
################################################################################

resource "aws_s3_bucket" "weather_bucket" {
  bucket = var.s3_bucket

  tags = {
    Name        = "Weather bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_object" "data" {
  bucket = aws_s3_bucket.weather_bucket.id
  key    = "data/"
}

resource "aws_s3_object" "output" {
  bucket = aws_s3_bucket.weather_bucket.id
  key    = "output/"
}

################################################################################
# Glue
################################################################################

resource "aws_glue_catalog_database" "weather_athena_db" {
  name = "weather_db"
}

resource "aws_glue_catalog_table" "weather_table" {
  database_name = aws_glue_catalog_database.weather_athena_db.name
  name          = "weather_table_007"
  description   = "table containing the data from OpenWeather API stored in S3"

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL = "TRUE"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.weather_bucket.bucket}/data/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.IgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "s3-stream"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"

      parameters = {
        "serialization.format"  = 1
        "ignore.malformed.json" = "TRUE"
        "dots.in.keys"          = "FALSE"
        "case.insensitive"      = "TRUE"
        "mapping"               = "TRUE"
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

resource "aws_athena_workgroup" "athena_wg" {
  name = "athena"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.weather_bucket.bucket}/output/"

    }
  }
}

