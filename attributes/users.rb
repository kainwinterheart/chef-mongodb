default['mongodb']['admin'] = {
  'username' => 'admin',
  'password' => 'admin',
  'roles' => [
      {
          "role" => "dbAdmin",
          "db" => "admin",
      },
      {
          "role" => "dbOwner",
          "db" => "admin",
      },
      {
          "role" => "root",
          "db" => "admin",
      },
  ],
}

default['mongodb']['users'] = []
