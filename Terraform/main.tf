provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

# ------------------------- KEY PAIR -------------------------
resource "aws_key_pair" "key_pair" {
  key_name   = "MyKey"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCpYNgTTqIEnkxo+5bFw1KQtO9BXbOPnpnT7lK2p/Ctizu+HIelY1MtE79K3sh+fXjGd35a17h1T045ErrS5RYDCfm2e0Kw671AmzM9/87Yo6Z7IKB/MaR4Xv3pyZt0bM8gAkxtLYZ+z5X15gr/7/OJmos5UJK6jEfSij5XIqoS97aFQ2uv01pbbDxdjPYbMXfcLdnIaZ67oGCaghlcJPc/PaeCrhMHCYIQi6bj/mXTUtk/coE6Bs/8s6wLmcI2UdMRMKGrcPFGwIxgtrTUgkDAR6Ya2q+jfPdXtNal3QgynqK7oBFi5ii6vnLD3WybVLvWS8DHQkDforoWWLdKloZpGLbN2pVsfR1+Jq3cgS4lKrAFB12678b7ZzWPRzoQXyDRgEIO6TbvP830JsaRsii9JJ0/mhxzeOCKCsK8rb6RHT5Nrax1OYKK5JqfYu072kXxr2qESrrSWFJp/U+MtzoB60DiydmUxHByqV+gjTVteA1EtpKmIaOZkJaa84zqBBk= HP@DESKTOP-KH6VGQA"
}

# ------------------------- VPC -------------------------
resource "aws_vpc" "prod" {
  cidr_block           = "172.20.0.0/16"
  enable_dns_hostnames = true

  tags = { Name = "prod" }
}

# ------------------------- SUBNET -------------------------
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.prod.id
  cidr_block              = "172.20.10.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = { Name = "public-subnet" }
}

# ------------------------- INTERNET GATEWAY -------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.prod.id

  tags = { Name = "prod-igw" }
}

# ------------------------- ROUTE TABLE -------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.prod.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "public-route-table" }
}

# ------------------------- ROUTE TABLE ASSOCIATION -------------------------
resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ------------------------- SECURITY GROUP - JENKINS -------------------------
resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-sg"
  vpc_id      = aws_vpc.prod.id
  description = "SG for Jenkins Server"

  ingress {
    description = "Jenkins HTTP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Ping"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SonarQube HTTP"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jenkins-sg" }
}

# ------------------------- SECURITY GROUP - MyApp -------------------------
resource "aws_security_group" "myapp_sg" {
  name        = "myapp-sg"
  vpc_id      = aws_vpc.prod.id
  description = "MyApp SG"

  ingress {
    description = "MyApp Port"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "All Inbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "myapp-sg" }
}

# ------------------------- JENKINS INSTANCE -------------------------
resource "aws_instance" "jenkins" {
  ami                    = "ami-01edba92f9036f76e"
  instance_type          = "c7i-flex.large"
  subnet_id              = aws_subnet.public_subnet.id
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ec2-user"
    private_key = file("~/.ssh/id_rsa")
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install java-21-amazon-corretto -y",
      "sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo",
      "sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key",
      "sudo yum install jenkins -y",
      "sudo systemctl enable jenkins && sudo systemctl start jenkins",
      "sudo yum install wget git maven ansible docker -y",
      "sudo systemctl enable docker && sudo systemctl start docker",
      "sudo usermod -aG docker ec2-user",
      "sudo usermod -aG docker jenkins",
      "sudo chmod 666 /var/run/docker.sock",
      "sudo docker run -d --name sonarct -p 9000:9000 sonarqube",
      "sudo rpm -ivh https://github.com/aquasecurity/trivy/releases/download/v0.18.3/trivy_0.18.3_Linux-64bit.rpm"
    ]
  }

  tags = { Name = "Jenkins-From-Terraform" }
}

# ------------------------- MyApp INSTANCE -------------------------
resource "aws_instance" "myapp" {
  ami                    = "ami-01edba92f9036f76e"
  instance_type          = "c7i-flex.large"
  subnet_id              = aws_subnet.public_subnet.id
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [aws_security_group.myapp_sg.id]

  tags = { Name = "MyApp-From-Terraform" }
}
