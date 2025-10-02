---
- name: Ensure groups exist
  ansible.builtin.group:
    name: "{{ item.group }}"
    state: present
  loop: "{{ users }}"

- name: Ensure users exist
  ansible.builtin.user:
    name: "{{ item.name }}"
    group: "{{ item.group }}"
    shell: /bin/bash
    create_home: yes
  loop: "{{ users }}"

- name: Deploy authorized keys (only if ssh_key is defined and not empty)
  ansible.builtin.authorized_key:
    user: "{{ item.name }}"
    state: present
    key: "{{ item.ssh_key }}"
  loop: "{{ users }}"
  when: item.ssh_key is defined and item.ssh_key | length > 0

- name: Deploy MOTD template
  ansible.builtin.template:
    src: motd.j2
    dest: /etc/motd


# needs to be worked on; error has to do with expected string.
# - name: Add users to sudoers (only if sudo: true)
#   ansible.builtin.copy:
#     dest: "/etc/sudoers.d/{{ item.name }}"
#     content: "{{ item.name }} ALL=(ALL) NOPASSWD:ALL\n"
#     mode: '0440'
#   when: item.sudo is defined and item.sudo
#   loop: "{{ users }}"

roles/
  users/
    defaults/
      main.yml        # user lists (safe defaults, override in inventory/Tower)
    vars/
      main.yml        # constants like sudoers_path, motd_file
    tasks/
      main.yml        # actual user/group/ssh/sudo logic
    templates/
      motd.j2


# Ansible Role: users

This role manages system users, groups, SSH keys, and sudo privileges.

## Features
- Creates groups and users with home directories and shells.
- Deploys SSH keys (supports single `ssh_key` or list `ssh_keys`).
- Rotates SSH keys (removes `old_ssh_key` if defined).
- Manages sudo privileges:
  - Group-level sudo rules in `/etc/sudoers.d`.
  - Per-user sudo rules (when `sudo: true` is set).
- Deploys a managed MOTD banner.

## Role Variables

### defaults/main.yml
```yaml
users:
  - name: alice
    group: devs
    ssh_key: "ssh-rsa AAAAB3Nz... alice"
    sudo: true
  - name: bob
    group: ops
    ssh_keys:
      - "ssh-rsa AAAAB3Nz... bob@laptop1"
      - "ssh-rsa AAAAB3Nz... bob@laptop2"
    old_ssh_key: "ssh-rsa AAAAB3Nz... oldbob"
    sudo: false

sudo_groups:
  - devs


# tasks to handle Group creation

User creation

Authorized keys

Sudoers handling (per-user)

MOTD
---
# roles/users/tasks/main.yml
# Role expects a `users` list (best defined in defaults/main.yml).
# Also optional variables:
# - sudo_groups: list of group names that should get sudo (defaults to []).
# - sudoers_path: path for sudoers fragments (defaults to /etc/sudoers.d).


---
# roles/users/tasks/main.yml

# Step 0: Merge baseline + extra users
- name: Merge default users with extra_users
  ansible.builtin.set_fact:
    users: "{{ users + extra_users }}"
  when: extra_users is defined
  tags: always

# Step 0.1: Merge baseline + extra sudo groups
- name: Merge default sudo_groups with extra_sudo_groups
  ansible.builtin.set_fact:
    sudo_groups: "{{ sudo_groups | default([]) + extra_sudo_groups }}"
  when: extra_sudo_groups is defined
  tags: always

# Step 1: Derive helper lists
- name: Derive helper lists: all_groups and combined sudo groups
  ansible.builtin.set_fact:
    all_groups: >-
      {{ users | map(attribute='group') | list | unique }}
    sudo_groups_from_users: >-
      {{ users | selectattr('sudo','defined') | selectattr('sudo') | map(attribute='group') | list | unique }}
    sudo_groups_combined: >-
      {{ (sudo_groups | default([])) | union(sudo_groups_from_users) | list }}
  tags: always





- name: Ensure sudoers.d directory exists
  ansible.builtin.file:
    path: "{{ sudoers_path | default('/etc/sudoers.d') }}"
    state: directory
    owner: root
    group: root
    mode: '0750'
  tags: sudo

- name: Ensure groups exist
  ansible.builtin.group:
    name: "{{ item }}"
    state: present
  loop: "{{ all_groups }}"
  when: all_groups is defined and all_groups | length > 0
  tags: groups

- name: Ensure users exist
  ansible.builtin.user:
    name: "{{ item.name }}"
    group: "{{ item.group }}"
    shell: "{{ item.shell | default('/bin/bash') }}"
    create_home: yes
    state: present
    comment: "{{ item.comment | default(omit) }}"
  loop: "{{ users }}"
  tags: users

- name: Ensure each user's .ssh directory exists
  ansible.builtin.file:
    path: "{{ (item.home | default('/home/' ~ item.name)) + '/.ssh' }}"
    state: directory
    owner: "{{ item.name }}"
    group: "{{ item.group }}"
    mode: '0700'
  loop: "{{ users }}"
  tags: ssh

- name: Remove old SSH key for user (if old_ssh_key defined)
  ansible.builtin.authorized_key:
    user: "{{ item.name }}"
    key: "{{ item.old_ssh_key }}"
    state: absent
    manage_dir: yes
  loop: "{{ users }}"
  when: item.old_ssh_key is defined and item.old_ssh_key | length > 0
  tags: ssh

- name: Add SSH keys from per-user ssh_keys lists
  ansible.builtin.authorized_key:
    user: "{{ item.0.name }}"
    key: "{{ item.1 }}"
    state: present
    manage_dir: yes
  loop: "{{ lookup('subelements', users, 'ssh_keys', wantlist=True) }}"
  when: users is defined
  tags: ssh

- name: Add single ssh_key entry for users (when ssh_key provided)
  ansible.builtin.authorized_key:
    user: "{{ item.name }}"
    key: "{{ item.ssh_key }}"
    state: present
    manage_dir: yes
  loop: "{{ users }}"
  when: item.ssh_key is defined and (item.ssh_keys is not defined)
  tags: ssh

- name: Ensure authorized_keys file permissions are correct
  ansible.builtin.file:
    path: "{{ (item.home | default('/home/' ~ item.name)) + '/.ssh/authorized_keys' }}"
    owner: "{{ item.name }}"
    group: "{{ item.group }}"
    mode: '0600'
    state: file
  loop: "{{ users }}"
  when: (item.ssh_key is defined) or (item.ssh_keys is defined) or (item.old_ssh_key is defined)
  tags: ssh

- name: Create group-level sudoers entries (in /etc/sudoers.d)
  ansible.builtin.copy:
    dest: "{{ sudoers_path | default('/etc/sudoers.d') }}/{{ item }}"
    content: "%{{ item }} ALL=(ALL) NOPASSWD:ALL\n"
    owner: root
    group: root
    mode: '0440'
    validate: 'visudo -cf %s'
  loop: "{{ sudo_groups_combined }}"
  when: sudo_groups_combined is defined and sudo_groups_combined | length > 0
  tags: sudo

- name: Create per-user sudoers entries for users with sudo: true
  ansible.builtin.copy:
    dest: "{{ sudoers_path | default('/etc/sudoers.d') }}/{{ item.name }}"
    content: |
      {{ item.name }} ALL=(ALL) NOPASSWD:ALL
    owner: root
    group: root
    mode: '0440'
    validate: 'visudo -cf %s'
  loop: "{{ users }}"
  when: item.sudo | default(false)
  tags: sudo


- name: Summary (debug)
  ansible.builtin.debug:
    msg: "Ensured {{ users | length }} users, {{ all_groups | length }} groups, {{ sudo_groups_combined | length }} sudo groups."
  tags: always


# old task( worked)
---
- name: Ensure groups exist
  ansible.builtin.group:
    name: "{{ item.group }}"
    state: present
  loop: "{{ users }}"

- name: Ensure users exist
  ansible.builtin.user:
    name: "{{ item.name }}"
    group: "{{ item.group }}"
    shell: /bin/bash
    create_home: yes
  loop: "{{ users }}"

- name: Deploy authorized keys (only if ssh_key is defined and not empty)
  ansible.builtin.authorized_key:
    user: "{{ item.name }}"
    state: present
    key: "{{ item.ssh_key }}"
  loop: "{{ users }}"
  when: item.ssh_key is defined and item.ssh_key | length > 0

- name: Deploy MOTD template
  ansible.builtin.template:
    src: motd.j2
    dest: /etc/motd


~
~
~
~