# Test dynamic inventory
ansible-inventory -i inventories/dev/dynamic-host.yml --graph
# or this depending the path of your inventory file
ansible-inventory -i aws_ec2.yml --graph

# use this to create the roles
ansible-galaxy init roles/nginx
ansible-galaxy init roles/users
ansible-galaxy init roles/docker

# use this run the plays
ansible-playbook -i aws_ec2.yml playbooks/site.yml



Perfect 👍 let’s update your roles/users/tasks/main.yml so it automatically merges baseline users (from defaults) with extra users (from inventory/group_vars/host_vars).

Here’s the top of your tasks file with the new merge step added:

---
# roles/users/tasks/main.yml

# Step 0: Merge default users + extra_users if defined
- name: Merge default users with extra_users
  ansible.builtin.set_fact:
    users: "{{ users + extra_users }}"
  when: extra_users is defined
  tags: always

# Step 1: Derive helper lists
- name: Derive helper lists: all_groups and combined sudo groups
  ansible.builtin.set_fact:
    all_groups: "{{ users | map(attribute='group') | list | unique }}"
    sudo_groups_from_users: "{{ users | selectattr('sudo','defined') | selectattr('sudo') | map(attribute='group') | list | unique }}"
    sudo_groups_combined: "{{ (sudo_groups | default([])) | union(sudo_groups_from_users) | list }}"
  tags: always

✅ How this works

users → baseline list from roles/users/defaults/main.yml.

extra_users → optional list you define in inventory (group_vars/dev.yml, group_vars/prod.yml, etc.).

If extra_users exists, the role merges it into users.

The rest of your tasks (create groups, create users, deploy ssh keys, etc.) continue unchanged.

Example usage

defaults/main.yml (baseline):

users:
  - name: admin
    group: admin
    ssh_key: "{{ lookup('amazon.aws.ssm_parameter', '/users/admin/ssh_key', region='us-east-1', default='') }}"
    sudo: true


inventory/group_vars/dev.yml (extra dev-only users):

extra_users:
  - name: alice
    group: devs
    ssh_key: "ssh-rsa AAAAB3Nz... alice@laptop"
    sudo: true

  - name: bob
    group: ops
    ssh_key: "ssh-rsa AAAAB3Nz... bob@laptop"
    sudo: false


inventory/group_vars/prod.yml (extra prod-only users):

extra_users:
  - name: charlie
    group: devs
    ssh_key: "ssh-rsa AAAAB3Nz... charlie@laptop"
    sudo: false


👉 This way:

You don’t duplicate baseline users in each environment.

You just add extra_users where needed.

The role always works with a single merged users list internally.



# Some eg.s. of ansible jobs
Here are some configurations you can manage with Ansible Tower, along with practice playbook ideas for each:

🔹 1. User and Access Management

Configs Managed: SSH users, groups, sudo privileges, SSH keys.

Practice Playbooks:

Create a user with SSH key and sudo access.

Manage /etc/sudoers for specific groups.

Rotate SSH keys across all servers.

🔹 2. Package and Service Management

Configs Managed: Installing, updating, removing software packages; managing services (start, stop, enable).

Practice Playbooks:

Install and configure nginx or httpd.

Ensure docker is installed and running.

Apply OS patches automatically.

🔹 3. Configuration Files & Templates

Configs Managed: /etc/hosts, app config files, templated settings (Jinja2).

Practice Playbooks:

Push a custom motd banner to all servers.

Manage /etc/hosts dynamically with inventory variables.

Template out an nginx.conf or app.properties.

🔹 4. Cloud Infrastructure Management

Configs Managed: AWS, Azure, GCP resources.

Practice Playbooks:

Launch an EC2 instance with security groups.

Create an S3 bucket and upload files.

Manage Route53 DNS records.

🔹 5. Application Deployment

Configs Managed: App code, dependencies, configs, restarts.

Practice Playbooks:

Deploy a simple Python Flask app with gunicorn + nginx.

Deploy a Node.js app with PM2.

Roll out updates using rolling updates strategy.

🔹 6. Database Configuration

Configs Managed: MySQL/Postgres users, schemas, backups.

Practice Playbooks:

Install and secure MySQL (set root password, create users).

Deploy PostgreSQL and create databases.

Automate DB backups with cron.

🔹 7. Monitoring & Logging

Configs Managed: Prometheus node exporter, Grafana agent, log rotation.

Practice Playbooks:

Install and configure Node Exporter.

Deploy Grafana dashboards from JSON.

Configure rsyslog or logrotate.

🔹 8. Security Hardening

Configs Managed: Firewall rules, SELinux, fail2ban, auditd.

Practice Playbooks:

Configure ufw or firewalld rules.

Deploy fail2ban with a custom jail.

Apply CIS benchmark checks (basic subset).

🔹 9. Container & Kubernetes

Configs Managed: Docker, Kubernetes manifests, Helm charts.

Practice Playbooks:

Install Docker and run a container.

Deploy a Kubernetes manifest (using k8s module).

Install Helm and deploy a chart.

🔹 10. CI/CD Integration (Tower strength)

Configs Managed: Triggering pipelines, running infra playbooks after commits.

Practice Playbooks:

Run Terraform plan/apply via Ansible.

Trigger a Jenkins job with credentials from Tower.

Update a Kubernetes deployment after a Git push.

⚡ Tips for Tower Practice:

Start with small playbooks (user creation, package install).

Create Projects in Tower linked to your Git repo of playbooks.

Use Inventories + Dynamic Inventory (AWS EC2).

Add Credentials for SSH/Cloud.

Create Job Templates for each playbook.

Schedule runs (patching every Sunday, backups daily).

Try Surveys (Tower feature) to make playbooks interactive.


# Ansible tower - Dynamic Inventory
Option A – Use Default EE

Go to Administration → Execution Environments.

If there’s already something like AWX EE or Ansible Automation Platform EE, select that in your job/inventory.

Option B – Create a Custom EE (if nothing exists)

Click Add Execution Environment.

Fill in:

Name: Default EE

Image: quay.io/ansible/awx-ee:latest (official image with AWS modules pre-installed)

Pull: Always pull

Save.

🔹 Step 3: Attach AWS Credential to Inventory Source

Go back to your Inventory → Sources → AWS EC2 Source.

Under Credentials, select your AWS Access credential.

Under Execution Environment, select Default EE (or whichever you made).

Save → Sync.

👉 At this point, AWX should be able to connect to AWS, pull EC2 metadata, and apply your filter:

Key: tag:role

Lookup type: exact

Value: users