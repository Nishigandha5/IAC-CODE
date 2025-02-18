provider "aws" {
  region = "us-east-1" # Change this to your desired source bucket region
}

# Source S3 Bucket
resource "aws_s3_bucket" "source" {
  bucket = "source-bucket-name"
}

# Enable Versioning on Source Bucket
resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Destination S3 Bucket (Replica)
resource "aws_s3_bucket" "replica" {
  bucket = "replica-bucket-name"
  provider = aws.replica
}

# Enable Versioning on Replica Bucket
resource "aws_s3_bucket_versioning" "replica" {
  bucket = aws_s3_bucket.replica.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Create IAM Role for Replication
resource "aws_iam_role" "s3_replication_role" {
  name = "s3-replication-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Attach IAM Policy to allow replication
resource "aws_iam_policy" "s3_replication_policy" {
  name        = "s3-replication-policy"
  description = "IAM policy for S3 cross-region replication"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete",
        "s3:ReplicateTags"
      ],
      "Resource": [
        "${aws_s3_bucket.replica.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObjectVersionForReplication",
        "s3:GetObjectVersionAcl",
        "s3:GetObjectVersionTagging"
      ],
      "Resource": [
        "${aws_s3_bucket.source.arn}/*"
      ]
    }
  ]
}
EOF
}

# Attach policy to the role
resource "aws_iam_role_policy_attachment" "s3_replication_attach" {
  role       = aws_iam_role.s3_replication_role.name
  policy_arn = aws_iam_policy.s3_replication_policy.arn
}

# Add Replication Configuration to the Source Bucket
resource "aws_s3_bucket_replication_configuration" "replication" {
  bucket = aws_s3_bucket.source.id
  role   = aws_iam_role.s3_replication_role.arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.replica.arn
      storage_class = "STANDARD"
    }
  }
}

# Secondary provider for destination bucket
provider "aws" {
  alias  = "replica"
  region = "us-west-2" # Change this to the region of your replica bucket
}
