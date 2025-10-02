# install docker on al23
---
- name: Install dependencies for Docker on Amazon Linux 2023
  ansible.builtin.yum:
    name:
      - yum-utils
      - device-mapper-persistent-data
      - lvm2
      - ca-certificates
    state: present

- name: Add Docker repository
  ansible.builtin.yum_repository:
    name: docker
    description: Docker CE Stable - AL2023
    baseurl: https://download.docker.com/linux/centos/8/x86_64/stable/
    gpgcheck: yes
    gpgkey: https://download.docker.com/linux/centos/gpg
    enabled: yes

- name: Install Docker on AL2023
  ansible.builtin.yum:
    name:
      - docker
      - containerd
    state: present

- name: Ensure Docker service is running
  ansible.builtin.service:
    name: docker
    state: started
    enabled: yes

- name: Add current user to docker group
  ansible.builtin.user:
    name: "{{ ansible_user_id }}"
    groups: docker
    append: yes
