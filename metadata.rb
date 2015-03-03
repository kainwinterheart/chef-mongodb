name              'mongodb'
maintainer        'edelight GmbH'
maintainer_email  'markus.korn@edelight.de'
license           'Apache 2.0'
description       'Installs and configures mongodb'
version           '0.16.3'

recipe 'mongodb', 'Installs and configures a single node mongodb instance'
recipe 'mongodb::10gen_repo', 'Adds the 10gen repo to get the latest packages'
recipe 'mongodb::mongos', 'Installs and configures a mongos which can be used in a sharded setup'
recipe 'mongodb::configserver', 'Installs and configures a configserver for mongodb sharding'
recipe 'mongodb::shard', 'Installs and configures a single shard'
recipe 'mongodb::replicaset', 'Installs and configures a mongodb replicaset'

depends 'apt', '>= 1.8.2'

%w(ubuntu debian).each do |os|
  supports os
end

attribute 'mongodb/config/dbpath',
          :display_name => 'dbpath',
          :description => 'Path to store the mongodb data',
          :default => '/var/lib/mongodb'

attribute 'mongodb/config/logpath',
          :display_name => 'logpath',
          :description => 'Path to store the logfiles of a mongodb instance',
          :default => '/var/log/mongodb/mongodb.log'

attribute 'mongodb/config/port',
          :display_name => 'Port',
          :description => 'Port the mongodb instance is running on',
          :default => '27017'

attribute 'mongodb/reload_action',
          :display_name => 'Reload',
          :description => 'Action to take when MongoDB config files are modified',
          :default => 'restart'

attribute 'mongodb/client_roles',
          :display_name => 'Client Roles',
          :description => 'Roles of nodes who need access to the mongodb instance',
          :type => 'array',
          :default => []

attribute 'mongodb/cluster_name',
          :display_name => 'Cluster Name',
          :description => 'Name of the mongodb cluster, all nodes of a cluster must have the same name.',
          :default => ''

attribute 'mongodb/shard_name',
          :display_name => 'Shard name',
          :description => 'Name of a mongodb shard',
          :default => 'default'

attribute 'mongodb/sharded_collections',
          :display_name => 'Sharded Collections',
          :description => 'collections to shard',
          :type => 'array',
          :default => []

attribute 'mongodb/config/replSet',
          :display_name => 'Replicaset Name',
          :description => 'Name of a mongodb replicaset',
          :default => ''

attribute 'mongodb/config/rest',
          :display_name => 'Enable Rest',
          :description => 'Enable the ReST interface of the webserver'

attribute 'mongodb/config/smallfiles',
          :display_name => 'Use small files',
          :description => 'Modify MongoDB to use a smaller default data file size'

attribute 'mongodb/config/bind_ip',
          :display_name => 'Bind address',
          :description => 'MongoDB instance bind address',
          :default => ''

attribute 'mongodb/package_version',
          :display_name => 'MongoDB package version',
          :description => 'Version of the MongoDB package to install',
          :default => ''

attribute 'mongodb/configfile',
          :display_name => 'Configuration File',
          :description => 'Name of configuration file to use with when starting mongod/mongos vs command line options',
          :default => ''

attribute 'mongodb/config/nojournal',
          :display_name => 'Disable Journals',
          :description => 'Journals are enabled by default on 64bit after mongo 2.0, this can disable it',
          :default => 'false'

