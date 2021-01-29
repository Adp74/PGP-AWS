#--------------Secrets manager kms key----------
resource "aws_kms_key" "pgp_cmk" {
  description             = "symmetric CMK key to encrypt pgp key in secrets managers"
  enable_key_rotation     = true
  #deletion_window_in_days = 30
  is_enabled              = true
  tags                    = var.TAGS

 # lifecycle {
 #    prevent_destroy = true
  #}

  #* Policy taken from https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html in KMS Keys and Encryption Context --> Point 4

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {

          "Sid" : "Enable IAM User Permissions",
          "Effect" : "Allow",
          "Principal" : {
            "AWS" : [
                "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
                "${aws_iam_role.pgp-key-lambda-iam-role.arn}"
            ]
            
          },
          "Action" : "kms:*",
          "Resource" : "*"
        }
      ]
    }
  )

}

resource "aws_kms_alias" "pgp_cmk_alias" {
  name          = var.pgp_kms_key_alias
  target_key_id = aws_kms_key.pgp_cmk.key_id
}


#--------------KEY STORAGE BUCKET kms key----------
resource "aws_kms_key" "s3_bucket_key_storage_cmk" {
  description             = "symmetric CMK key for SF s3 bucket key storage"
  enable_key_rotation     = true
  is_enabled              = true
  tags                    = var.TAGS


  #* Policy taken from https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html in KMS Keys and Encryption Context --> Point 4

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {

          "Sid" : "Enable IAM User Permissions",
          "Effect" : "Allow",
          "Principal" : {
            "AWS" : [
                "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
                "${aws_iam_role.pgp-key-lambda-iam-role.arn}"
            ]
            
          },
          "Action" : "kms:*",
          "Resource" : "*"
        }
      ]
    }
  )

}

resource "aws_kms_alias" "s3_bucket_key_storage_cmk_alias" {
  name          = "alias/sf-s3-bucket-key-storage"
  target_key_id = aws_kms_key.s3_bucket_key_storage_cmk.key_id
}