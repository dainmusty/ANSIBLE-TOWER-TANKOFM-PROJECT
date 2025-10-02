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