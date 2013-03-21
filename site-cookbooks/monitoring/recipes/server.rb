include_recipe 'runit'
include_recipe 'riemann::server'
include_recipe 'graphite'
include_recipe 'monitoring::client'
include_recipe 'firewall'

%w{ruby1.9.3 rubygems}.each do |pkg|
  package pkg do
    action :upgrade
  end
end

gem_package 'riemann-tools' do
  action :install
  gem_binary "/usr/bin/gem1.9.3"
end

template '/etc/riemann/riemann.config' do
  source 'riemann.config.erb'
  owner 'root'
  group 'root'
  mode 0644
  notifies :restart, resources(:service => 'riemann')
end

firewall "ufw" do
  action :enable
end

firewall_rule "ssh" do
  port 22
  protocol :tcp
  action :allow
end

firewall_rule "http" do
  port 80
  protocol :tcp
  action :allow
end

firewall_rule "riemann_our_net" do
  port 5555
  source "140.211.10.64/26"
  direction :in
  action :allow
end

firewall_rule "graphite_our_net" do
  port 2003
  source "140.211.10.64/26"
  direction :in
  action :allow
end

# Dirty hack to change our resolution
# Hope Noah knows a better way
storage_template = "#{node['graphite']['base_dir']}/conf/storage-schemas.conf"

begin
  template = resources("template[#{storage_template}]")
  template.source "storage-schemas.conf.erb"
  template.cookbook "monitoring"
rescue Chef::Exceptions::ResourceNotFound
  Chef::Log.warn "Can't locate #{storage_template} to modify"
end