terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_org_or_user" {
  type        = string
  description = "Your GitHub username or organization name"
  default     = "Ahmed-Abbas-1"
}

variable "github_repo_name" {
  type        = string
  description = "The application repository name"
  default     = "cloudpulse-microservices"
}

variable "microservices" {
  type = list(string)
  default = [
    "frontend-ui",
    "auth-gateway",
    "catalog-service",
    "order-service",
    "notification-worker"
  ]
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# 1. Encrypted S3 Bucket for Database Backups and Artifacts
resource "aws_s3_bucket" "enterprise_backups" {
  bucket        = "cloudpulse-enterprise-backups-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = {
    Project     = "CloudPulse"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_versioning" "backups_versioning" {
  bucket = aws_s3_bucket.enterprise_backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups_encryption" {
  bucket = aws_s3_bucket.enterprise_backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backups_private" {
  bucket                  = aws_s3_bucket.enterprise_backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2. Amazon ECR Repositories for Microservices with Image Scanning & Lifecycle Policy
resource "aws_ecr_repository" "services" {
  for_each             = toset(var.microservices)
  name                 = "cloudpulse/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = "CloudPulse"
    Service = each.key
  }
}

resource "aws_ecr_lifecycle_policy" "cleanup_old_images" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 10 images to save AWS storage costs"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# 3. GitHub Actions OIDC Provider for Keyless Authentication
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions_ecr_role" {
  name = "cloudpulse-github-actions-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org_or_user}/${var.github_repo_name}:*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "ecr_push_policy" {
  name = "cloudpulse-ecr-push-policy"
  role = aws_iam_role.github_actions_ecr_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = [for repo in aws_ecr_repository.services : repo.arn]
      }
    ]
  })
}

output "s3_backup_bucket_name" {
  value = aws_s3_bucket.enterprise_backups.bucket
}

output "ecr_repository_urls" {
  value = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_ecr_role.arn
}
