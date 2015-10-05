#
# Cookbook Name:: mongodb
# Definition:: mongodb
#
# Copyright 2011, edelight GmbH
# Authors:
#       Markus Korn <markus.korn@edelight.de>
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

require 'json'

class Chef::ResourceDefinitionList::MongoDB
  def self.configure_replicaset(node, name, members)
    # lazy require, to move loading this modules to runtime of the cookbook
    require 'rubygems'
    require 'mongo'
    require 'bson'

    if members.length == 0
      if Chef::Config[:solo]
        Chef::Log.warn('Cannot search for member nodes with chef-solo, defaulting to single node replica set')
      else
        Chef::Log.warn("Cannot configure replicaset '#{name}', no member nodes found")
        return
      end
    end

    begin
      connection = get_connection(node, ["localhost:#{node['mongodb']['config']['port']}"])
    rescue => e
      Chef::Log.warn("Could not connect to database: 'localhost:#{node['mongodb']['config']['port']}', reason: #{e}")
      return
    end

    # Want the node originating the connection to be included in the replicaset
    members << node unless members.any? { |m| m.name == node.name }
    members.sort! { |x, y| x.name <=> y.name }
    rs_members = []
    rs_options = {}
    members.each_index do |n|

      new_member = Chef::Node.new

      default_node_hash = node.default.to_hash
      default_node_hash.delete( 'run_list' )
      default_node_hash.delete( 'recipes' )

      new_member.consume_attributes( default_node_hash )

      member_hash = members[n].to_hash
      member_hash.delete( 'run_list' )
      member_hash.delete( 'recipes' )

      new_member.consume_attributes( member_hash )

      members[n].consume_attributes( new_member.to_hash )

      host = "#{members[n]['fqdn']}:#{members[n]['mongodb']['config']['port']}"
      rs_options[host] = {}
      rs_options[host]['arbiterOnly'] = true if members[n]['mongodb']['replica_arbiter_only']
      rs_options[host]['buildIndexes'] = false unless members[n]['mongodb']['replica_build_indexes']
      rs_options[host]['hidden'] = true if members[n]['mongodb']['replica_hidden']
      slave_delay = members[n]['mongodb']['replica_slave_delay']
      rs_options[host]['slaveDelay'] = slave_delay if slave_delay > 0
      if rs_options[host]['buildIndexes'] == false || rs_options[host]['hidden'] || rs_options[host]['slaveDelay']
        priority = 0
      else
        priority = members[n]['mongodb']['replica_priority']
      end
      rs_options[host]['priority'] = priority unless priority == 1
      tags = members[n]['mongodb']['replica_tags'].to_hash
      rs_options[host]['tags'] = tags unless tags.empty?
      votes = members[n]['mongodb']['replica_votes']
      rs_options[host]['votes'] = votes unless votes == 1
      rs_members << { '_id' => n, 'host' => host }.merge(rs_options[host])
    end

    Chef::Log.info(
      "Configuring replicaset with members #{members.map { |n| n['hostname'] }.join(', ')}"
    )

    rs_member_ips = []
    members.each_index do |n|
      port = members[n]['mongodb']['config']['port']
      rs_member_ips << { '_id' => n, 'host' => "#{members[n]['ipaddress']}:#{port}" }
    end

    admin = connection.database
    cmd = BSON::Document.new
    cmd['replSetInitiate'] = {
      '_id' => name,
      'members' => rs_members
    }

    begin
        result = nil
        retry_db_op do
            result = admin.command(cmd).documents[0]
        end
    rescue => e
      Chef::Log.info("Started configuring the replicaset, this will take some time, another run should run smoothly: #{e}")
      return
    end
    if result['ok'] == 1
      # everything is fine, do nothing
    elsif ( result['errmsg'] =~ /(\S+) is already initiated/i ) || (result['errmsg'] =~ /already initialized/i)
      server, port = Regexp.last_match.nil? || Regexp.last_match.length < 2 ? ['localhost', node['mongodb']['config']['port']] : Regexp.last_match[1].split(':')
      begin
        connection = get_connection( node, ["#{server}:#{port}"] )
        connection.use('local')
      rescue
        abort("Could not connect to database: '#{server}:#{port}'")
      end

      # check if both configs are the same
      config = connection['system.replset'].find('_id' => name).limit(1).first

      if config['_id'] == name && config['members'] == rs_members
        # config is up-to-date, do nothing
        Chef::Log.info("Replicaset '#{name}' already configured")
      elsif config['_id'] == name && config['members'] == rs_member_ips
        # config is up-to-date, but ips are used instead of hostnames, change config to hostnames
        Chef::Log.info("Need to convert ips to hostnames for replicaset '#{name}'")
        old_members = config['members'].map { |m| m['host'] }
        mapping = {}
        rs_member_ips.each do |mem_h|
          members.each do |n|
            ip, prt = mem_h['host'].split(':')
            mapping["#{ip}:#{prt}"] = "#{n['fqdn']}:#{prt}" if ip == n['ipaddress']
          end
        end
        config['members'].map! do |m|
          host = mapping[m['host']]
          { '_id' => m['_id'], 'host' => host }.merge(rs_options[host])
        end
        config['version'] += 1

        rs_connection = get_connection(node, old_members)

        admin = rs_connection.database
        cmd = BSON::Document.new
        cmd['replSetReconfig'] = config
        result = nil
        begin
          result = admin.command(cmd).documents[0]
        rescue => e
          # reconfiguring destroys existing connections, reconnect
          connection = get_connection(node, ["localhost:#{node['mongodb']['config']['port']}"])
          connection.use('local')
          config = connection.database['system.replset'].find('_id' => name).limit(1).first
          # Validate configuration change
          if config['members'] == rs_members
            Chef::Log.info("New config successfully applied: #{config.inspect}, previous error: #{e}")
          else
            Chef::Log.error("Failed to apply new config. Current config: #{config.inspect} Target config #{rs_members}, previous error: #{e}")
            return
          end
        end
        Chef::Log.error("configuring replicaset returned: #{result.inspect}") unless result['errmsg'].nil?
      else
        # remove removed members from the replicaset and add the new ones
        max_id = config['members'].map { |member| member['_id'] }.max
        rs_members.map! { |member| member['host'] }
        config['version'] += 1
        old_members = config['members'].map { |member| member['host'] }
        members_delete = old_members - rs_members
        config['members'] = config['members'].delete_if { |m| members_delete.include?(m['host']) }
        config['members'].map! do |m|
          host = m['host']
          { '_id' => m['_id'], 'host' => host }.merge(rs_options[host])
        end
        members_add = rs_members - old_members
        members_add.each do |m|
          max_id += 1
          config['members'] << { '_id' => max_id, 'host' => m }.merge(rs_options[m])
        end

        rs_connection = get_connection(node, old_members)

        admin = rs_connection.database

        cmd = BSON::Document.new
        cmd['replSetReconfig'] = config

        result = nil
        begin
          result = admin.command(cmd).documents[0]
        rescue => e
          # reconfiguring destroys existing connections, reconnect
          connection = get_connection(node, ["localhost:#{node['mongodb']['config']['port']}"])
          connection.use('local')
          config = connection['system.replset'].find('_id' => name).limit(1).first
          # Validate configuration change
          if config['members'] == rs_members
            Chef::Log.info("New config successfully applied: #{config.inspect}, previous error: #{e}")
          else
            Chef::Log.error("Failed to apply new config. Current config: #{config.inspect} Target config #{rs_members}, previous error: #{e}")
            return
          end
        end
        Chef::Log.error("configuring replicaset returned: #{result.inspect}") unless result.nil? || result['errmsg'].nil?
      end
    elsif !result['errmsg'].nil?
      Chef::Log.error("Failed to configure replicaset, reason: #{result.inspect}")
    end
  end

  def self.configure_shards(node, shard_nodes)
    # lazy require, to move loading this modules to runtime of the cookbook
    require 'rubygems'
    require 'mongo'
    require 'bson'

    shard_groups = Hash.new { |h, k| h[k] = [] }

    shard_nodes.each do |n|
      new_n = Chef::Node.new

      default_node_hash = node.default.to_hash
      default_node_hash.delete( 'run_list' )
      default_node_hash.delete( 'recipes' )

      new_n.consume_attributes( default_node_hash )

      member_hash = n.to_hash
      member_hash.delete( 'run_list' )
      member_hash.delete( 'recipes' )

      new_n.consume_attributes( member_hash )

      n.consume_attributes( new_n.to_hash )

      next if n['mongodb']['replica_hidden']

      n_recipes = n['recipes']

      if n_recipes.nil?
        n_recipes = []
      end

      key = n['mongodb']['config']['replSet']

      unless key
        key = "rs_#{n['mongodb']['shard_name']}"
      end

      unless key
        key = '_single'
      end

      shard_groups[key] << "#{n['fqdn']}:#{n['mongodb']['config']['port']}"
    end
    Chef::Log.info("shard_groups:" + shard_groups.inspect)

    shard_members = []
    shard_groups.each do |name, members|
      if name == '_single'
        shard_members += members
      else
        shard_members << "#{name}/#{members.join(',')}"
      end
    end
    Chef::Log.info("shard_members: " + shard_members.inspect)

    begin
      connection = get_connection(node, ["localhost:#{node['mongodb']['config']['port']}"])
    rescue => e
      Chef::Log.warn("Could not connect to database: 'localhost:#{node['mongodb']['config']['port']}', reason #{e}")
      return
    end

    admin = connection.database

    shard_members.each do |shard|
      cmd = BSON::Document.new
      cmd['addShard'] = shard
      result = nil
      retry_db_op do
        result = admin.command(cmd).documents[0]
      end
      Chef::Log.info(result.inspect)
    end
  end

  def self.configure_sharded_collections(node, sharded_collections)
    if sharded_collections.nil? || sharded_collections.empty?
      Chef::Log.warn('No sharded collections configured, doing nothing')
      return
    end

    # lazy require, to move loading this modules to runtime of the cookbook
    require 'rubygems'
    require 'mongo'
    require 'bson'

    begin
      connection = get_connection(node, ["localhost:#{node['mongodb']['config']['port']}"])
    rescue => e
      Chef::Log.warn("Could not connect to database: 'localhost:#{node['mongodb']['config']['port']}', reason #{e}")
      return
    end

    admin = connection.database

    databases = sharded_collections.keys.map { |x| x.split('.').first }.uniq
    Chef::Log.info("enable sharding for these databases: '#{databases.inspect}'")

    databases.each do |db_name|
      cmd = BSON::Document.new
      cmd['enablesharding'] = db_name
      begin
        result = nil
        retry_db_op do
            result = admin.command(cmd).documents[0]
        end
      rescue => e
        result = "enable sharding for '#{db_name}' timed out, run the recipe again to check the result: #{e}"
      end
      if result['ok'] == 0
        # some error
        errmsg = result['errmsg']
        if errmsg == 'already enabled'
          Chef::Log.info("Sharding is already enabled for database '#{db_name}', doing nothing")
        else
          Chef::Log.error("Failed to enable sharding for database #{db_name}, result was: #{result.inspect}")
        end
      else
        # success
        Chef::Log.info("Enabled sharding for database '#{db_name}'")
      end
    end

    sharded_collections.each do |name, key|
      cmd = BSON::Document.new
      cmd['shardcollection'] = name
      unless key.kind_of?(Hash)
        key = { "#{key}" => 1 }
      end
      cmd['key'] = key
      key = key.inspect
      begin
        result = nil
        retry_db_op do
            result = admin.command(cmd).documents[0]
        end
      rescue => e
        result = "sharding '#{name}' on key '#{key}' timed out, run the recipe again to check the result: #{e}"
      end
      if ( result['ok'] == 0 ) || ( ! result['collectionsharded'] )
        # some error
        errmsg = result['errmsg']
        if errmsg == 'already sharded'
          Chef::Log.info("Sharding is already configured for collection '#{name}', doing nothing")
        else
          Chef::Log.error("Failed to shard collection #{name}, result was: #{result.inspect}")
        end
      else
        # success
        Chef::Log.info("Sharding for collection '#{result['collectionsharded']}' enabled")
      end
    end
  end

  def self.configure_create_indexes(node, create_indexes)
    if create_indexes.nil? || create_indexes.empty?
      Chef::Log.warn('No indexes configured, doing nothing')
      return
    end

    # lazy require, to move loading this modules to runtime of the cookbook
    require 'rubygems'
    require 'mongo'
    require 'bson'

    begin
      connection = get_connection(node, ["localhost:#{node['mongodb']['config']['port']}"])
    rescue => e
      Chef::Log.warn("Could not connect to database: 'localhost:#{node['mongodb']['config']['port']}', reason #{e}")
      return
    end

    create_indexes.each do |collection, data|
      split_collection = collection.split('.')
      dbname = split_collection.shift()
      collection = split_collection.join('.')

      cmd = BSON::Document.new
      cmd['createIndexes'] = collection
      cmd['indexes'] = []

      data.each do |spec|
        idx_spec = BSON::Document.new
        [ 'name', 'key', 'background', 'sparse', 'unique', 'dropDups' ].each do |key|
            idx_spec[ key ] = spec[ key ] if spec.has_key?( key ) && ! spec[ key ].nil?
        end
        unless idx_spec['key'].kind_of?(Hash)
          idx_spec['key'] = { "#{idx_spec['key']}" => 1 }
        end
        cmd['indexes'] << idx_spec
      end
      key = key.inspect
      connection.use( dbname )
      db = connection.database
      begin
        result = nil
        retry_db_op do
            result = db.command(cmd).documents[0]
        end
      rescue => e
        result = "command " + cmd.inspect + " timed out: #{e}"
      end
      if result['ok'] == 0
        # some error
        errmsg = result['errmsg']
        #if errmsg == 'already sharded'
        #  Chef::Log.info("Sharding is already configured for collection '#{name}', doing nothing")
        #else
          Chef::Log.error("Failed to execute command " + cmd.inspect + ", result was: " + result.inspect)
        #end
      else
        # success
        Chef::Log.info("Indexes for #{dbname}.#{collection} are created successfully")
      end
      connection.use( 'admin' )
    end
  end

  def self.configure_user(node, spec)
    # lazy require, to move loading this modules to runtime of the cookbook
    require 'rubygems'
    require 'mongo'
    require 'bson'

    begin
      connection = get_connection(node, ["localhost:#{node['mongodb']['config']['port']}"])
    rescue => e
      Chef::Log.warn("Could not connect to database: 'localhost:#{node['mongodb']['config']['port']}', reason #{e}")
      return
    end

    admin = connection.database

    cmd = BSON::Document.new
    cmd['createUser'] = spec['username']
    cmd['pwd'] = spec['password']
    cmd['roles'] = spec['roles']

    result = nil

    retry_db_op do
        begin
            result = admin.command(cmd).documents[0]
        rescue => e
            if (!result.nil?) && result['errmsg'] && (result['errmsg'] =~ /already exists/i)
                Chef::Log.info("User #{spec['username']} already exists")
            else
                raise e
            end
        end
    end

    Chef::Log.info(result.inspect)
  end

  def self.get_connection(node, hosts)

      connection = nil
      default_options = {
          :server_selection_timeout => 3,
          :connection_timeout => 1,
          :connect => :direct,
          :database => 'admin',
          :read => {
              :mode => :secondary_preferred
          },
      }

      options = {}.merge( default_options )

      if node['mongodb']['config']['auth']

          options[:user] = node['mongodb']['admin']['username']
          options[:password] = node['mongodb']['admin']['password']
      end

      retry_db_op do
        begin
            connection = Mongo::Client.new(hosts, options)
            connection.database_names # check connection
        rescue => e
            connection = Mongo::Client.new(hosts, default_options)
            connection.database_names # check connection
        end
      end

      connection
  end

  # Ensure retry upon failure
  def self.retry_db_op(max_retries = 3)
    retries = 0
    begin
      yield
    rescue => ex
      retries += 1
      raise ex if retries > max_retries
      sleep(1.5)
      retry
    end
  end
end
