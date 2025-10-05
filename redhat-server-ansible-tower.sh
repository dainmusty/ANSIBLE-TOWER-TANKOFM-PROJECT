#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to handle errors
error_exit() {
    echo "Error: $1"
    exit 1
}

# Variables
VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET1_CIDR="10.0.1.0/24"
PUBLIC_SUBNET2_CIDR="10.0.2.0/24"
PRIVATE_SUBNET1_CIDR="10.0.3.0/24"
PRIVATE_SUBNET2_CIDR="10.0.4.0/24"
REGION="us-east-1"
AMI_IDS=("ami-0b09ffb6d8b58ca91" "ami-02a53b0d62d37a757" "ami-04f77c9cd94746b09" "ami-0dfc569a8686b9320" "ami-04b4f1a9cf54c11d0")
AMI_NAMES=("AL2023" "AL2" "Windows" "RedHat" "ubuntu")
INSTANCE_TYPES=("t2.micro" "t2.micro" "t2.micro" "t3.large" "t2.micro")
KEY_NAME="your-key-pair-name"  # Replace with your actual key pair name
TAG_NAME="env or company-name"  # Replace with your desired tag name
SSM_ROLE_NAME="your instance-profile-name"  # Replace with your actual IAM instance profile name
PUBLIC_INSTANCE_COUNTS=(0 0 0 1 0)
PRIVATE_INSTANCE_COUNTS=(0 0 0 0 0)

# Volume Configuration
ROOT_VOLUME_SIZE=50     # Root volume size, change to 50+G when installing Ansible Tower
VOLUME_SIZE=1           # Additional EBS volume size
VOLUME_TYPE="gp3"
DELETE_ON_TERMINATION=true

# Validate user_data.sh existence
if [[ ! -f "user_data.sh" ]]; then
  error_exit "user_data.sh not found in the current directory!"
fi

# Create VPC
echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$TAG_NAME}]" \
  --query "Vpc.VpcId" --output text) || error_exit "Failed to create VPC"
echo "VPC Created: $VPC_ID"

aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames "{\"Value\":true}" || error_exit "Failed to enable DNS hostnames"

# Internet Gateway
echo "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$TAG_NAME}]" \
  --query "InternetGateway.InternetGatewayId" --output text) || error_exit "Failed to create IGW"
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID || error_exit "Failed to attach IGW"
echo "Internet Gateway Attached: $IGW_ID"

# Subnets
echo "Creating Subnets..."
PUBLIC_SUBNET1_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUBLIC_SUBNET1_CIDR --availability-zone ${REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$TAG_NAME-Public1}]" \
  --query "Subnet.SubnetId" --output text) || error_exit "Failed to create Public Subnet 1"
PUBLIC_SUBNET2_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUBLIC_SUBNET2_CIDR --availability-zone ${REGION}b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$TAG_NAME-Public2}]" \
  --query "Subnet.SubnetId" --output text) || error_exit "Failed to create Public Subnet 2"

PRIVATE_SUBNET1_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PRIVATE_SUBNET1_CIDR --availability-zone ${REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$TAG_NAME-Private1}]" \
  --query "Subnet.SubnetId" --output text) || error_exit "Failed to create Private Subnet 1"
PRIVATE_SUBNET2_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PRIVATE_SUBNET2_CIDR --availability-zone ${REGION}b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$TAG_NAME-Private2}]" \
  --query "Subnet.SubnetId" --output text) || error_exit "Failed to create Private Subnet 2"

# Route Table
echo "Creating Route Table..."
ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$TAG_NAME-PublicRouteTable}]" \
  --query "RouteTable.RouteTableId" --output text) || error_exit "Failed to create Route Table"
aws ec2 create-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID || error_exit "Failed to create route"
aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_ID --subnet-id $PUBLIC_SUBNET1_ID || error_exit "Failed to associate RT to Public Subnet 1"
aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_ID --subnet-id $PUBLIC_SUBNET2_ID || error_exit "Failed to associate RT to Public Subnet 2"

# Security Groups
echo "Creating Security Groups..."
PUBLIC_SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name ${TAG_NAME}-pub-SG --description "Public SG" --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${TAG_NAME}-pub-SG}]" \
  --query "GroupId" --output text) || error_exit "Failed to create Public SG"
aws ec2 authorize-security-group-ingress --group-id $PUBLIC_SECURITY_GROUP_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $PUBLIC_SECURITY_GROUP_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $PUBLIC_SECURITY_GROUP_ID --protocol tcp --port 443 --cidr 0.0.0.0/0

PRIVATE_SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name ${TAG_NAME}-pri-SG --description "Private SG" --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${TAG_NAME}-pri-SG}]" \
  --query "GroupId" --output text) || error_exit "Failed to create Private SG"
aws ec2 authorize-security-group-ingress --group-id $PRIVATE_SECURITY_GROUP_ID --protocol tcp --port 22 --source-group $PUBLIC_SECURITY_GROUP_ID

# Launch EC2 Instances (Public)
echo "Launching EC2 Instances in Public Subnet..."
for ((i=0; i<${#PUBLIC_INSTANCE_COUNTS[@]}; i++)); do
  for ((j=1; j<=${PUBLIC_INSTANCE_COUNTS[i]}; j++)); do
    INSTANCE_NAME="${TAG_NAME}-${AMI_NAMES[i]}-pub-$j"
    aws ec2 run-instances \
      --image-id ${AMI_IDS[i]} \
      --instance-type ${INSTANCE_TYPES[i]} \
      --key-name $KEY_NAME \
      --security-group-ids $PUBLIC_SECURITY_GROUP_ID \
      --subnet-id $PUBLIC_SUBNET1_ID \
      --associate-public-ip-address \
      --iam-instance-profile Name=$SSM_ROLE_NAME \
      --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$ROOT_VOLUME_SIZE,\"VolumeType\":\"$VOLUME_TYPE\",\"DeleteOnTermination\":$DELETE_ON_TERMINATION}},{\"DeviceName\":\"/dev/sdf\",\"Ebs\":{\"VolumeSize\":$VOLUME_SIZE,\"VolumeType\":\"$VOLUME_TYPE\",\"DeleteOnTermination\":$DELETE_ON_TERMINATION}}]" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
      --user-data file://user_data.sh || error_exit "Failed to launch public EC2 instance $INSTANCE_NAME"
    echo "Launched: $INSTANCE_NAME"
  done
done

# Launch EC2 Instances (Private)
echo "Launching EC2 Instances in Private Subnet..."
for ((i=0; i<${#PRIVATE_INSTANCE_COUNTS[@]}; i++)); do
  for ((j=1; j<=${PRIVATE_INSTANCE_COUNTS[i]}; j++)); do
    INSTANCE_NAME="${TAG_NAME}-${AMI_NAMES[i]}-pri-$j"
    aws ec2 run-instances \
      --image-id ${AMI_IDS[i]} \
      --instance-type ${INSTANCE_TYPES[i]} \
      --key-name $KEY_NAME \
      --security-group-ids $PRIVATE_SECURITY_GROUP_ID \
      --subnet-id $PRIVATE_SUBNET1_ID \
      --iam-instance-profile Name=$SSM_ROLE_NAME \
      --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$ROOT_VOLUME_SIZE,\"VolumeType\":\"$VOLUME_TYPE\",\"DeleteOnTermination\":$DELETE_ON_TERMINATION}},{\"DeviceName\":\"/dev/sdf\",\"Ebs\":{\"VolumeSize\":$VOLUME_SIZE,\"VolumeType\":\"$VOLUME_TYPE\",\"DeleteOnTermination\":$DELETE_ON_TERMINATION}}]" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
      --user-data file://user_data.sh || error_exit "Failed to launch private EC2 instance $INSTANCE_NAME"
    echo "Launched: $INSTANCE_NAME"
  done
done

# Final Output
echo "Setup Complete!"
echo "VPC ID: $VPC_ID"
echo "Public Subnet 1 ID: $PUBLIC_SUBNET1_ID"
echo "Private Subnet 1 ID: $PRIVATE_SUBNET1_ID"