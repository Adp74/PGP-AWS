# ---------------  S3 BUCKETS -----------------------------------------

#it is used to upload lambda layer. Either create an s3 bucket or upload the object to an existing one
resource "aws_s3_bucket" "lambda_layer_s3_bucket" {
  bucket = "${var.PROJECT}-lambda-layers-${data.aws_caller_identity.current.account_id}"
  acl = "private"
  
  #update logging with the details of your project
  #logging {
  #  target_bucket =  
  #  target_prefix = 
  #}
  
  
  tags = merge(
    var.tags,
    {
      "Purpose" = "S3 bucket for lambda layer zip file"
    },
  )
}

#it is used to store pgp public key
resource "aws_s3_bucket" "s3_bucket_key_storage" {
  bucket = "${var.PROJECT}-public-pgp-${data.aws_caller_identity.current.account_id}"
  acl = "private"
  
  #update logging with the details of your project
  #logging {
  #  target_bucket =  
  #  target_prefix = 
  #}
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3_bucket_key_storage_cmk.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
  
  tags = merge(
    var.TAGS,
    {
      "Purpose" = "S3 bucket for pgp key storage"
    },
  )
}

resource "aws_s3_bucket_policy" "s3-policy-key-storage" {
  bucket = "${aws_s3_bucket.s3_bucket_key_storage.id}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "sspolicy",
  "Statement": [
       {
            "Sid": "EnforceHttpsAlways",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "*",
            "Resource": [
                "arn:aws:s3:::${var.PROJECT}-public-pgp-${data.aws_caller_identity.current.account_id}",
                "arn:aws:s3:::${var.PROJECT}-public-pgp-${data.aws_caller_identity.current.account_id}/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
  ]
}
POLICY
}


#----------------------- LAMBDA LAYER  ------------------------------------------------------

data "archive_file" "pgp-key-lambda" {
  type = "zip"

  output_path = "${path.module}/code/pgpDataCreation.zip"
  source {
    content  = file("${path.module}/code/pgp/pgpDataCreation.py")
    filename = "pgpDataCreation.py"
  }
}

# option 1 when uploading lambda layer (if zip file is small)
# resource "aws_lambda_layer_version" "shared_libs_crypto" {
#   description         = "Provides third party cryptography libraries for use in AWS Lambda"
#   layer_name          = "gdc_pcs_crypto_api_shared_libs"
#   filename            = "${path.module}/code/layer/shared_libs_crypto.zip"
#   source_code_hash    = filebase64sha256("${path.module}/code/layer/shared_libs_crypto.zip")
#   compatible_runtimes = ["python3.6", "python3.7"]
# }

#Option 2: lambda layer zip is stored in S3 bucket
resource "aws_s3_bucket_object" "shared_libs_crypto_file" {
  bucket = aws_s3_bucket.lambda_layer_s3_bucket.id
  key    = "shared_libs_crypto.zip"
  source = "${path.module}/code/layer/shared_libs_crypto.zip"
  etag = filemd5("${path.module}/code/layer/shared_libs_crypto.zip")
}


#lambda layer
resource "aws_lambda_layer_version" "shared_libs_crypto" {
  depends_on          = [aws_s3_bucket_object.shared_libs_crypto_file]
  description         = "Provides cryptography python libraries integrated with x-ray for use in AWS Lambda"
  layer_name          = "crypto_api_shared_libs"
  s3_bucket           = aws_s3_bucket.lambda_layer_s3_bucket.id
  s3_key              = "shared_libs_crypto.zip"

  #if option 1 because lambda layer size is small
  #filename            = "${path.module}/code/layer/shared_libs.zip"
  #source_code_hash    = filebase64sha256("${path.module}/code/layer/shared_libs.zip")
  
  compatible_runtimes = ["python3.6", "python3.7"]
}


#----------------------- LAMBDA FUNCTION ------------------------------------------------------

resource "aws_lambda_function" "pgp-key-lambda" {
  depends_on = [aws_s3_bucket.s3_bucket_key_storage]
  filename         = "${path.module}/code/pgpDataCreation.zip"
  function_name    = "${var.VPC_NAME}-${var.PROJECT}-pgp-key-lambda"
  role             = aws_iam_role.pgp-key-lambda-iam-role.arn
  handler          = "pgpDataCreation.handler"
  runtime          = "python3.6"
  source_code_hash = data.archive_file.pgp-key-lambda.output_base64sha256
  timeout          = 900   
  
  layers = [
    "${aws_lambda_layer_version.shared_libs_crypto.arn}"
  ]

  environment {
    variables = {
    "CreatePGPKeys" = "False",
 	  "KeyAlias" = aws_kms_alias.pgp_cmk_alias.name,
 	  "keyType"  = var.pgp_keyType,
 	  "keyLength" = var.pgp_keyLength,
 	  "userName"  = var.pgp_username,
 	  "email"     = var.pgp_email,
 	  "s3bucket"  = var.s3_bucket_key_storage_name,
 	  "KMSs3Alias" = aws_kms_alias.s3_bucket_key_storage_cmk_alias.name,
 	  "pgp_file_name" = var.pgp_file_name,
 	  "pgp_secret_pair_key_id"    = var.pgp_pair_key_secret_name,
 	  "PGPKeyimport"      = "False",
 	  "PGPFileName"       = var.pgp_file_name,
 	  "PGPFilePath"       = var.pgp_file_path,
 	  "PGPPublicSecretId" = var.pgp_public_key_secret_name
    }
  }
  
  
  tags = merge(
    var.TAGS,
    {
      "Purpose" = "Lambda function to create pgp key pairs and store them in S3 and Secrets manager"
      "Name"    = "${var.PROJECT}-pgp-key-lambda"
    },
  )

}


# pgp-key-lAmbda
resource "aws_iam_role" "pgp-key-lambda-iam-role" {
  name = "${var.VPC_NAME}-${var.PROJECT}-pgp-key-lAmbda"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
POLICY


  tags = merge(
    var.TAGS,
    {
      "Purpose" = "Lambda service role used for Lambda function to create pgp key pairs and store them in S3 and Secrets manager"
      "Name"    = "${var.PROJECT}-pgp-key-lAmbda-role"
    },
  )
}

# this policy does not follow the least priviledge advice. Please, modify for your use case.
resource "aws_iam_role_policy" "pgp-key-lambda-iam_inline_policy" {
  name = "pgp-key-lambda-inline-policy-logs-ssm"
  role = aws_iam_role.pgp-key-lambda-iam-role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSLambdaBasicExecutionRoleAccess",
      "Effect": "Allow",
      "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AccessvpcResources",
      "Effect": "Allow",
      "Action":  [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SSM",
      "Effect": "Allow",
      "Action": "ssm:*",
      "Resource": "*"
    },
    {
      "Sid": "AccessSecretManager",
      "Effect": "Allow",
      "Action": "secretsmanager:*",
      "Resource": "arn:aws:secretsmanager:eu-west-1:${var.account_id}:secret:*"
    },
    {
      "Sid": "AccessKMS",
      "Effect": "Allow",
      "Action": "kms:*",
      "Resource": "arn:aws:kms:eu-west-1:${var.account_id}:*"
    },
    {
      "Sid": "AccessSNS",
      "Effect": "Allow",
      "Action": "sns:*",
      "Resource": "*"
    },
    {
      "Sid": "AccessSES",
      "Effect": "Allow",
      "Action": "ses:*",
      "Resource": "*"
    },
    {
      "Sid": "AccessS3",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
      "arn:aws:s3:::${var.s3_bucket_key_storage_name}",
      "arn:aws:s3:::${var.s3_bucket_key_storage_name}/*"]
    },
    {
      "Sid": "AllowSLambdaInvoke",
      "Effect": "Allow",
      "Action": "lambda:InvokeFunction",
      "Resource": "${aws_lambda_function.pgp-key-lambda.arn}"
    }
  ]
}
EOF

}

#PERMISSIONS FOR SECRET KEY ROTATION
resource "aws_lambda_permission" "secrets-manager-permissions" {
  statement_id  = "AllowSecretManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pgp-key-lambda.function_name
  principal     = "secretsmanager.amazonaws.com"
}
