# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "My VPC"
  }
}

resource "aws_subnet" "my_subnet" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "My Subnet"
  }
}
resource "aws_security_group" "my_security_group" {
  name_prefix = "my-security-group"
  vpc_id      = aws_vpc.my_vpc.id
  description = "My Security Group"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 

  ingress {
    from_port   = 80
    to_port     = 80
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


resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
  depends_on = [
    aws_vpc.my_vpc
  ]
  tags = {
    Name = "My Internet Gateway"
  }
}

resource "aws_route_table" "my_route_table" {
  vpc_id = aws_vpc.my_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }
  tags = {
    Name = "My Route Table"
  }
}

resource "aws_route_table_association" "my_route_table_association" {
  subnet_id      = aws_subnet.my_subnet.id
  route_table_id = aws_route_table.my_route_table.id
}

/*resource "aws_key_pair" "my_key_pair" {
  key_name   = "my-key-pair"
  public_key = file("~/.ssh/id_rsa.pub")
}*/

resource "aws_instance" "ec2_prov" {
  ami           = "ami-0866a3c8686eaeeba"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.my_subnet.id
  security_groups = [aws_security_group.my_security_group.id]
  key_name = "AWS_k"
  tags = {
    Name = "Myec2_prov"
  }

  /* connection to ec2 */
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("/Users/thorins/documents/AWS_k.pem")
    host        = self.public_ip
  }

  /* file provisioner to copy a file from local to remote ec2 */
  provisioner "file" {
    source      = "./app.py"
    destination = "/home/ubuntu/app.py"
  }

  /* remote-exec provisioner to execute commands on the remote instance */
  provisioner "remote-exec" {
    inline = [
        "set -x",  # Enable debugging
    "echo 'Hello from the remote instance'",
    "sudo apt update -y",  # Update package lists
    "sudo apt-get install -y python3-pip python3-venv",  # Install pip and venv
    "cd /home/ubuntu",
    "python3 -m venv myenv",  # Create a virtual environment
    "source myenv/bin/activate",  # Activate the virtual environment
    "pip install flask",  # Install Flask in the virtual environment
    "python3 app.py"  # Run app.py in the current session only

    ]
  }
}

#cmd  = sudo ps -ef | grep python3

#useful link
#provisioner = https://developer.hashicorp.com/terraform/tutorials/provision?utm_source=WEBSITE&utm_medium=WEB_IO&utm_offer=ARTICLE_PAGE&utm_content=DOCS


/* provisioers helps to deloy application o ec2_instance*/

/* below is connection to ec2

connection {
    type = "ssh"
    user = "ubuntu"
    private_key = file("aws_k.pem")
    host = aws_instance.ec2_prov.public_ip    /*if we are already in resource of ec2 then in " host =self.public.ip"
}

/*file provisioner to copy  a file from local to remote ec2

provisioner "file" {
    source = "app.py"
    destination = "/Users/thorins/visualcode/main_project_D/app.py/app.py"
}

provisioner "remote-exec" {
    inline = [
      "echo 'Hello from the remote instance'",
      "sudo apt update -y",  # Update package lists (for ubuntu)
      "sudo apt-get install -y python3-pip",  # Example package installation
      "cd /home/ubuntu",
      "sudo pip3 install flask",
      "sudo python3 app.py &",
    ]
} */