if node['mongodb']['config']['auth']

    include_recipe 'mongodb::install'
    include_recipe 'mongodb::mongo_gem'

    # If authentication is required,
    # add the admin to the users array for adding/updating

    # Add each user specified in attributes
    [ node['mongodb']['admin'] ].concat( node['mongodb']['users'] ).each do |user|
      mongodb_user user['username'] do
        password user['password']
        roles user['roles']
        action :add
        notifies node['mongodb']['reload_action'], "service[#{node['mongodb']['instance_name']}]", :delayed
      end
    end
end
