#!/bin/bash

# ________________________
# VARIABLES

# vpc
VPC_CIDR="10.0.0.0/16"
VPC_TAG=acit4640-vpc


# public ec2
PUBLIC_EC2_SUBNET_CIDR="10.0.1.0/24"
AZ="us-west-2a"
EC2_KEY_NAME="acit4640-ec2-kp"
EC2_IMAGE="ami-0735c191cf914754d"
EC2_INSTANCE_TYPE="t2.micro"


# private rds 1
PRIVATE_RDS_1_SUBNET_CIDR="10.0.2.0/24"


# private rds 2
PRIVATE_RDS_2_SUBNET_CIDR="10.0.3.0/24"
PRIVATE_RDS_2_AZ="us-west-2b"


# rds
DB_INSTANCE_IDENTIFIER="database-1"
DB_MASTER_USERNAME="admin"
DB_MASTER_PASSWORD="252002252002"
DB_ENGINE="mysql"
DB_ENGINE_VERSION="8.0.28"
DB_INSTANCE_CLASS="db.t3.micro"
DB_STORAGE_TYPE="gp2"
DB_STORAGE_SIZE="20"
rds_sng="rds-sng"


# ________________________
# VPC SETUP

# create vpc
vpc_id=$(aws ec2 create-vpc --cidr-block $VPC_CIDR | yq '.Vpc.VpcId')
echo "VPC ID $vpc_id"

# give the vpc a tag
aws ec2 create-tags --resources $vpc_id --tags Key=Name,Value=$VPC_TAG

# ________________________
# SUBNET SETUP

# create public ec2 subnet
pub_ec2_subnet_id=$(
  aws ec2 create-subnet \
  --cidr-block $PUBLIC_EC2_SUBNET_CIDR \
  --availability-zone $AZ \
  --vpc-id $vpc_id \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=rdc-public-ec2}]' \
  | yq '.Subnet.SubnetId'
)
echo "Subnet ID (public ec2) $pub_ec2_subnet_id"

# auto-assigning public IPv4 address
aws ec2 modify-subnet-attribute --subnet-id $pub_ec2_subnet_id --map-public-ip-on-launch


# create private rds 1 subnet
pri_rds_1_subnet_id=$(
  aws ec2 create-subnet \
  --cidr-block $PRIVATE_RDS_1_SUBNET_CIDR \
  --availability-zone $AZ \
  --vpc-id $vpc_id \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=rdc-private-rds1}]' \
  | yq '.Subnet.SubnetId'
)
echo "Subnet ID (private rds 1): $pri_rds_1_subnet_id"


# create private rds 2 subnet
pri_rds_2_subnet_id=$(
  aws ec2 create-subnet \
  --cidr-block $PRIVATE_RDS_2_SUBNET_CIDR \
  --availability-zone $PRIVATE_RDS_2_AZ \
  --vpc-id $vpc_id \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=rdc-private-rds2}]' \
  | yq '.Subnet.SubnetId'
)
echo "Subnet ID (private rds 2): $pri_rds_2_subnet_id"


# ________________________
# INTERNET GATEWAY SETUP

# create igw
igw_id=$(aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=acit4640-igw}]' \
    | yq '.InternetGateway.InternetGatewayId'
)
echo "Internet Gateway Id: $igw_id"

# attach igw to vpc
aws ec2 attach-internet-gateway \
    --internet-gateway-id $igw_id \
    --vpc-id $vpc_id


# ________________________
# ROUTE TABLE SETUP

# create route table
route_table_id=$(aws ec2 create-route-table \
  --vpc-id $vpc_id \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=acit4640-rt}]' \
  | yq '.RouteTable.RouteTableId'
)
echo "Route Table Id: $route_table_id"

# add route 0.0.0.0/0 to igw
aws ec2 create-route \
  --route-table-id $route_table_id \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $igw_id

# associate public ec2 subnet to route table
assoc_id=$(aws ec2 associate-route-table \
  --subnet-id $pub_ec2_subnet_id \
  --route-table-id $route_table_id \
  | yq '.AssociationId'
)
echo "Association ID: $assoc_id"


# ________________________
# SECURITY GROUP SETUP

# create ec2 security group
ec2_sg_id=$(aws ec2 create-security-group \
  --group-name ec2-sg \
  --description "security group for public ec2" \
  --vpc-id $vpc_id \
  | yq -r '.GroupId'
)
echo "Security Group ID (ec2): $ec2_sg_id"

# add inbound rule for ssh
aws ec2 authorize-security-group-ingress \
  --group-id $ec2_sg_id \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# allow http connection to ec2
aws ec2 authorize-security-group-ingress \
  --group-id $ec2_sg_id \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0



# Create rds security group
rds_sg_id=$(aws ec2 create-security-group \
  --group-name rds-sg \
  --description "Security group for MySQL access from within VPC" \
  --vpc-id $vpc_id \
  | yq -r '.GroupId'
)
echo "Security Group ID (rds): $rds_sg_id"

# Authorize inbound MySQL traffic from within the VPC
aws ec2 authorize-security-group-ingress \
  --group-id $rds_sg_id \
  --protocol tcp \
  --port 3306 \
  --cidr $VPC_CIDR


# ________________________
# EC2 SETUP + KEY PAIR SETUP

# create key pair for ec2
aws ec2 create-key-pair \
  --key-name $EC2_KEY_NAME \
  --key-type ed25519 \
  --query 'KeyMaterial' \
  --output text > $EC2_KEY_NAME.pem

chmod 600 $EC2_KEY_NAME.pem


# create ec2 instance 
echo "Creating EC2 (takes a few min)..."
instance_info=$(aws ec2 run-instances \
    --image-id $EC2_IMAGE \
    --instance-type $EC2_INSTANCE_TYPE \
    --subnet-id $pub_ec2_subnet_id \
    --security-group-ids $ec2_sg_id \
    --key-name $EC2_KEY_NAME \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=acit4640-ec2}]' \
    --query 'Instances[0].{InstanceId:InstanceId, PublicIpAddress:PublicIpAddress}' \
    --output json
)

# save ec2 instance id    
instance_id=$(echo $instance_info | yq -r '.InstanceId')

# wait for instance to reach "running" state and get a public IP address
aws ec2 wait instance-running --instance-ids $instance_id
public_ip=$(aws ec2 describe-instances --instance-ids $instance_id --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

# show how to connect to ec2
echo "SSH Into Your EC2: ssh -i $EC2_KEY_NAME.pem ubuntu@$public_ip #NOTE: if you change ami for the os you may need to change ubuntu"


# ________________________
# RDS SUBNET GROUP

# create subnet group
aws rds create-db-subnet-group \
    --db-subnet-group-name $rds_sng \
    --db-subnet-group-description "subnet group for RDS" \
    --subnet-ids $pri_rds_1_subnet_id $pri_rds_2_subnet_id \
    --region us-west-2

# Create the RDS database instance
database_result=$(aws rds create-db-instance \
  --db-instance-identifier $DB_INSTANCE_IDENTIFIER \
  --db-instance-class $DB_INSTANCE_CLASS \
  --engine $DB_ENGINE \
  --master-username $DB_MASTER_USERNAME \
  --master-user-password $DB_MASTER_PASSWORD \
  --allocated-storage $DB_STORAGE_SIZE \
  --engine-version $DB_ENGINE_VERSION \
  --storage-type $DB_STORAGE_TYPE \
  --no-publicly-accessible \
  --vpc-security-group-ids $rds_sg_id \
  --db-subnet-group-name $rds_sng
)

# wait for rds
echo "Wait for Database to get created (it will take a bit of time...)"
aws rds wait \
    db-instance-available \
    --db-instance-identifier $DB_INSTANCE_IDENTIFIER


# _________________________
# Write RDS endpoint data to a file

copy_application=$(scp -i ./$EC2_KEY_NAME.pem ./application_script.sh ubuntu@$public_ip:~/)

# get rds endpoint
rds_endpoint=$(aws rds describe-db-instances | yq ".DBInstances.[].Endpoint.Address") 

# put variables into a env.sh file
cat > env.sh <<EOL
endpoint=$rds_endpoint
DOMAIN=$public_ip
EOL

copy_endpoint_to_ec2=$( scp -o StrictHostKeyChecking=no -i ./$EC2_KEY_NAME.pem ./env.sh ubuntu@$public_ip:~/)


# ________________________
# SHOW HOW TO SSH INTO EC2

echo "*************** Infrastructure Done! Run these last commands ***************"

# show how to ssh into ec2
echo "[1] ssh -i $EC2_KEY_NAME.pem ubuntu@$public_ip"
echo "[1] sudo ./application_script.sh"


# ________________________
# DESCRIBE INFRASTRUCTURE

echo ""
echo "Describe Inrrastructure:"
aws ec2 describe-vpcs