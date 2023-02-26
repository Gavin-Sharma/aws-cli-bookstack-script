#!/bin/bash

# Specify the AWS region to delete resources in
AWS_REGION="us-west-2"

echo "Deleting all databases..."
for db_id in $(aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier' --output text); do
    aws rds delete-db-instance \
    --db-instance-identifier "$db_id" \
    --skip-final-snapshot \
    --no-delete-automated-backups \
    | aws rds wait db-instance-deleted \
    --db-instance-identifier "$db_id"
done

echo "Deleting all subnet groups..."
for subnet_name in $(aws rds describe-db-subnet-groups --query 'DBSubnetGroups[].DBSubnetGroupName' --output text); do
    aws rds delete-db-subnet-group --db-subnet-group-name "$subnet_name" > /dev/null
done

# Delete all instances
echo "Deleting all instances..."
for instance_id in $(aws ec2 describe-instances --query 'Reservations[].Instances[].InstanceId' --output text); do
    aws ec2 terminate-instances --instance-ids "$instance_id" > /dev/null
done

# Delete all security groups
echo "Deleting all security groups..."
for group_id in $(aws ec2 describe-security-groups --query 'SecurityGroups[].GroupId' --output text); do
    aws ec2 delete-security-group --group-id "$group_id" > /dev/null
done

# Delete all routing tables
echo "Deleting all routing tables..."
for table_id in $(aws ec2 describe-route-tables --query 'RouteTables[].RouteTableId' --output text); do
    aws ec2 delete-route-table --route-table-id "$table_id" > /dev/null
done

# Delete all internet gateways
echo "Deleting all internet gateways..."
for gateway_id in $(aws ec2 describe-internet-gateways --query 'InternetGateways[].InternetGatewayId' --output text); do
    aws ec2 detach-internet-gateway --internet-gateway-id "$gateway_id" --vpc-id "$(aws ec2 describe-internet-gateways --internet-gateway-ids "$gateway_id" --query 'InternetGateways[].Attachments[].VpcId' --output text)" > /dev/null
    aws ec2 delete-internet-gateway --internet-gateway-id "$gateway_id" > /dev/null
done

# Delete all subnets
echo "Deleting all subnets..."
for subnet_id in $(aws ec2 describe-subnets --query 'Subnets[].SubnetId' --output text); do
    aws ec2 delete-subnet --subnet-id "$subnet_id" > /dev/null
done

# Delete all VPCs
echo "Deleting all VPCs..."
for vpc_id in $(aws ec2 describe-vpcs --query 'Vpcs[].VpcId' --output text); do
    aws ec2 delete-vpc --vpc-id "$vpc_id" > /dev/null
done

echo "Deleting key pair..."
aws ec2 delete-key-pair --key-name acit4640-ec2-kp
rm -f ./acit4640-ec2-kp.pem

echo "Done!"