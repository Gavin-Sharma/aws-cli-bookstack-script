# Setting Up BookStack on AWS

This repository contains scripts to set up a BookStack instance on AWS. The infrastructure is created using the AWS CLI.

## Prerequisites

- AWS CLI installed on your development environment
- An AWS account with permissions to create the resources e.g. vpc, ec2, rds, sg, subnet, etc

## Infrastructure and Application Setup

1. `git clone https://github.com/Gavin-Sharma/aws-cli-bookstack-script.git`
2. `cd aws-cli-bookstack-script`
3. `./infrastructure_script.sh`
4. you will get a prompt on how to ssh into your ec2 (type yes if you get a pop up from aws)
5. `sudo ./application_script.sh`

## Clean Up

Be aware before running it will clean all your subnets, vpc, ec2, sg, igw, etc 
`./cleanup_script.sh`
