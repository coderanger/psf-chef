application "speed.pypy.org" do
  path "/srv/speed.pypy.org"
  repository "https://github.com/alex/codespeed.git"
  revision "pypy"
  migrate true
  packages ["libpq-dev", "git-core", "mercurial", "subversion"]

  django do
    requirements "example/requirements.txt"
    packages ["psycopg2"]
    # TODO: write this
    settings_template "settings.py.erb"
    local_settings_file "example/settings.py"
    collectstatic "collectstatic --noinput"
    settings :secret_key => data_bag_item("secrets", "pypy-codespeed")["secret_key"]
    database do
      engine "postgresql_psycopg2"
      database data_bag_item("secrets", "postgres")["pypy-codespeed"]["database"]
      hostname data_bag_item("secrets", "postgres")["pypy-codespeed"]["hostname"]
      username data_bag_item("secrets", "postgres")["pypy-codespeed"]["user"]
      password data_bag_item("secrets", "postgres")["pypy-codespeed"]["password"]
    end
  end

  before_restart do
    link "/srv/pypy-codespeed/current/manage.py" do
      to "example/manage.py"
    end
  end

  gunicorn do
    app_module :django
  end

  nginx_load_balancer do
    application_server_role "pypy-codespeed"
    static_files "/static" => "example/sitestatic/"
  end
end
