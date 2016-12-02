# Ansible Role: Consul-Agent

This role manages most of the components of [Hashicorp's Consul](https://www.consul.io/), including cluster bootstrapping, coordinating rolling service restarts across groups of hosts, and ACL management.

[![Build Status](https://travis-ci.org/arc-ts/ansible-role-consul-agent.svg?branch=master)](https://travis-ci.org/arc-ts/ansible-role-consul-agent)

**NOTE:** This role has some specific execution requirements, please see the [Usage](#usage) section for more information.



 Index
----------
* [Requirements](#requirements)
* [Dependencies](#dependencies)
* [Usage](#usage)
  * [Understanding the Consul Role](#understanding-the-consul-role)
  * [Bootstrapping and Security Auto-Configuration](#bootstrapping-and-security-auto-configuration)
    * [Gossip Encryption](#gossip-encryption)
    * [RPC Encryption](#rpc-encryption)
    * [ACL Master Token](#acl-master-token)
  * [ACLs](#acls)
  * [Service Restarts](#service-restarts)
* [Role Variables](#role-variables)
  * [Execution Control and Security](#execution-control-and-security)
  * [Download and Versioning](#download-and-versioning)
  * [User and Directories Config](#user-and-directories-config)
  * [HTTP Endpoint Settings](#http-endpoint-settings)
  * [Consul Agent Config](#consul-agent-config)
* [Example Playbook](#example-playbook)
* [Example Cluster](#example-cluster)
* [Testing and Contributing](#testing-and-contributing)
* [License](#license)
* [Author Information](#author-information)

----------



Requirements
------------

There are no external requirements, however the playbook used to install and manage Consul Servers **MUST** be run with execution mode `strategy: free`. Consul server nodes coordinate their own actions and should not be run in standard `linear` mode. See the [Usage](#usage) sections for further details.



Dependencies
------------
None



Usage
----------

### Understanding the Consul Role
----------
Consul is a complex, highly configurable tool that provides a distributed, scalable, and highly available method of storing configuration information and state. This makes it an excellent choice for use with service discovery or coordinating distributed actions.

Understanding all the innards of the Consul is out of scope for this document, however there are a few concepts that should be addressed before attempting to deploy Consul in a Production setting.

Consul uses [Raft](https://raft.github.io/) as it's consensus mechanism to maintain state across server nodes. Raft depends on a quorum, or a majority of members to be available at any given time. This means Consul server nodes must be deployed in quantities of `(n/2)+1`, or simply an odd number of servers. If for any reason quorum cannot be established, Consul will be **UNAVAILABLE**. This makes it incredibly important to coordinate actions that could potentially disrupt quorum. A common example of this would be service or system restarts.

This is also the case with initial Consul cluster bootstrapping. Consul services will **NOT** be available until the expected amount of servers are online (see the `bootstrap-expect` config option), and a quorum can be established.

This role handles these actions in a unique way using features built into Consul itself. Actions that **MUST** be run once in a specific manner are coordinated through what is known as a [semaphore lock](https://www.consul.io/docs/guides/semaphore.html). Each server will first wait for all nodes to be present in the quorum, then proceed to obtain a 'session', or a randomly generated uuid associated with the node. They will then compete to take ownership of a predefined key stored in Consul key/value store. The system that has taken ownership will then perform the desired action, followed by releasing its ownership over the key. The remaining nodes will continue to compete to take ownership and the cycle will complete until all systems in the quorum have completed the action.

Locks are coordinated for two types of actions: restarting the Consul Agent Service or create, update, or destroy operation for ACLs. These actions will be discussed further in the sections below.


Ansible's default `strategy` of executing tasks in a playbook is done in what is known as `linear` mode. In this mode, all actions happen in lockstep. A task must complete on **ALL** hosts before moving to the next task. This method will **NOT** work when provisioning servers with this role (it is fine for clients). `Strategy` must be set to `free` for server provisioning to work as intended.

In this mode, tasks will fire off independently and as fast as possible on each of the hosts. This will allow for them to wait and coordinate their actions utilizing the semaphore locks correctly.



### Bootstrapping and Security Auto-Configuration
----------

If the role is instructed to manage either Consul's gossip encryption or ACLs, there is some specific security related bootstrapping that must occur.

First, a host from the Ansible group of servers specified by the `consul_agent_server_group` variable will be selected to perform the initial bootstrap configuration. By default, the first host in this group will be selected. If however, another host in the group would be preferred; this may be overridden by supplying the inventory hostname of the desired host via the `consul_agent_bootstrap_host` variable.

Second, a json file will be created on the host running Ansible (as in, the Ansible Master or Controller). The intention of this file is to save the Consul security related configuration information (gossip encryption, acl uuids etc). This file is controlled by the hash `consul_agent_security_config_file` and by default has the following settings:

```yaml
consul_agent_security_config_file:
  path: '/etc/consul/security.json'
  owner: root
  group: root
  mode: '0640'
```

**Note:** The user executing Ansible **MUST** be able to read/write to the path supplied.

The file generated will contain the following:


```json
{
  "consul_agent_sec_cfg": {
    "encrypt": "",
    "acl": {
      "acls": {},
      "master_token": "",
      "uuid": {}
    }
  }
}
```

Third, the bootstrap host will then generate either or both the gossip encryption key, and the acl master token saving them on the master in the security config file. Once this is done, the security bootstrapping will be complete.


**All nodes**, both **client** and **server** will read this file to populate various variables in the Consul Configuration.

#### Gossip Encryption
When `consul_agent_manage_gossip_encryption` is set to `true` the encryption key will automatically be added to either the Consul Agent config (`consul_agent_config`) hash, or the Opts (`consul_agent_opts`). The encryption key should **NOT** be supplied manually. For more information on Consul's Gossip Encryption, please see the [Consul Gossip Encryption Documentation](https://www.consul.io/docs/agent/encryption.html).



#### RPC Encryption
If `consul_agent_manage_rpc_encryption` is set to `true`. The role will expect 3 other variables to be set.

|             Variable            |                                                                                            Description                                                                                            |
|:-------------------------------:|:-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------:|
|  `consul_agent_rpc_encrypt_ca`  |                                                          The PEM-encoded CA certificate used to check both client and server connections.                                                         |
| `consul_agent_rpc_encrypt_cert` |                                                          The PEM-encoded certificate that is used for both client and server connections.                                                         |
|  `consul_agent_rpc_encrypt_key` | The PEM-encoded private key used to with the certificate to validate the consul Agent's authenticity. This **MUST** be supplied with certificate referenced with `consul_agent_rpc_encrypt_cert`. |

The cert components above will then be created in their respective files, and stored in the `consul_agent_certs_dir`. Their paths and variables will then be added to the `consul_agent_config` hash.

The role however will **NOT** set the variables associated with the desired check behavior, and these should be added to the `consul_agent_config` hash. These variables include `verify_incoming`, `verify_outgoing`, and `verify_server_hostname`. For information on how this will affect Consul's behavior, see the main documentation regarding [RPC Encryption](https://www.consul.io/docs/agent/encryption.html).



#### ACL Master Token
If `consul_agent_manage_acls` is set to `true`, the acl master token will be generated and automatically injected into the config hash (`consul_agent_config`) for Consul **Servers** as the `acl_master_token` variable.

In addition to the `acl_master_token` if no `acl_datacenter` variable is supplied in the Consul config, the role will look at the both the `consul_agent_config` hash and `consul_agent_opts` checking for the `dc` variable. If it cannot be found the default (`dc1`) will be injected into the config. For more information on ACL configuration, see the [ACL](#acl) section below.



### ACLs
----------

ACL management is centered around the `consul_agent_acls` hash. This hash consists of key:value pairs, with the key being a unique 'Ansible friendly name', and the value including at a minimum, the elements `rules` and `type`. Additionally, a `name` element may be provided,  however its use is simply to be a friendly name within Consul itself. It has **no** relation to the key or 'Ansible friendly name'.

ACLs managed by the role should **NOT** be updated or modified outside of Ansible. It will **NOT** detect changes to the ACL within Consul itself. The same can be applied for ACLs created outside of Ansible. If it was not created by Ansible, it should not be managed by Ansible. This behavior is intentional, and was built that way to prevent interfering with other services that may manage ACLs directly (namely [Hashicorp's Vault](https://www.vaultproject.io/)).

When the ACL management portion of the role is triggered whether it be a create, update, or delete action, a key will be created within Consul's key/value store. This key is managed by the `consul_agent_kv_acl` variable and defaults to `locks/consul/acl`.

After the key has been created, the servers will request a session from Consul with a `TTL` or time-to-live value as managed by the `consul_agent_check_ttl` variable. This means the session will become invalidated if it is not renewed within that timeframe.

Once a server has obtained a session, it will attempt to acquire ownership of the key as specified by `consul_agent_kv_acl`. If it obtains ownership it will proceed to execute the ACL actions and has the duration of the `TTL` to complete. The other servers will pause at this point and continue to retry and acquire ownership of the key, based on the settings of two variables - `consul_agent_check_delay` and `consul_agent_check_retries`.

For the node that obtained the lock, it will then proceed to perform the following actions for ACL creation, updating, or deletion.

**ACL Creation**
1. If an ACL is supplied and its 'Ansible friendly name' is unknown, attempt to create it.
2. Once created, save the returned uuid from Consul.
3. Update the Consul Security Config File that is stored on the master with with the ACL and the uuid.

**ACL Update**
1. If an ACL's 'Ansible friendly name' is known, compare the config in `consul_agent_acls` to what is stored on the master in Consul agent security config file.
2. If they differ, get the uuid from the security config file, and attempt to update it in Consul.
3. If the update in Consul was successful, update ACL definition in the security config file.

**ACL Deletion**
1. If there is an 'Ansible friendly name' in the security config file that is **NOT** in the `consul_agent_acls` hash, attempt to delete it.
2. If the attempt was successful, remove the entries from the Consul agent security config file.

If all actions were successful, the server will release ownership of the key, and the next node to obtain the lock will perform the same set of checks ensuring `consul_agent_acls` and the information in the Consul Agent Security Config file are in sync.

If for whatever reason the server performing the ACL actions should fail, the `TTL` will expire and the next node to obtain ownership of the key, will pick up where it left off, attempting to finish the ACL actions.


#### Accessing Information Stored in the Security Config

The security config file contains a fairly simple schema that makes it easy to access ACL tokens on client nodes, or even other roles or tasks themselves.

All Consul Security information will be loaded in a hash under the variable `consul_agent_sec_cfg`, and will have the following schema:

```json
{
  "consul_agent_sec_cfg": {
    "encrypt": "",
    "acl": {
      "acls": {},
      "master_token": "",
      "uuid": {}
    }
  }
}
```

* `consul_agent_sec_cfg.acl.master_token` - Is the role generated Consul ACL Master Token.

* `consul_agent_sec_cfg.acl.acls` - Contains the same key:value pair as stored in `consul_agent_acls`

* `consul_agent_sec_cfg.acl.uuid` - Contains a mapping of the key used in `consul_agent_sec_cfg.acl.acls` and `consul_agent_acls` to it's associated Consul generated token.

To reference a token, simply include or use a lookup to read the information from the file and access the token uuid by `consul_agent_sec_cfg.acl.uuid[<Ansible friendly name>]`.

An example of of a security config is included below.

```json
{
  "consul_agent_sec_cfg": {
    "encrypt": "VmxrZyV4RihnWWJSMDhvIw==",
    "acl": {
      "acls": {
        "write_kv": {
          "rules": "key \"locks/consul/restart\" {\n  policy = \"write\"\n}\n",
          "type": "client",
          "name": "write_kv"
        },
        "read_kv": {
          "rules": "key \"locks/consul/acl\" {\n  policy = \"read\"\n}\n",
          "type": "client",
          "name": "read_kv"
        }
      },
      "master_token": "8339d65c-049c-437b-be63-7c71d1f0dfa0",
      "uuid": {
        "write_kv": "2a88a116-476b-4636-13b0-63598d1bcdc7",
        "read_kv": "de62b22f-b9ba-1b08-77d2-ffcc1362b4c0"
      }
    }
  }
}
```



### Service Restarts
----------

Service Restarts for Consul Servers are coordinated when changes occur to either `consul_agent_opts` or `consul_agent_config`. Changes to `consul_agent_checks`, `consul_agent_services`, or `consul_agent_watches` will **ONLY** trigger a reload of the service and do not need to be coordinated.

When a restart is needed, The role will create a key as supplied by the variable `consul_agent_kv_restart` and defaults to `locks/consul/restart`. **Note:** If ACLs are enabled, all actions taken by the Consul Servers use the `acl_master_token` when interacting with Consul itself.

Once the key is created, the servers will request a session from Consul. This request is done **WITHOUT** a `TTL` value, meaning a lock will stay in place until the node is deregistered or the session is deleted. When the server is stopped or restarted, node deregistration will automatically occur, triggering the release of the lock.

To prevent a node from quickly restarting after the lock is released, the next node will hold the lock till all peers are back, and a leader has been elected. This acts as a failsafe in the event of a possible bad configuration disrupting the quorum. The duration and amount of retries for this setting are managed by the variables `consul_agent_check_delay` and `consul_agent_check_retries`.



Role Variables
----------



### Execution Control and Security
----------

The settings in this section determine both what and how the components of the role will be excuted.


#### Defaults
|                  Variable                 |           Default           |
|:-----------------------------------------:|:---------------------------:|
|        `external_dependency_delay`        |             `20`            |
|       `external_dependency_retries`       |             `6`             |
|       `consul_agent_security_no_log`      |           `false`           |
|  `consul_agent_manage_gossip_encryption`  |            `true`           |
|    `consul_agent_manage_rpc_encryption`   |           `false`           |
|         `consul_agent_manage_acls`        |            `true`           |
|        `consul_agent_server_group`        |              -              |
|       `consul_agent_bootstrap_host`       |              -              |
|  `consul_agent_security_config_file.path` | `/etc/consul/security.json` |
| `consul_agent_security_config_file.owner` |            `root`           |
| `consul_agent_security_config_file.group` |            `root`           |
|  `consul_agent_security_config_file.mode` |            `0644`           |
|       `consul_agent_rpc_encrypt_ca`       |              -              |
|      `consul_agent_rpc_encrypt_cert`      |              -              |
|       `consul_agent_rpc_encrypt_key`      |              -              |
|         `consul_agent_check_delay`        |             `30`            |
|        `consul_agent_check_retries`       |             `20`            |
|          `consul_agent_check_ttl`         |            `300`            |
|           `consul_agent_kv_acl`           |      `locks/consul/acl`     |
|         `consul_agent_kv_restart`         |    `locks/consul/restart`   |

#### Description

* **external_dependency_delay** - The time in seconds between external dependency retries. (repos, keyservers, etc)

* **external_dependency_retries** - The number of retries to attempt accessing an external dependency.

* **consul_agent_security_no_log** - If `true`, any action that could contain a potential secret will not be logged. This does set the `no_log` option for the majority of the role.

* **consul_agent_manage_gossip_encryption** - If enabled, the role will automatically generate a gossip encryption key and inject it into the config of every node. The encryption key is saved on the Ansible master in a json file controlled by the `consul_agent_security_config_file` variable.
* **consul_agent_manage_rpc_encryption** - When `true`, the role will inject the certificate information supplied by the `consul_agent_rpc_cert_*` variables into their associated files and add them to the consul agent config. Note: This does NOT fully configure rpc encryption, options such `verify_server_hostname`, `verify_incoming`, and `verify_outgoing` must be managed via the `consul_agent_config` hash variable.

* **consul_agent_manage_acls** - Allows the role to manage ACLs. This will automatically create a master token, as well as create, update, or delete ACLs managed via the `consul_agent_acls` hash. It will **NOT** impact ACLs created outside of Ansible. When using tokens on consul clients or for use in other roles, their token may be accessed via `consul_agent_sec_cfg.acl.uuid[<acl name>]` hash. This hash contains a mapping of user defined ACL names to UUIDs, and is saved on the Ansible master in a json file controlled by the `consul_agent_security_config_file` variable.

* **consul_agent_server_group** - The name of the ansible group containing the consul servers.

* **consul_agent_bootstrap_host** - A consul server host that will handle the initial bootstrapping of the consul security configuration. This includes both gossip encryption and acl master token generation. If not supplied, the first host as defined in the `consul_agent_server_group` will be used.

* **consul_agent_security_config_file.path** - The path to the Consul Agent Security Config file to be stored on the Ansible Master or Controller.

* **consul_agent_security_config_file.owner** - The owner of Consul Agent Security Config file.

* **consul_agent_security_config_file.group** - The group name of the group that the Consul Agent Security Config file should be grouped into.
* **consul_agent_security_config_file.mode** - The mode of the Consul Agent Security Config file.

* **consul_agent_rpc_encrypt_ca** - The PEM-encoded CA certificate used to check both client and server connections. If supplied, and `consul_agent_manage_rpc_encryption` is `true`, the `ca_file` config option will be added automatically.

* **consul_agent_rpc_encrypt_cert** - The PEM-encoded certificate that is used for both client and server connections. If supplied, and `consul_agent_manage_rpc_encryption` is `true`, the `cert_file` config option will be added automatically.

* **consul_agent_rpc_encrypt_key** - The PEM-encoded private key used to with the certificate to validate the consul Agent's authenticity. **MUST** be supplied with certificate referenced with `consul_agent_rpc_encrypt_cert`. If supplied, and `consul_agent_manage_rpc_encryption` is `true`, the `key_file` config option will be added automatically.

* **consul_agent_check_delay** - Global amount of time to wait between retries for actions that could possibly fail.

* **consul_agent_check_retries** - Global number of retries for actions that could possibly fail. Examples include http checks or package downloads.

* **consul_agent_check_ttl** - The session `TTL` for use with consul locks. At this time, only used with ACL locks.

* **consul_agent_kv_acl** - The key name of the key:value pair used when managing acls.

* **consul_agent_kv_restart** - The key name of the key:value pair used when coordinating restarts of the Consul service.



### Download and Versioning
----------

The Downloading and Versioning variables instruct the role on where it should download Consul, and what version should be installed.

#### Defaults

|            Variable            |                 Default                 |
|:------------------------------:|:---------------------------------------:|
|     `consul_agent_baseurl`     | `https://releases.hashicorp.com/consul` |
|     `consul_agent_version`     |                 `0.6.4`                 |
| `consul_agent_verify_checksum` |                  `true`                 |

#### Description

* **consul_agent_baseurl** - The baseurl used when downloading consul. If using something other than the default, ensure that the download schema is followed: `<baseurl>/<version>/consul_<version>_linux_[amd64|386].zip`

* **consul_agent_version** - The version of consul to download and install.

* **consul_agent_verify_checksum** - If `true`, it will download the sha256 checksums and verify the downloaded file matches. The hash file must be in the same directory as the zip and have a filename matching `consul_<version>_SHA256SUMS`.



### User and Directories Config
----------

The Users and Directories Config dictate the creation of the folders needed to run Consul, as well as the user and group they should belong to.

#### Defaults

|           Variable          |          Default          |
|:---------------------------:|:-------------------------:|
|   `consul_agent_user.name`  |          `consul`         |
|   `consul_agent_user.uid`   |             -             |
|  `consul_agent_user.system` |           `true`          |
| `consul_agent_user.comment` |       `Consul User`       |
|  `consul_agent_user.shell`  |        `/bin/bash`        |
|   `consul_agent_group.name` |          `consul`         |
|   `consul_agent_group.gid`  |             -             |
| `consul_agent_group.system` |           `true`          |
|  `consul_agent_config_dir`  |    `/etc/consul/conf.d`   |
|   `consul_agent_data_dir`   |   `/var/lib/consul/data`  |
|  `consul_agent_scripts_dir` | `/var/lib/consul/scripts` |
|   `consul_agent_certs_dir`  |    `/etc/consul/certs`    |
|    `consul_agent_log_dir`   |     `/var/log/consul`     |

#### Description

* **consul_agent_user.name** - The name of the Consul user.

* **consul_agent_user.uid** - If supplied, the uid of the user will be set to this value.

* **consul_agent_user.system** - Boolean specifying if the account should be created as a system account.

* **consul_agent_user.comment** - The comment or GECOS to assign to the user account.

* **consul_agent_user.shell** - The shell for the Consul User. **NOTE:** This shell is used for any services or check scripts. It is advised **NOT** to set this to something like `/sbin/nologin`.

* **consul_agent_group.name** - The name of the Consul group.

* **consul_agent_group.gid** - If supplied, the gid of the group will be set to this value.

* **consul_agent_group.system** - Boolean specifying if the account should be a created as a system account.

* **consul_agent_config_dir** - The path to consul config directory. When supplied, it will automatically be added to the consul daemon opts (`consul_agent_opts`).

* **consul_agent_data_dir** - The path to the consul data directory. When supplied, it will automatically be added to the consul daemon opts (`consul_agent_opts`).

* **consul_agent_scripts_dir** - The path to the directory which will act as home for all scripts managed by the consul-agent role

* **consul_agent_certs_dir** - The path to the directory which will house the certificates managed by the consul-agent role.

* **consul_agent_log_dir** - The directory in which consul logs will be saved. **NOTE:** Will only be applicable to non systemd based systems.



### HTTP endpoint Settings
----------

All the http endpoint settings are optional and will be inferred by the variables supplied in either `consul_agent_opts` or `consul_agent_config`. **HOWEVER**, these should be supplied if intending to use consul behind a reverse proxy. e.g. nginx for ssl termination or using some form of http auth.

#### Defaults

|           Variable           | Default |
|:----------------------------:|:-------:|
|  `consul_agent_http_scheme`  |    -    |
|   `consul_agent_http_host`   |    -    |
|   `consul_agent_http_port`   |    -    |
|  `consul_agent_api_version`  |   `v1`  |
|   `consul_agent_http_user`   |    -    |
| `consul_agent_http_password` |    -    |

#### Description

* **consul_agent_http_scheme** - The http api endpoint URI scheme.

* **consul_agent_http_host** - The http api endpoint host address.

* **consul_agent_http_port** - The http api endpoint port.

* **consul_agent_api_version** - The Consul http api version.

* **consul_agent_http_user** - The username to supply when connecting with http basic auth.

* **consul_agent_http_password** - The password associated with the user in `consul_agent_http_user` when connecting with http basic auth.



Consul Agent Config
---------

The Consul Agent Config settings directly dictate how the Agent will run. These are the commandline parameters, config file, acls etc.

#### Defaults

|         Variable        | Default |
|:-----------------------:|:-------:|
|   `consul_agent_opts`   |    -    |
|  `consul_agent_config`  |    -    |
|   `consul_agent_acls`   |    -    |
|  `consul_agent_checks`  |    -    |
|  `consul_agent_scripts` |    -    |
| `consul_agent_services` |    -    |
|  `consul_agent_watches` |    -    |

#### Description

* **consul_agent_opts** - A hash of key:array of options that will supplied to the consul agent. Options are supplied in the form of key:array to handle items such as 'join' where it can be supplied multiple times.

* **consul_agent_config** - A hash of items that will be converted to json and used for the consul agent config.

* **consul_agent_acls** - A hash of ACLs that the role will manage. They MUST supplied in the form of `<Ansible friendly name>: { <acl definition> }`. The ansible acl name will act as a unique key to lookup the uuid of the acl when performing acl create/update/delete operations.

* **consul_agent_checks** - A hash that will be converted to json to be used as the checks config.

* **consul_agent_scripts** - An array of files (path required) to be synced to the remote system and stored in the `consul_agent_scripts_dir`. These scripts will then be available for use with any checks or watches.

* **consul_agent_services** - A hash that will be converted to json to be used as the services config.

* **consul_agent_watches** - A hash that will be converted to json to be used as the watches config.



Example Playbook
----------

```yaml

---
# Gather facts task done in linear strategy as a task before executing the consul server tasks to
# ensure all host variables are known before execution. If this is not done, tasks that reference
# host facts can fail. e.g. the start_join reference in the playbook below.
#
- name: Gather Facts
  hosts: all
  gather_facts: true
  any_errors_fatal: true

- name: provision consul servers
  hosts: consul_servers
  strategy: free
  tags:
    - 'consul:server'
  roles:
    - ansible-role-consul-agent
  vars:
    consul_agent_server_group: consul_servers
    consul_agent_manage_acls: true
    consul_agent_manage_gossip_encryption: true
    consul_agent_manage_rpc_encryption: false
    consul_agent_security_no_log: false
    consul_agent_opts:
      server:
      ui:
      client: ['{{ ansible_enp0s8.ipv4.address }}']
      bind: ['{{ ansible_enp0s8.ipv4.address }}']
      config-dir: ['/etc/consul/conf.d']
      data-dir: ['/var/lib/consul/data']
    consul_agent_config:
      bootstrap_expect: 3
      start_join: "{{ groups['consul_servers']|map('extract', hostvars, ['ansible_enp0s8', 'ipv4', 'address'])|list }}"
      advertise_addr: '{{ ansible_enp0s8.ipv4.address }}'
      log_level: INFO
    consul_agent_acls:
      write_kv:
        name: write_kv
        type: client
        rules: |
          key "locks/consul/restart" {
            policy = "write"
          }
      read_kv:
        name: read_kv
        type: client
        rules: |
          key "locks/consul/acl" {
            policy = "read"
          }
    consul_agent_scripts:
      - '../sshd_service.sh'
    consul_agent_services:
      service:
        name: ssh
        tags: ['ssh']
        address: '{{ ansible_enp0s8.ipv4.address }}'
        port: 22
    consul_agent_checks:
      checks:
        - id: ssh_tcp
          name: ssh_tcp check
          service_id: ssh
          tcp: '{{ ansible_enp0s8.ipv4.address }}:22'
          interval: 10s
          timeout: 1s
        - id: ssh_script
          name: ssh service check
          service_id: ssh
          script: /var/lib/consul/scripts/sshd_service.sh
          interval: 10s
          timeout: 1s


- name: provision consul clients
  hosts: consul_clients
  tags:
   - 'consul:client'
  roles:
    - ansible-role-consul-agent
  vars:
    consul_agent_manage_acls: false
    consul_agent_manage_gossip_encryption: true
    consul_agent_manage_rpc_encryption: false
    consul_agent_security_no_log: false
    consul_agent_opts:
      ui:
      client: ['{{ ansible_enp0s8.ipv4.address }}']
      bind: ['{{ ansible_enp0s8.ipv4.address }}']
      config-dir: ['/etc/consul/conf.d']
      data-dir: ['/var/lib/consul/data']
    consul_agent_config:
      advertise_addr: '{{ ansible_enp0s8.ipv4.address }}'
      start_join: "{{ groups['consul_servers']|map('extract', hostvars, ['ansible_enp0s8', 'ipv4', 'address'])|list }}"
      acl_token: "{{ consul_agent_sec_cfg.acl.uuid['write_kv'] }}"
      log_level: INFO

```

Example Cluster
----------

An example Vagrant Consul Cluster based on Ubuntu 16.04 is available for demo purposes. It uses the above Example playbook to spin up 3 Consul Servers, and 1 Client. It does require that Ansible be present on the host machine.

For best results, bring the cluster up first with `vagrant up --no-provision`, and give the systems a moment to fully come up. Then simply execute `vagrant provision`. **NOTE:** Depending on the permissions and security of Ansible on the host machine, this may need to executed with `sudo`.


Once the cluster is up, the Consul UI may be accessed from any one of the nodes at the following addresses:

|         Node         |              Address             |
|:--------------------:|:--------------------------------:|
| **consul-server-01** | `http://10.255.13.101:8500/ui/#` |
| **consul-server-02** | `http://10.255.13.102:8500/ui/#` |
| **consul-server-03** | `http://10.255.13.103:8500/ui/#` |
| **consul-client-01** | `http://10.255.13.111:8500/ui/#` |


Testing and Contributing
----------

Please see the [CONTRIBUTING.md](CONTRIBUTING.md) document in the repo for information regarding testing and contributing.

**TIP:** If you've previously brought up the Vagrant Cluster, remove the vagrant machines to drastically speed up testing. This can be done by executing the following: `rm -r .vagrant/machines/*`


License
----------

MIT

Author Information
----------

Created by Bob Killen, maintained by the Department of [Advanced Research Computing and Technical Services](http://arc-ts.umich.edu/) of the University of Michigan.
