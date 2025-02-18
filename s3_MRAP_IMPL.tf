terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Generate random suffix for buckets
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Source Bucket
resource "aws_s3_bucket" "source" {
  bucket = "source-bucket-${random_id.bucket_suffix.hex}"
  force_destroy = true
  object_lock_enabled = false  # disable Object Lock
  versioning {
    enabled = false
  }
  tags = {
    Name        = "Source Bucket"
    Environment = "Production"
  }
}

/*
resource "aws_s3_bucket_object_lock_configuration" "source_lock" {
  bucket = aws_s3_bucket.source.id
  rule {
    default_retention {
      mode = "GOVERNANCE"  # or "COMPLIANCE"
      days = 30
    }
  }
}
*/

resource "aws_s3_bucket_server_side_encryption_configuration" "source_encryption" {
  bucket = aws_s3_bucket.source.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Destination Bucket in different region
provider "aws" {
  alias  = "west"
  region = "us-west-2"
}

resource "aws_s3_bucket" "destination" {
  provider            = aws.west
  bucket              = "destination-bucket-${random_id.bucket_suffix.hex}"
  force_destroy       = true
  object_lock_enabled = false
  versioning {
    enabled = false
  }
  tags = {
    Name        = "Destination Bucket"
    Environment = "Production"
  }
}
/*

resource "aws_s3_bucket_object_lock_configuration" "destination_lock" {
  provider = aws.west
  bucket   = aws_s3_bucket.destination.id
  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 30
    }
  }
}
*/
resource "aws_s3_bucket_server_side_encryption_configuration" "destination_encryption" {
  provider = aws.west
  bucket   = aws_s3_bucket.destination.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access for Source Bucket
resource "aws_s3_bucket_public_access_block" "source_block" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Block public access for Destination Bucket
resource "aws_s3_bucket_public_access_block" "destination_block" {
  provider = aws.west
  bucket   = aws_s3_bucket.destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# Create an Amazon S3 Multi-Region Access Point
resource "aws_s3control_multi_region_access_point" "mrap" {
  details {
    name = "s3-mrap-${random_id.bucket_suffix.hex}"
    
    # Specify each region in its own block
    region {
      bucket = aws_s3_bucket.source.bucket
      region = "us-east-1"  # Specify the region for the source bucket
    }
    
    region {
      bucket = aws_s3_bucket.destination.bucket
      region = "us-west-2"  # Specify the region for the destination bucket
    }
  }
}

output "mrap_arn" {
  value = aws_s3control_multi_region_access_point.mrap.arn
}

output "mrap_alias" {
  value = aws_s3control_multi_region_access_point.mrap.alias
}

resource "null_resource" "write_outputs_to_file" {
  provisioner "local-exec" {
    command = <<EOT
    echo "MRAP ARN: ${aws_s3control_multi_region_access_point.mrap.arn}" > mrap_output.txt
    echo "MRAP Alias: ${aws_s3control_multi_region_access_point.mrap.alias}" >> mrap_output.txt
    EOT
  }
}
/* Check Output:
terraform apply
cat mrap_output.txt
*/

resource "aws_s3_bucket_replication_configuration" "replication1" {
    bucket = aws_s3_bucket.source.bucket
    role = aws_iam_role.replication_role.arn
    #role   = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/s3_replication_role"
    #token  = "1234567890"  # Replace with your desired token value

    rule {
        id     = "replication-rule"
        status = "Enabled"  # Replication rule is enabled

         # Apply to all objects in the bucket
    filter {
      prefix = ""  # Empty prefix means apply to all objects
    }

        destination {
            bucket = aws_s3control_multi_region_access_point.mrap.alias
            account = data.aws_caller_identity.current.account_id
            storage_class = "STANDARD"

        #priority = 1
        #delete_marker_replication {
            #status = "Enabled" }
    }
} 
}
resource "aws_s3_bucket_replication_configuration" "replication2" {
    provider = aws.west
    bucket = aws_s3_bucket.destination.bucket
    role = aws_iam_role.replication_role.arn
    #role   = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/s3_replication_role"
    #token  = "1234567890"  # Replace with your desired token value

    rule {
        id     = "replication-rule"
        status = "Enabled"

        destination {
            bucket = aws_s3control_multi_region_access_point.mrap.alias
            account = data.aws_caller_identity.current.account_id
            storage_class = "STANDARD"

        #priority = 1
        #delete_marker_replication {
            #status = "Enabled" }
    }
} 
}
resource "aws_iam_role" "replication_role" {
  name = "s3-replication-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "replication_policy" {
  name        = "s3-replication-policy"
  description = "IAM policy for S3 replication"

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = [
          aws_s3_bucket.bucket1.arn,
          aws_s3_bucket.bucket2.arn
        ]
      },
      {
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl"
        ]
        Effect   = "Allow"
        Resource = [
          "${aws_s3_bucket.bucket1.arn}/*",
          "${aws_s3_bucket.bucket2.arn}/*"
        ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Effect   = "Allow"
        Resource = [
          "${aws_s3_bucket.bucket1.arn}/*",
          "${aws_s3_bucket.bucket2.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "replication_attach" {
  role       = aws_iam_role.replication_role.name
  policy_arn = aws_iam_policy.replication_policy.arn
}

# Replication configuration with RTC, delete marker replication, and replica modification sync
resource "aws_s3_bucket_replication_configuration" "replication" {
  role = aws_iam_role.replication_role.arn
  bucket = aws_s3_bucket.bucket1.id

  rule {
    status = "Enabled"
    filter {}
    delete_marker_replication { status = "Enabled" }
    destination {
      bucket = aws_s3_bucket.bucket2.arn
      storage_class = "STANDARD"
      replication_time {
        status = "Enabled"
        time { minutes = 15 }  # RTC configuration
      }
      metrics {
        status = "Enabled"
        event_threshold { minutes = 15 }
      }
    }
    source_selection_criteria {
      replica_modifications { status = "Enabled" }
    }
  }
}

# Upload existing content to source bucket
resource "aws_s3_object" "upload_files" {
  for_each = fileset("/Users/thorins/visualcode/s3_replication", "*") # Adjust this to the correct folder
  bucket = aws_s3_bucket.source.id
  key    = each.value
  source = "/Users/thorins/visualcode/s3_replication/${each.value}"
}

/*resource "aws_s3_object" "upload_object" {
  bucket = aws_s3_bucket.source.bucket
  key    = "example_file.txt"  # Change to your file name
  source = "path/to/your/local/file.txt"  # Path to your local file

  etag = filemd5("path/to/your/local/file.txt")  # Ensures file consistency
}
This will ensure the object is replicated automatically 
through your S3 Multi-Region Access Points setup! 
Update key with the desired object name.
Update source with the path to the file you want to upload.
*/

#Failover Configuration - Although failover is initiated between only two Regions at one time, you can separately update the routing statuses for multiple Regions at the same time in your Multi-Region Access Point.
/*
In Amazon S3 Multi-Region Access Points, failover routing ensures that your application traffic is directed to the most available and responsive S3 bucket in your chosen regions. While only two regions can be in failover at a time, you can manually or programmatically update the routing statuses for multiple regions simultaneously through the AWS Console, CLI, or SDK.
You can use the aws s3control command to update routing statuses programmatically:
aws s3control update-multi-region-access-point-routes \
    --account-id 123456789012 \
    --mrap arn:aws:s3::<account-id>:accesspoint/<mrap-alias> \
    --route-updates '[{"Region": "us-west-1", "TrafficDialPercentage": 100}, {"Region": "us-east-1", "TrafficDialPercentage": 0}, {"Region": "eu-central-1", "TrafficDialPercentage": 50}]'
This command updates routing for multiple regions at once by adjusting the TrafficDialPercentage, effectively balancing or disabling traffic across regions simultaneously.
You can adjust traffic routing for several regions at the same time, though only one failover pair is active at once.
This helps in scenarios like:
Regional maintenance.
Partial outages.
Performance optimization.
Failover Configuration - Although failover is initiated between only two Regions at one time, you can separately update the routing statuses for multiple Regions at the same time in your Multi-Region Access Point.
# Failover configuration (Active-Passive)
resource "aws_s3control_multi_region_access_point_policy" "mrap_failover" {
  mrap_name = aws_s3control_multi_region_access_point.mrap.name

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Sid       = "ActivePassiveRouting"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource  = "${aws_s3control_multi_region_access_point.mrap.arn}/*"
        Condition = {
          StringEquals = {
            "s3:DataAccessPointRegion" : "us-east-1"  # Active Region
          }
        }
      },
      {
        Sid       = "PassiveRegion"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource  = "${aws_s3control_multi_region_access_point.mrap.arn}/*"
        Condition = {
          StringEquals = {
            "s3:DataAccessPointRegion" : "us-west-2"  # Passive Region
          }
        }
      }
    ]
  })
}
*/

#Failover Configuration 

# Active-Passive Routing Configuration
resource "aws_s3control_multi_region_access_point_routes" "mrap_routes" {
  #account_id         = "<your-account-id>"
  mrap_identifier    = aws_s3control_multi_region_access_point.mrap.id

  route {
    region  = "us-east-1"
    status  = "ACTIVE"
  }

  route {
    region  = "us-west-2"
    status  = "PASSIVE"
  }
}

# IAM Role for S3 MRAP Routing Management
resource "aws_iam_role" "mrap_routing_role" {
  name = "mrap-routing-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "s3.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "mrap_routing_policy" {
  name        = "mrap-routing-policy"
  description = "Policy for managing MRAP routing"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = [
        "s3:PutMultiRegionAccessPointRoutes",
        "s3:GetMultiRegionAccessPointRoutes"
      ],
      Effect   = "Allow",
      Resource = aws_s3control_multi_region_access_point.mrap.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "mrap_policy_attach" {
  role       = aws_iam_role.mrap_routing_role.name
  policy_arn = aws_iam_policy.mrap_routing_policy.arn
}

/* 
resource "aws_iam_policy" "policymrap" {
  name        = "s3-mrap-policy"
  description = "Policy for managing MRAP routing"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "*",
      Effect   = "Allow",
      Principal = { "AWS":"*" }   #The * means all AWS accounts, users, and roles are allowed access.For tighter security, you could specify specific AWS accounts, IAM roles, or users instead of using a wildcard.
      Resource = :[
        "<BucketARN>",
        "<BucketARN>/*"          #For tighter security, you could specify specific AWS accounts, IAM roles, or users instead of using a wildcard.
       # "${aws_s3control_multi_region_access_point.mrap.arn}/*",
       #"${aws_s3control_multi_region_access_point.mrap.arn}"
      ],
      "Condition": {                        
        "StringEquals": {
          "s3:DataAccessPointArn" : "<MultiRegionAccessPoint_ARN>"
         # "s3:DataAccessPointAccount": "${data.aws_caller_identity.current.account_id}"
        }
      }
    }]
  })
}

#for condition - Adds a condition that this policy is only enforced when the request is made through the specified Multi-Region Access Point ARN.
Ensures that even though the policy grants wide access (*), it only works when accessed via the MRAP, providing an additional layer of security.

if want to restrict access to your Multi-Region Access Point
 inserting your account ID, user name, and Multi-Region Access Point ARN in the relevant sections (replacing the text inside the <angle brackets>). This policy example provides the named user with permission to use this 
 access point to carry out all supported Amazon S3 operations.

{
  "Version":"2012-10-17",
  "Statement": [
    {
       "Effect": "Allow",
       "Principal": {
          "AWS":"arn:aws:iam::123456789012:user/JohnDoe"
       },
       "Action":[
          "s3:ListBucket",
          "s3:GetObject"
       ],
       "Resource":[ 
          "MultiRegionAccessPoint_ARN",
          "MultiRegionAccessPoint_ARN/object/*"
       ]
     }
  ]
}
*/

#Use Your Multi-Region Access Point:
#You can use Multi-Region Access Points to access data 
#in your buckets by using a subset of Amazon S3 API operations
/*Simplifying cross-Region access to Amazon S3: For example, if you have an S3 bucket in one AWS Region and compute resources across multiple Regions, you would need to set up VPC peering to use PrivateLink. With an S3 Multi-Region Access Point in front of the S3 bucket and s3-global VPC endpoints local to the compute, there is no need for VPC peering.
Note: S3 Multi-Region Access Points cannot be accessed via 
any other type of VPC endpoint than com.amazonaws.s3-global.accesspoint. 
In addition, accessing Amazon S3 directly from Amazon EC2 does not incur Data Transfer OUT From Amazon EC2 To Internet or Data Transfer OUT From Amazon S3 To Internet charges, 
including when S3 buckets are accessed through an S3 Multi-Region Access Point.
*/

#7.VPC endpoints
provider "aws" {
  region = "us-east-1"  # Change region if needed
}

# Create VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "my_vpc"
  }
}

# Create Subnet
resource "aws_subnet" "my_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = {
    Name = "my_subnet"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "my_igw"
  }
}

# Create Route Table
resource "aws_route_table" "my_route_table" {
  vpc_id = aws_vpc.my_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }
  tags = {
    Name = "my_route_table"
  }
}

# Associate Route Table with Subnet
resource "aws_route_table_association" "my_association" {
  subnet_id      = aws_subnet.my_subnet.id
  route_table_id = aws_route_table.my_route_table.id
}

# Security Group for EC2
resource "aws_security_group" "my_sg" {
  vpc_id = aws_vpc.my_vpc.id
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
  tags = {
    Name = "my_sg"
  }
}

# EC2 Instance
resource "aws_instance" "my_ec2" {
  ami             = "ami-0c02fb55956c7d316"  # Amazon Linux 2 AMI (change based on your region)
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.my_subnet.id
  security_groups = [aws_security_group.my_sg.name]

  tags = {
    Name = "my_ec2"
  }
}

# S3 VPC Endpoint
resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id            = aws_vpc.my_vpc.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [aws_route_table.my_route_table.id]

  tags = {
    Name = "s3_vpc_endpoint"
  }
}

#8.monitor Amazon S3 Replication in the Multi-Region Access Point console, and S3 request metrics in Amazon CloudWatch.
#!/bin/bash

# Step 1: Run Terraform to deploy infrastructure
echo "Applying Terraform configuration..."
terraform apply -auto-approve

# Step 2: Retrieve MRAP ARN from Terraform output
echo "Retrieving MRAP ARN..."
mrap_arn=$(terraform output -raw mrap_arn)
echo "Multi-Region Access Point ARN: $mrap_arn"

# Step 3: Create a 1 MiB test file
echo "Creating a 1 MiB test file..."
dd if=/dev/urandom of=testfile bs=1M count=1

# Step 4: Start generating traffic every 20 seconds
echo "Starting traffic generation for 20 minutes..."
(
  end=$((SECONDS+1200))  # 1200 seconds = 20 minutes
  while [ $SECONDS -lt $end ]; do
    echo "Uploading file to $mrap_arn"
    aws s3 cp testfile s3://$mrap_arn/testfile-$(date +%s)
    
    echo "Downloading file from $mrap_arn"
    aws s3 cp s3://$mrap_arn/testfile-$(date +%s) downloaded-testfile-$(date +%s)

    echo "Sleeping for 20 seconds..."
    sleep 20
  done
  echo "Traffic generation completed after 20 minutes."
) &

# Step 5: Wait for 20 minutes then stop the script
wait
echo "Script execution finished."

/*Key Changes and Additions:
Save the above code in a file called automate_mrap_setup.sh.
Make the script executable:
chmod +x automate_mrap_setup.sh
Run the script:
./automate_mrap_setup.sh

mrap_arn fetched dynamically using terraform output from the provided Terraform MRAP resource.
end_time variable ensures the script runs for exactly 20 minutes.
Loop runs until SECONDS reaches 1200 seconds (20 minutes).
Uploads and downloads a 1 MiB file every 20 seconds to/from your MRAP.
Automatically stops after 20 minutes to prevent unnecessary costs.




arn:aws:s3::343218192165:accesspoint/mu46f51nysup4.mrap
mu46f51nysup4.mrap


You can initiate failover between 2 Regions that 
are configured to be in an active-passive state. 
To failover, select 1 active and 1 passive Region below and then choose the Failover button. 
Failover switches the routing statuses of both Regions at once. 
To independently change the routing status of 1 or more Regions, 
choose the Edit routing status button.
 To keep all objects and metadata in sync between Regions before and after failover
  or any routing status changes, we recommend that you create two-way S3 Replication rules.
  arn:aws:s3:::buck1east

cmds - 
mrap_arn=arn:aws:s3::343218192165:accesspoint/mu46f51nysup4.mrap
thorins@ThorinSs-MacBook-Air visualcode % aws s3 ls $mrap_Arn
2025-02-15 23:54:23 buck1east
2025-02-15 23:55:17 buck2west
To use the copy command to download (GET) an object from the closest active S3 bucket to the current folder of your command shell, use the following commands (updating the file name as required).

 aws s3 cp s3://$mrap_arn/arch.gif downloads    
download: s3://arn:aws:s3::343218192165:accesspoint/mu46f51nysup4.mrap/arch.gif to ./downloads

Solution:
Run the command again by specifying the correct region: aws s3control list-multi-region-access-points --account-id 343218192165 --region us-west-2
aws s3 cp /Users/thorins/visualcode/main.tf s3://arn:aws:s3::343218192165:accesspoint/mu46f51nysup4.mrap/object/main.tf --region us-west-2

executed - upload: ./main.tf to s3://arn:aws:s3::343218192165:acc

metadata -

Metadata is data that provides information about other data. In the context of AWS S3 objects, metadata refers to information about an object stored in S3, but not the actual content of the object itself.
aws s3api head-object --bucket buck2west --key main.tf --region us-west-1

aws s3api head-object --bucket buck1east --key arch.gif --region us-east-1

{
    "AcceptRanges": "bytes",
    "LastModified": "2025-02-15T18:28:45+00:00",
    "ContentLength": 1910751,
    "ETag": "\"abfb4b46c6a20cd1ee043469c716b53c\"",
    "VersionId": "null",
    "ContentType": "image/gif",
    "ServerSideEncryption": "AES256",
    "Metadata": {}
}

generating files----ps
#!/bin/bash
echo "Starting traffic generation for 20 minutes..."

mrap_arn="arn:aws:s3::343218192165:accesspoint/mu46f51nysup4.mrap"  # MRAP ARN
region="us-west-2"               # Correct region for MRAP operations

# Create a 1 MiB file containing random data
dd if=/dev/urandom of=~/1MiB.file bs=1024 count=1024

end=$((SECONDS+1200))  # Run for 20 minutes (1200 seconds)

while [ $SECONDS -lt $end ]; do
    datetime=$(date "+%Y.%m.%d-%H.%M.%S")

    echo "Uploading 1MiB file to $mrap_arn"
    aws s3 cp ~/1MiB.file s3://$mrap_arn/load_generator/1MiB_from_load_generator.$datetime --region $region

    echo "Downloading 1MiB file from $mrap_arn"
    aws s3 cp s3://$mrap_arn/load_generator/1MiB_from_load_generator.$datetime ~/1MiB_from_S3 --region $region

    echo "Sleeping for 20 seconds..."
    sleep 20
done

echo "Traffic generation completed after 20 minutes."

*/
