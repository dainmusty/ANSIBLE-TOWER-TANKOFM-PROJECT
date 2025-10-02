playbooks/
├── site.yml         # Master playbook (calls all roles)
├── web.yml          # Nginx + Docker
├── db.yml           # MySQL
└── users.yml        # User management

ansible-playbook -i inventories/dev/dynamic-host.yml playbooks/users.yml


ansible-playbook -i aws_ec2.yml playbooks/users.yml
ansible-playbook -i aws_ec2.yml playbooks/nginx.yml

ansible-playbook -i aws_ec2.yml playbooks/docker.yml

ansible-playbook -i inventories/aws_ec2.yml playbooks/site.yml

