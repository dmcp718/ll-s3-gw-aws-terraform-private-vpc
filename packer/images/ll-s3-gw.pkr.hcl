packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

locals { timestamp = regex_replace(timestamp(), "[- TZ:]", "") }

variable "region" {
  type    = string
  default = "us-east-2"
}

variable "instance_type" {
  type    = string
  default = "c5.xlarge"
}

variable "filespace" {
  type    = string
  default = "production.dpfs"
}

source "amazon-ebs" "ubuntu-minimal" {
  ami_name      = "ll-s3-gw-${var.filespace}-${local.timestamp}"
  instance_type = var.instance_type
  region        = var.region
  ssh_username  = "ubuntu"
  ebs_optimized = true

  source_ami_filter {
    filters = {
      virtualization-type = "hvm"
      name                = "ubuntu-minimal/images/hvm-ssd-gp3/ubuntu-mantic-23.10-amd64-minimal-2024*"
      root-device-type    = "ebs"
    }
    owners      = ["aws-marketplace"]
    most_recent = true
  }

  launch_block_device_mappings {
      device_name             = "/dev/sda1"
      volume_size             = 40
      volume_type             = "gp3"
      iops                    = 3000
      throughput              = 500
      delete_on_termination   = true
  }

  ami_block_device_mappings {
      device_name             = "/dev/sdb"
      volume_size             = 100
      volume_type             = "gp3"
      iops                    = 3000
      throughput              = 500
  }
}

build {
  name = "ll-s3-gw"
  sources = [
    "source.amazon-ebs.ubuntu-minimal"
  ]

  provisioner "file" {
    sources = [
      "../files/lucidlink-1.service",
      "../files/lucidlink-service-vars1.txt",
      "../files/lucidlink-password1.txt",
      "../files/minio1",
      "../files/s3-gw.service",
      "../files/compose.yaml"
    ]
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = ["echo Running build script..."]
  }

  provisioner "shell" {
    script          = "../files/build_script.sh"
    execute_command = "sudo /bin/bash -c '{{ .Vars }} {{ .Path }}'"
  }

  provisioner "shell" {
    inline = ["echo Build script complete"]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }

  post-processor "shell-local" {
    inline = [
      "AMI_ID=$(jq -r '.builds[-1].artifact_id' manifest.json | cut -d \":\" -f2)",
    "echo $AMI_ID > ami_id.txt"]
  }
}


