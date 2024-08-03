# This variable defines the AWS Region.
variable "region" {
  description = "region to use for AWS resources"
  type        = string
  default     = "eu-west-1"
}

variable "global_prefix" {
  type    = string
  default = "weather-msk"
}

variable "private_cidr_blocks" {
  type = list(string)
  default = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24",
  ]
}

variable "cidr_blocks_bastion_host" {
  type    = list(string)
  default = ["10.0.4.0/24"]
}

variable "api_key" {
  description = "OpenWeather API Key"
  type        = string
  sensitive   = true
}

variable "lat" {
  description = "Latitude for weather data"
  type        = string
  default     = "6.1944"
}

variable "lon" {
  description = "Longitude for weather data"
  type        = string
  default     = "106.8229"
}

variable "kafka_topic" {
  description = "Kafka topic name"
  type        = string
  default     = "weather_topic"
}


variable "s3_bucket" {
  description = "S3 bucket name for storing data"
  type        = string
  default     = "weather-data-bucket-007"
}