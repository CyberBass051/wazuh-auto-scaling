#!/usr/bin/env python3

import os
import logging
from logging.handlers import RotatingFileHandler
import tempfile
import argparse
import re
import json
import sys

LOG_DIR = "logs"
os.makedirs(LOG_DIR, exist_ok=True)
LOG_FILE = os.path.join(LOG_DIR, "settings_checker.log")

def parse_arguments():
    parser = argparse.ArgumentParser(description="Check settings file")
    parser.add_argument("-f", "--files",  nargs='+', help="Settings file to check", required=True)
    parser.add_argument("--dry-run", help="Don't actually change anything", action="store_true")
    return parser.parse_args()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        RotatingFileHandler(LOG_FILE, maxBytes=1024*1024*10, backupCount=5),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

def atomic_write(filename, content):
    # Create a temporary file
    temp_dir = os.path.dirname(filename) or '.'
    with tempfile.NamedTemporaryFile(mode='w', dir=temp_dir, delete=False, suffix='.tmp') as tmp_file:
        tmp_file.write(content)
        tmp_filename = tmp_file.name

    # Atomically replace the original file
    os.replace(tmp_filename, filename)

def check_settings(files: str, dry_run: bool = False) -> None:
    
    logger.info("Checking settings file: %s", files)
    json_report = {
        "files": [],
        "summary": {
            "total_files": 0,
            "files_with_issues": 0,
            "issues": []
        }
    }
    try:
        for file in files:
            json_report["files"].append({"filename": file, "status": "checked"})
            json_report["summary"]["total_files"] += 1
            if os.path.basename(file) == 'alb.tf':
                logger.info("Checking alb.tf")
                pattern_to_check = r'(drop_invalid_header_fields\s+=\s+)(true|false)'
                with open(file, 'r') as f:
                    content = f.read()
                    match = re.search(pattern_to_check, content)
                    if not match:
                        json_report["summary"]["issues"].append({"file": file, "issue": "no drop_invalid_header found"})
                        if not dry_run:
                            # Perform the atomic write
                            logger.info("Pattern not found in %s. Adding it.", file)
                            new_content = re.sub(r'(resource "aws_lb" ".*" {)', 
                                             r'\1\n  drop_invalid_header_fields = true\n  enable_deletion_protection = false # Set to true for production!' , content)
                            atomic_write(file, new_content)
                        else:
                            logger.info("Dry run: would add pattern to %s", file)

                    elif match.group(2) == 'false':
                        logger.info("Drop_invalid_header_fields is set to false in %s.", file)
                        json_report["summary"]["issues"].append({"file": file, "issue": "drop_invalid_header set to disabled"})
                        if not dry_run:
                            logger.info("Setting drop_invalid_header_fields to true in %s.", file)
                            new_content = re.sub(pattern_to_check, r'\1true', content)
                            atomic_write(file, new_content)
                        else:
                            logger.info("Dry run: would set drop_invalid_header_fields to true in %s", file)

            elif os.path.basename(file) == 'ec2.tf':
                logger.info("Checking ec2.tf")
                with open(file, 'r') as f:
                    content = f.read()
                    pattern_to_check = r'(metadata_options)(\s+{\s+http_endpoint\s+=\s+")(enabled|disabled)("\s+http_tokens\s+=\s+"required"\s+http_put_response_hop_limit\s+=\s+)(1|\d?)(\s+})'
                    match = re.search(pattern_to_check, content, re.DOTALL)
                    if not match:
                        json_report["summary"]["issues"].append({"file": file, "issue": "No metadata_options found"})
                        if not dry_run:
                            # Perform the atomic write
                            logger.info("Pattern 'metadata_options' not found in %s. Adding it.", file)
                            new_content = re.sub(r'(resource ".*" ".*" {)',
                                             r'\1\n    metadata_options {\n      http_endpoint = "enabled"\n      http_tokens   = "required"\n      http_put_response_hop_limit = 1\n    }\n' , content)
                            atomic_write(file, new_content)
                        else:
                            new_content = re.sub(r'(resource ".*" ".*" {)',
                                             r'\1\n    metadata_options {\n    http_endpoint = "enabled"\n    http_tokens   = "required"\n    http_put_response_hop_limit = 1\n    }\n' , content)
                            logger.info("Dry run: would add\n%s\nto %s", new_content, file)
                    elif match.group(3) == 'disabled':
                        if not dry_run:
                            json_report["summary"]["issues"].append({"file": file, "issue": "http_endpoint is set to disabled"})
                            logger.info("metadata_option's http_endpoint is set to disabled. Setting it to 'enabled'")
                            new_content = re.sub(pattern_to_check, r'\1\2enabled\4\5 1\6', content)
                            atomic_write(file, new_content)
                        else:
                            new_content = re.sub(pattern_to_check, r'\1\2enabled\4\5 1\6', content)
                            logger.info("Dry run: would change\n%s\nto\n%s", content, new_content)
                    elif match.group(5) != '1':
                        json_report["summary"]["issues"].append({"file": file, "issue": "http_put_response_hop_limit is not set to 1"})
                        if not dry_run:
                            logger.info("metadata_option's http_put_response_hop_limit is not set to 1. Setting it to 1")
                            new_content = re.sub(pattern_to_check, r'\1\2\3\4\5 1\6', content)
                            atomic_write(file, new_content)
                        else:
                            new_content = re.sub(pattern_to_check, r'\1\2\3\5 1\6', content)
                            logger.info("Dry run: would change\n%s\nto\n%s", content, new_content)
            elif os.path.basename(file) == 'sg.tf':
                logger.info("Checking sg.tf")
                with open(file, 'r') as f:
                    content = f.read()
                    pattern_to_check = r'(resource\s+"aws_vpc_security_group_egress_rule)(\s+.*)(cidr_ipv4\s*=\s*)("0.0.0.0/0")'
                    match = re.search(pattern_to_check, content, re.DOTALL)
                    if not match:
                        logger.warning("No app egress rule found in %s", file)
                    elif match.group(4) == "0.0.0.0/0":
                        json_report["summary"]["issues"].append({"file": file, "issue": "app egress rule allows all"})
                        logger.warning("Security group egress rule allows all. Please restrict it to a proxy server.")
                        if not dry_run:
                            logger.info("Restricting app egress rule to localhost")
                            new_content = re.sub(pattern_to_check, r'\1\2\3 = "127.0.0.1/32"', content)
                            atomic_write(file, new_content)
                        else:
                            logger.info("Dry run: would change egress rule to localhost")
            else: 
                logger.warning("No checks implemented for %s", file)
                json_report["summary"]["issues"].append({"file": file, "issue": "No checks implemented"})

        with open('report.json', 'w') as f:
            logger.info("Writing report to report.json")
            json.dump(json_report, f, indent=4)

    except FileNotFoundError:
        logger.error("File %s not found.", file)
    except Exception as e:
        logger.error("An error occurred: %s", str(e))
              
def main():
    print("Checking settings file...")
    args = parse_arguments()
    check_settings(args.files, args.dry_run)

if __name__ == "__main__":
    main()


