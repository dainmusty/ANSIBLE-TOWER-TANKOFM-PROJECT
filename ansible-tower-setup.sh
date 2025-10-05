#!/bin/bash

# Variables
SSM_PARAMETER_NAME="your-ssm-parameter-name for Ansible Tower password"   # SSM Parameter Name
REDHAT_USERNAME="your email address or username"  # Red Hat Account Username
S3_BUCKET="your-s3-bucket-name"  # S3 Bucket Name
TOWER_ARCHIVE="ansible-automation-platform-setup-bundle-2.4-1-x86_64.tar.gz"
TOWER_FOLDER="/root/ansible-automation-platform-setup-bundle-2.4-1-x86_64"
INVENTORY_FILE="$TOWER_FOLDER/inventory"
INSTALLER_SOURCE="s3://$S3_BUCKET/$TOWER_ARCHIVE"  # S3 Path Variable

# Ensure AWS CLI is in the PATH
export PATH=/usr/local/bin:$PATH

# Install AWS CLI if not installed
if ! command -v aws &> /dev/null; then
  echo "Installing AWS CLI..."
  sudo yum install unzip -y
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  sudo rm -rf aws
  unzip -o awscliv2.zip
  sudo ./aws/install
  /usr/local/bin/aws --version  # Directly added here to verify installation
  export PATH=/usr/local/bin:$PATH
  if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI installation failed!"
    exit 1
  fi
else
  echo "AWS CLI already installed. Skipping..."
fi

# Register with Red Hat Subscription Manager
REGISTER_PASSWORD=$(aws ssm get-parameter --name "$SSM_PARAMETER_NAME" --query "Parameter.Value" --output text --with-decryption)
if sudo subscription-manager register --username "$REDHAT_USERNAME" --password "$REGISTER_PASSWORD"; then
  echo "Red Hat registration successful."
else
  echo "Instance already registered or failed to register."
fi

# Update system packages
echo "Updating system packages..."
sudo yum update -y

# Set hostname
echo "Setting hostname..."
sudo hostnamectl set-hostname ansible
echo "127.0.0.1 ansible.local localhost.localdomain" | sudo tee -a /etc/hosts

# **Download Ansible Tower installer from S3 (Using Variable for Source)**
echo "Downloading Ansible Tower installer from S3..."
aws s3 cp "$INSTALLER_SOURCE" /root/
if [ ! -f "/root/$TOWER_ARCHIVE" ]; then
  echo "Error: Failed to download Ansible Tower archive from S3!"
  exit 1
fi

# Extract Ansible Tower installer
echo "Extracting Ansible Tower archive..."
tar -xzf "/root/$TOWER_ARCHIVE" -C /root/

# Modify inventory file
ADMIN_PASSWORD=$(aws ssm get-parameter --name "$SSM_PARAMETER_NAME" --query "Parameter.Value" --output text --with-decryption)

if [ -f "$INVENTORY_FILE" ]; then
  echo "Configuring inventory file..."
  sudo sed -i "s|admin_password=.*|admin_password='$ADMIN_PASSWORD'|" "$INVENTORY_FILE"
  sudo sed -i "s|pg_password=.*|pg_password='$ADMIN_PASSWORD'|" "$INVENTORY_FILE"
  sudo sed -i "s|register_username=.*|register_username='$REDHAT_USERNAME'|" "$INVENTORY_FILE"
  sudo sed -i "s|register_password=.*|register_password='$ADMIN_PASSWORD'|" "$INVENTORY_FILE"
  
  echo "[automationcontroller]" | sudo tee -a "$INVENTORY_FILE"
  echo "ansible ansible_connection=local" | sudo tee -a "$INVENTORY_FILE"
else
  echo "Error: Inventory file not found!"
  exit 1
fi

# Run Ansible Tower setup
echo "Starting Ansible Tower setup..."
if [ -f "$TOWER_FOLDER/setup.sh" ]; then
  sudo bash "$TOWER_FOLDER/setup.sh" -e required_ram=2048
else
  echo "Error: Ansible Tower setup script not found!"
  exit 1
fi

echo "Ansible Tower setup completed successfully!"


# Steps to install Ansible Tower using this script:
# 1. Create a redhat account and subscribe to the Ansible Automation Platform. # https://developers.redhat.com/

# 2. Create an SSM parameter with the name "/ansible/tower" and the value as the Red Hat Subscription Manager password.

# 3. Create an S3 bucket and upload the Ansible Tower installer archive to the bucket.

# 4. Update the script variables with the appropriate values for SSM_PARAMETER_NAME, REDHAT_USERNAME, S3_BUCKET
# TOWER_ARCHIVE, TOWER_FOLDER, INVENTORY_FILE, and INSTALLER_SOURCE.
# 5. Launch RHEL 9 EC2 instance with at least 4GB RAM, 50G+ EBS Volume and t3 medium and attach an IAM role 
# with permissions to access the SSM parameter and S3 bucket.  #NB: This 2.4 bundle only works with RHEL 9 
# instance so pick a RHEL 9 ami.

# 6. Switch to root and run the script on an EC2 instance with the appropriate IAM role to access the SSM parameter 
# and S3 bucket.

# 7. The script will download the Ansible Tower installer from S3, extract it, configure the inventory 
# file, and run the setup script to install Ansible Tower.

# 8. How to use Ansible | Red Hat Developer
# https://developers.redhat.com/products/ansible/getting-started?success=true&tcWhenSigned=January+1%2C+1970&tcWhenEnds=January+1%2C+1970&tcEndsIn=0&tcDuration=365&tcDownloadFileName=ansible-automation-platform-setup-bundle-2.4-1-x86_64.tar.gz&tcRedirect=5000&tcSrcLink=https%3A%2F%2Fdevelopers.redhat.com%2Fcontent-gateway%2Fcontent%2Forigin%2Ffiles%2Fsha256%2F95%2F95f5bfc00f65be7785098bf196f21e76c3eca54f95b203ba8655c80676f665a7%2Fansible-automation-platform-setup-bundle-2.4-1-x86_64.tar.gz&p=SPMM%3A+Red+Hat+Ansible+Automation+Platform&pv=Ansible+Automation+Platform+2.4&tcDownloadURL=https%3A%2F%2Faccess.cdn.redhat.com%2Fcontent%2Forigin%2Ffiles%2Fsha256%2F95%2F95f5bfc00f65be7785098bf196f21e76c3eca54f95b203ba8655c80676f665a7%2Fansible-automation-platform-setup-bundle-2.4-1-x86_64.tar.gz%3F_auth_%3D1738981610_4bc12cfb4077214f2ad4300b4535ca3e#imnewtoansible

# username: should be admin
# password should be the password you used to register the redhat machine.
# Make sure that your redhat instance has 50+GB of free space on the root volume to allow pulling of container images.