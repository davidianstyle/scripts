#!/usr/local/bin/python

# Run this script with:
# $ python3.6 ~/scripts/backup.py --daily/--monthly/--yearly --site [sitename] --rootdirectory [root dir] --backupdirectory [backup dir]
#
# This script will:
# 1.) Cycle through specified site root directory for sites to backup (default: /home/dchang/sites/)
# 2.) Stage backup in a temp location (default: /home/dchang/backups/)
# 3.) Copy all site files
# 4.) Parse wp-config file for db user/password to conduct a sql dump
# 5.) Gzip site files along with db backup
# 6.) Send to AWS S3 to be stored in correct periodic folder (daily/monthly/yearly)
# 7.) Cleanup temp location
#
# Required parameters:
# One of:
#   --daily
#   --monthly
#   --yearly
#
# Optional parameters:
# --rootdirectory	(default: /home/dchang/sites)
# --backupdirectory	(default: /home/dchang/backups)
# --verbose		Runs with verbose output
# --cleanup		Cleans the backupdirectory after script run

import argparse
import os
import sys
import warnings
import shutil
import distutils
from distutils import dir_util
import tarfile
import subprocess
import datetime
import re
import boto3

# Default S3 bucket - make sure this bucket exists
DEFAULT_BUCKET = 'misc-sites'

# Parse script arguments
parser = argparse.ArgumentParser()
group = parser.add_mutually_exclusive_group()
group.add_argument("-d", "--daily", help="Save backup to 'daily' folder", action="store_true")
group.add_argument("-m", "--monthly", help="Save backup to 'monthly' folder", action="store_true")
group.add_argument("-a", "--yearly", help="Save backup to 'yearly' folder", action="store_true")
parser.add_argument("--rootdirectory", help="Specify a root directory to backup")
parser.add_argument("--backupdirectory", help="Specify a directory to stage the temporary backup")
parser.add_argument("--bucket", help="Specify an s3 bucket to store backup")
parser.add_argument("--site", help="Specify a site to backup")
parser.add_argument("--verbose", help="Print verbose output", action="store_true")
parser.add_argument("--cleanup", help="Clean up backup directory", action="store_true")
args = parser.parse_args()
if not (args.daily or args.monthly or args.yearly):
    parser.error("Must specify one of --daily, --monthly, or --yearly.")

# Get proper date strings to label backups
today = datetime.date.today()
year = today.strftime('%Y')
month = today.strftime('%m')
day = today.strftime('%d')
year_month_day = today.strftime('%Y%m%d')

def extractWordpressData(site_directory, backup_directory, site):
    sql_file = ''
    database = ''
    database_user = ''
    database_password = ''
    
    # Parse wp-config file for db user/password to conduct a sql dump
    wp_config_file = os.path.join(site_directory, 'wp-config.php')
    if not (os.path.isfile(wp_config_file)):
        if (args.verbose):
            print("Couldn't find wp-config.php file in " + site_directory)
        return ''
    else:
        # TODO: Parse the wp-config.php file instead of parsing text
        wp_config = open(wp_config_file, "r")
        for line in wp_config:
            database_match = re.match('^define\(\'DB_NAME\',\s*\'([^\']*)\'\);$', line)
            if database_match:
                database = database_match.group(1)

            database_user_match = re.match('^define\(\'DB_USER\',\s*\'([^\']*)\'\);$', line)
            if database_user_match:
                database_user = database_user_match.group(1)

            database_password_match = re.match('^define\(\'DB_PASSWORD\',\s*\'([^\']*)\'\);$', line)
            if database_password_match:
                database_password = database_password_match.group(1)

    if not database:
        print("Unable to extract database name")
    if not database_user:
        print("Unable to extract database user")
    if not database_password:
        print("Unable to extract database password")

    if not (database and database_user and database_password):
        return ''
    else:
        sql_file = os.path.join(backup_directory, site + "-" + year_month_day + ".sql")
        mysql_dump_command = "/usr/bin/mysqldump -u " + database_user + " -p\'" + database_password + "\' " + database + " > " + sql_file
        subprocess.run(mysql_dump_command, shell=True)
                
    return sql_file

def sendToS3(tar_file, site):
    s3 = boto3.client('s3')

    # Set frequency and upload path
    frequency = 'daily' if args.daily else 'monthly' if args.monthly else 'yearly'
    upload_target = os.path.join(site, frequency, os.path.basename(tar_file))

    # Identify what bucket/sub-bucket to store backup file
    # 1.) Use specified s3 bucket if supplied
    # 2.) If no s3 bucket specified, attempt to match site name to bucket name
    # 3.) Default to DEFAULT_BUCKET if there is no match
    bucket = args.bucket
    if not bucket:
        response = s3.list_buckets()
        buckets = [bucket['Name'] for bucket in response['Buckets']]
        if (site in buckets):
            bucket = site
            upload_target = os.path.join(frequency, os.path.basename(tar_file))
        else:
            bucket = DEFAULT_BUCKET

    if (args.verbose):
        print("S3 bucket: " + bucket + " selected")

    s3.upload_file(tar_file, bucket, upload_target)
    if (args.verbose):
        print("Uploaded " + tar_file + " to s3://" + bucket + "/" + upload_target)

    # Tag the file with the right frequency tag: daily/monthly/annually
    tag_key = 'frequency'
    tag_value = frequency
    key = upload_target
    s3.put_object_tagging(
        Bucket=bucket,
        Key=key,
        Tagging={
            'TagSet': [
                {
                    'Key': tag_key,
                    'Value': tag_value,
                },
            ]
        }
    )
    if (args.verbose):
        print("Tagged s3://" + bucket + "/" + upload_target + " with " + tag_key + ":" + tag_value)

def backupSite(backup_directory, root_directory, site):
    site_directory = os.path.join(root_directory, site)
    if (args.verbose):
        print("Backing up website: '" + site + "'")

    backup_site_directory = os.path.join(backup_directory, site)
    # Start clean by removing the backup directory if it already exists
    if (os.path.exists(backup_site_directory)):
        shutil.rmtree(backup_site_directory)

    os.makedirs(backup_site_directory)

    # Copy all site files
    distutils.dir_util.copy_tree(site_directory, backup_site_directory)
    if (args.verbose):
        print(site_directory + " copied into " + backup_site_directory)
    
    # Extract database data if it exists
    database_file = extractWordpressData(site_directory, backup_directory, site)
    database_file_name = os.path.basename(database_file)
    if (args.verbose):
        if (os.path.isfile(database_file)):
            print(database_file + " created")
        else:
            print("Database file not created")
            
    # Gzip site files along with db backup
    tar_file = os.path.join(backup_directory, site + "-" + year_month_day + ".tar.gz")
    if (args.verbose):
        print("Creating " + tar_file)

    with tarfile.open(tar_file, "w:gz") as tar:
        tar.add(backup_site_directory, arcname=site)
        if (database_file):
            tar.add(database_file, arcname=database_file_name)
        tar.close()
    
    # Send to AWS S3 to be stored in correct periodic folder (daily/monthly/yearly)
    if (args.verbose):
        print("Uploading to s3...")

    sendToS3(tar_file, site)
    
    # Cleanup temp location
    if (args.cleanup):
        shutil.rmtree(backup_site_directory)
        for file in [database_file, tar_file]:
            if (os.path.isfile(file)):
                os.remove(file)

def main():
    # List out all directories in the root directory to get all sites
    root_directory = args.rootdirectory or '/var/www'
    sites = [name for name in os.listdir(root_directory) if os.path.isdir(os.path.join(root_directory, name))]

    # Exit early if site specified is not found
    if (args.site and args.site not in sites):
        sys.exit("Website '" + args.site + "' not found in " + root_directory)

    # Stage backup in a temp location (default: /home/dchang/backups/)
    backup_directory = args.backupdirectory or '/home/dchang/backups'
    if not (os.path.exists(backup_directory)):
        os.makedirs(backup_directory)

    # If a site is specified, only backup the specified site
    if (args.site):
        backupSite(backup_directory, root_directory, args.site)
    # Otherwise backup all sites in the root directory
    else:
        for site in sites:
            backupSite(backup_directory, root_directory, site)

# Execute the main program
if __name__ == "__main__":
    main()
