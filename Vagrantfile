sys = Process::Sys
base_path = File.expand_path(File.dirname(__FILE__))
ENV['ANSIBLE_ROLES_PATH'] = File.expand_path('..', base_path)
cluster = {
  'consul-server-01' => { ip: '10.255.13.101', cpus: 1, mem: 512 },
  'consul-server-02' => { ip: '10.255.13.102', cpus: 1, mem: 512 },
  'consul-server-03' => { ip: '10.255.13.103', cpus: 1, mem: 512 },
  'consul-client-01' => { ip: '10.255.13.111', cpus: 1, mem: 256 }
}

Vagrant.configure('2') do |config|
  if Vagrant.has_plugin?('vagrant-cachier')
    config.cache.auto_detect = true
    config.cache.scope = :machine
  end

  cluster.each do |hostname, info|
    config.vm.define hostname do |vm_cfg|
      vm_cfg.vm.box = 'bento/ubuntu-16.04'
      vm_cfg.vm.box_url = 'https://atlas.hashicorp.com/bento/ubuntu-16.04'
      vm_cfg.vm.hostname = hostname
      vm_cfg.vm.network  'private_network', ip: info[:ip]

      vm_cfg.vm.provider 'virtualbox' do |v|
        v.cpus = info[:cpus]
        v.memory = info[:mem]
      end

      if hostname == 'consul-client-01'
        vm_cfg.vm.provision :ansible do |ansible|
          ansible.sudo = true
          ansible.limit = 'all'
          ansible.playbook = base_path + '/tests/cluster/cluster.yml'
          ansible.verbose = true
          ansible.groups = {
            'consul_servers' => ['consul-server-01', 'consul-server-02', 'consul-server-03'],
            'consul_clients' => ['consul-client-01']
          }
          ansible.extra_vars = {
            consul_agent_security_config_file: {
              path: base_path + '/tests/cluster/security.json',
              owner: sys.getuid,
              group: sys.getgid,
              mode: '0640'
            }
          }
        end
      end
    end
  end
end
