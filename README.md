# how to create Ansible role (dont be inside the roles directory when running the command below,
it creates duplicates)
ansible-galaxy init roles/users
ansible-galaxy init roles/docker
ansible-galaxy init roles/nginx

Next Steps in Tower (AWX)

Create a Project linked to this repo.

Add Inventories (dev, prod) → you can later swap to AWS dynamic inventory.

Add Credentials (SSH keys, AWS credentials).

Create Job Templates for each playbook.

Run jobs and check logs in the Tower UI.

# Install Git on AL2024
sudo dnf update -y
sudo dnf install git -y
git --version
Clone your ansible repo project



# Test dynamic inventory
1. Use the resource editor to tag instances to test your dynamic inventory

2. Based on the dynamic inventory file below, tag all instances with the key-value pair (env:dev) of the main filter () 
---
plugin: aws_ec2
regions:
  - us-east-1     # adjust when needed
filters:
  tag:env: dev
keyed_groups:
  - key: tags.role
    prefix: role
hostnames:
  - private-ip-address
compose:
  ansible_host: private_ip_address

ansible-inventory -i inventories/aws_ec2.yml --graph
# or this depending the path of your inventory file
ansible-inventory -i aws_ec2.yml --graph




# to remove directories 
rm -rf ANSIBLE-TOWER-TANKOFM-PROJECT/
rm is the remove command
-r means recursive (remove subdirectories and their contents)
-f means force (no confirmation prompts)

# use this to create the roles
ansible-galaxy init roles/nginx
ansible-galaxy init roles/users
ansible-galaxy init roles/docker

# use this run the plays
ansible-playbook -i aws_ec2.yml playbooks/site.yml