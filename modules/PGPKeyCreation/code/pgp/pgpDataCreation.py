import boto3
import sys
import os
import json
import pprint
import random
import datetime
import base64
import cryptography
from base64 import b64decode,b64encode
import binascii
from botocore.client import Config
import logging
import time
from botocore.exceptions import ClientError
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.application import MIMEApplication

#for PGP
import gnupg

#X-RAY
logger = logging.getLogger()
logger.setLevel(logging.INFO)

gpg = gnupg.GPG(homedir='/tmp')

##########-----------------PGP------------
def gnupg_create_key(keyType, keyLength, userName, email):
    print("creating pgp key with python gnupg\n")
    try:
        input_data = gpg.gen_key_input(key_type=keyType, key_length=keyLength, name_real=userName,name_email=email)
        key = gpg.gen_key(input_data)
        ascii_armored_public_keys = gpg.export_keys(key) # same as gpg.export_keys(keyids, False)
        ascii_armored_private_keys = gpg.export_keys(key, True) # True => private keys
        return { 'key': key, 'ascii_armored_public_keys': ascii_armored_public_keys, 'ascii_armored_private_keys':ascii_armored_private_keys}
    except Exception as e:
        print(e)

def import_key_gnupg(key_data_value):
    print("importing pgp key with python gnupg\n")
    try:
        import_result = gpg.import_keys(key_data_value)
        print("IMPORT RESULT\n")
        print(import_result.results)
        print("FINGERPRINT\n")
        print(import_result.fingerprints)
        return import_result.fingerprints
    except Exception as e:
        print(e)
        return False
    return False
      
##########-----------------SECRETS MANAGER------------
def secrets_manager_key_management(secret_value, secret_id, description, KMSkeyAlias):    
    client_secrets = boto3.client('secretsmanager')
    try:
        print("checking details for secret with id {}...\n".format(secret_id))
        priv_key_string_exists = client_secrets.describe_secret(SecretId=secret_id)
        print("Updating secret...\n")
        response_2 = client_secrets.update_secret(SecretId=secret_id,Description=description, KmsKeyId=KMSkeyAlias,SecretString=secret_value)
    except Exception as e:
        print('There is not any secret with that secret id. Creating a new one...\n')
        print(e)
        response_2 = client_secrets.create_secret(Name=secret_id,Description=description, KmsKeyId=KMSkeyAlias,SecretString=secret_value)

#update secrets manager
def set_secret_rotation(service_client, secret_id, lambda_arn, rotation_days):
    print("setting secret rotation..\n")
    try:
       response = service_client.rotate_secret(RotationLambdaARN=lambda_arn,RotationRules={'AutomaticallyAfterDays': rotation_days},SecretId=secret_id)
    except Exception as e:
        print(e)
        logger.info("Exception when adding rotation configuration to secret\n")

##########-----------------S3------------    
#without kms
def export_keys_to_s3(public_keys, keypairfile, bucket, path):    
    s3 = boto3.resource('s3')
    bucket = s3.Bucket(bucket)
    local_file = "/tmp/" + keypairfile 
    with open(local_file, 'w') as f:
        f.write(public_keys)
    s3_path = path + keypairfile
    bucket.upload_file(local_file, s3_path)

#WITH KMS
def export_keys_to_s3_with_KMS(public_keys, keypairfile, bucket, path, s3KMSAlias):    
    s3 = boto3.client("s3", config=Config(signature_version='s3v4'))
    local_file = "/tmp/" + keypairfile 
    with open(local_file, 'w') as f:
        f.write(public_keys)
    s3_path = path + keypairfile
    s3.upload_file(local_file, bucket, s3_path, ExtraArgs={'ServerSideEncryption':'aws:kms', 'SSEKMSKeyId':s3KMSAlias})

#upload to s3
def upload_file_to_s3_KMS(local_file, bucket, s3_path):
    s3 = boto3.client('s3')
    s3.upload_file(local_file, bucket, s3_path, ExtraArgs={'ServerSideEncryption':'aws:kms', 'SSEKMSKeyId':'alias/sf-s3bucket-target-cmk'})

def upload_file_to_s3(local_file, bucket, s3_path):
    s3 = boto3.client('s3')
    s3.upload_file(local_file, bucket, s3_path)

def get_most_recent_s3_object(bucket_name, prefix):
    s3 = boto3.client('s3')
    paginator = s3.get_paginator("list_objects_v2")
    page_iterator = paginator.paginate(Bucket=bucket_name, Prefix=prefix)
    latest = None
    for page in page_iterator:
        if "Contents" in page:
            latest = max(page['Contents'], key=lambda x: x['LastModified'])
    return latest

#UPLOAD TO TMP
def upload_to_tmp(body,file):
    print("uploading key file to tmp..\n")
    local_file = "/tmp/" + file 
    with open(local_file, 'w') as f:
        f.write(body)
        
#DOWNLOAD FROM S3
def download_file_from_s3_KMS(filename,file_path, bucket):
    print("downloading file from {} s3 bucket with name {} in path {}...\n".format(bucket,filename,file_path ))
    s3 = boto3.client("s3", config=Config(signature_version='s3v4'))
    local_file = "/tmp/" + filename 
    s3_file = file_path + "/"+ filename
    try:
        s3.download_file(bucket, s3_file, local_file)
    except Exception as e:
        print(e)
        return False
    return local_file

def from_file_to_secret_manager(local_file,secret_id, description, KMSkeyAlias):
    print("from_file_to_secret_manager..\n")
    try:
        with open(local_file, 'r') as f:
            text = f.read()
            secrets_manager_key_management(text, secret_id, description, KMSkeyAlias)
    except Exception as e:
        print(e)
        return False
    return True
    

#### lambda handler
def handler(event, context):

    if os.environ["CreatePGPKeys"] == "True":
        print("Starting PGP Key creation...\n")
        pgp_keys = gnupg_create_key(os.environ['keyType'], os.environ['keyLength'], os.environ['userName'], os.environ['email'])
        key_pair = pgp_keys['ascii_armored_private_keys'] + "\n" + pgp_keys['ascii_armored_public_keys']
        #secrets_manager_key_management(pgp_keys['ascii_armored_private_keys'], os.environ['pgp_secret_priv_key_id'],"Private Key for SAP PGP in SF",os.environ['KeyAlias'])
        secrets_manager_key_management(key_pair, os.environ['pgp_secret_pair_key_id'],"PGP Key Pair for SAP PGP in SF",os.environ['KeyAlias'])
        #export_keys_to_s3(pgp_keys['ascii_armored_public_keys'], os.environ['pgp_file_name'], os.environ['s3bucket'], "pgpKeys/")
        export_keys_to_s3_with_KMS(pgp_keys['ascii_armored_public_keys'], os.environ['pgp_file_name'], os.environ['s3bucket'], "pgpKeys/", os.environ["KMSs3Alias"])
    if os.environ["PGPKeyimport"] == "True":
        local_file_name = download_file_from_s3_KMS(os.environ["PGPFileName"],os.environ["PGPFilePath"], os.environ["s3bucket"])
        from_file_to_secret_manager(local_file_name, os.environ['PGPPublicSecretId'], "This is a secret manager for PGP public Key", os.environ['KeyAlias'])
        
    return event
