#
# Cookbook Name:: mongodb
# Attributes:: default
#
# Copyright 2010, edelight GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# this variable is being renamed to dbconfig_file
default[:mongodb][:configfile] = "/etc/mongodb.conf"

# cluster identifier
default[:mongodb][:client_roles] = []
default[:mongodb][:cluster_name] = nil
default[:mongodb][:shard_name] = "default"

# replica options
default[:mongodb][:replica_arbiter_only] = false
default[:mongodb][:replica_build_indexes] = true
default[:mongodb][:replica_hidden] = false
default[:mongodb][:replica_slave_delay] = 0
default[:mongodb][:replica_priority] = 1
default[:mongodb][:replica_tags] = {}
default[:mongodb][:replica_votes] = 1

default[:mongodb][:auto_configure][:replicaset] = true
default[:mongodb][:auto_configure][:sharding] = true

# don't use the node's fqdn, but this url instead; something like 'ec2-x-y-z-z.aws.com' or 'cs1.domain.com' (no port)
# if not provided, will fall back to the FQDN
default[:mongodb][:configserver_url] = nil

default[:mongodb][:root_group] = "root"
default[:mongodb][:user] = "mongodb"
default[:mongodb][:group] = "mongodb"

default[:mongodb][:init_dir] = "/etc/init.d"
default[:mongodb][:init_script_template] = "debian-mongodb.init.erb"
default[:mongodb][:sysconfig_file] = "/etc/default/mongodb"
default[:mongodb][:sysconfig_file_template] = "mongodb.sysconfig.erb"
default[:mongodb][:dbconfig_file] = node[:mongodb][:configfile] || "/etc/mongodb.conf"
default[:mongodb][:dbconfig_file_template] = "mongodb.conf.erb"
default[:mongodb][:package_name] = "mongodb"

default[:mongodb][:default_init_name] = "mongodb"
default[:mongodb][:instance_name] = "mongodb"

# this option can be "distro" or "10gen"
default[:mongodb][:install_method] = "distro"

default[:mongodb][:is_replicaset] = nil
default[:mongodb][:is_shard] = nil
default[:mongodb][:is_configserver] = nil

case node['platform_family']
when "debian"
    default[:mongodb][:apt_repo] = "debian-sysvinit"
end


default[:mongodb][:package_version] = nil
default[:mongodb][:template_cookbook] = "mongodb"

# These options are being deprecated (see dbconfig.rb)
default[:mongodb][:port] = 27017
default[:mongodb][:bind_ip] = nil
default[:mongodb][:logpath] = "/var/log/mongodb"
default[:mongodb][:dbpath] = "/var/lib/mongodb"
default[:mongodb][:nojournal] = false
default[:mongodb][:enable_rest] = false # rest
default[:mongodb][:smallfiles] = false
default[:mongodb][:oplog_size] = nil # opslogSize
default[:mongodb][:replicaset_name] = nil #replSet

# name is being clarified
default[:mongodb][:key_file] = nil # keyFile's contents
default[:mongodb][:key_file_content] = node[:mongodb][:key_file]
