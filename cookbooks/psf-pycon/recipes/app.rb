secrets = data_bag_item("secrets", "pycon")
is_production = tagged?('production')
if is_production
  db = data_bag_item("secrets", "postgres")["pycon2016"]
  app_name = "us.pycon.org"
  sentry_dsn = secrets["sentry_dsn"]["production"]
  google_oauth2 = secrets["google_oauth2"]["production"]
else
  db = data_bag_item("secrets", "postgres")["pycon2016-staging"]
  app_name = "staging-pycon.python.org"
  sentry_dsn = secrets["sentry_dsn"]["staging"]
  google_oauth2 = secrets["google_oauth2"]["staging"]
end

include_recipe "psf-pycon::apt_pgdg_postgresql"
include_recipe "nodejs::install_from_binary"
include_recipe "git"
include_recipe "firewall"


# Common env for Django processes
app_env = {
    "SECRET_KEY" => secrets["secret_key"],
    "GRAYLOG_HOST" => secrets["graylog_host"],
    "IS_PRODUCTION" => "#{is_production}",
    "DB_NAME" => db["database"],
    "DB_HOST" => db["hostname"],
    "DB_PORT" => "",
    "DB_USER" => db["user"],
    "DB_PASSWORD" => db["password"],
    "EMAIL_HOST" => "mail.python.org",
    "MEDIA_ROOT" => "/srv/staging-pycon.python.org/shared/media/",
    "SENTRY_DSN" => sentry_dsn,
    "GOOGLE_OAUTH2_CLIENT_ID" => google_oauth2['client_id'],
    "GOOGLE_OAUTH2_CLIENT_SECRET" => google_oauth2['client_secret'],
}
ENV.update(app_env)

execute "install_lessc" do
  command "npm install -g less@1.3.3"
end

git "/srv/pycon-archive" do
  repository "https://github.com/python/pycon-archive.git"
  revision "master"
end

application app_name do
  path "/srv/staging-pycon.python.org"
  repository "git://github.com/caktus/pycon.git"
  revision is_production ? "production" : "staging"
  packages ["postgresql-client-#{node['postgresql']['version']}", "libpq-dev", "git-core", "libjpeg8-dev"]
  migration_command "/srv/staging-pycon.python.org/shared/env/bin/python manage.py migrate --noinput"
  migrate true

  before_deploy do
    directory "/srv/staging-pycon.python.org/shared/media" do
      owner "root"
      group "root"
      action :create
    end
  end

  before_symlink do
    execute "/srv/staging-pycon.python.org/shared/env/bin/python manage.py compress --force" do
      user "root"
      cwd release_path
    end
  end

  django do
    requirements "requirements/project.txt"
    settings_template "local_settings.py.erb"
    local_settings_file "local_settings.py"
    collectstatic "collectstatic --noinput"
    settings :secret_key => secrets["secret_key"], :graylog_host => secrets["graylog_host"], :is_production => is_production
    database do
      engine "postgresql_psycopg2"
      database db["database"]
      hostname db["hostname"]
      username db["user"]
      password db["password"]
    end
  end

  gunicorn do
    app_module "symposion.wsgi"
    environment app_env
    virtualenv "/srv/staging-pycon.python.org/shared/env"
  end

  nginx_load_balancer do
    template 'nginx.conf.erb' # Remove this once /2014/ is the default
    hosts ['localhost']
    server_name [node['fqdn'], 'staging-pycon.python.org', 'us.pycon.org']
    static_files({
      "/2016/site_media/static" => "site_media/static",
      "/2016/site_media/media" => "/srv/staging-pycon.python.org/shared/media",
      "/2015" => "/srv/pycon-archive/2015",
      "/2014" => "/srv/pycon-archive/2014",
      "/2013" => "/srv/pycon-archive/2013",
      "/2012" => "/srv/pycon-archive/2012",
      "/2011" => "/srv/pycon-archive/2011",
    })
    application_port 8080
  end

end

template "/srv/staging-pycon.python.org/shared/.env" do
  path "/srv/staging-pycon.python.org/shared/.env"
  source "environment.erb"
  mode "0440"
  variables :app_env => app_env
end

cron_d "staging-pycon-account-expunge" do
  hour "0"
  minute "0"
  command "bash -c 'source /srv/staging-pycon.python.org/shared/.env && source /srv/staging-pycon.python.org/shared/env/bin/activate && cd /srv/staging-pycon.python.org/current && /srv/staging-pycon.python.org/shared/env/bin/python manage.py expunge_deleted'"
end

cron_d "staging-pycon-update-tutorial-registrants" do
  hour "0"
  minute "20"
  command "bash -c 'source /srv/staging-pycon.python.org/shared/.env && source /srv/staging-pycon.python.org/shared/env/bin/activate && cd /srv/staging-pycon.python.org/current && /srv/staging-pycon.python.org/shared/env/bin/python manage.py update_tutorial_registrants'"
end

firewall 'ufw' do
  action :enable
end

firewall_rule 'ssh' do
  port 22
  protocol :tcp
  action :allow
end

firewall_rule 'http_our_net' do
  port 80
  source '140.211.10.64/26'
  direction :in
  action :allow
end
