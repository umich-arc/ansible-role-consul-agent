# -*- encoding: utf-8 -*-
# frozen_string_literal: true

require 'spec_helper'
require 'support/users_and_groups'

def distrib
  return 'centos' if os[:family] == 'redhat'
  os[:family]
end

RSpec.describe ENV['KITCHEN_INSTANCE'] || host_inventory['hostname'] do
  context 'CONSUL_AGENT:PREREQS:ALL' do
    consul_agent_group = gen_consul_group_config
    consul_agent_user = gen_consul_user_config
    describe 'Consul Agent group' do
      subject { group(consul_agent_group['name']) }
      it { is_expected.to exist }
      if consul_agent_group.key?('gid')
        it { is_expected.to have_gid consul_agent_group['gid'] }
      end
    end
    describe 'Consul Agent user' do
      subject { user(consul_agent_user['name']) }
      it { is_expected.to exist }
      it { is_expected.to belong_to_group consul_agent_group['name'] }
      it { is_expected.to have_login_shell consul_agent_user['shell'] }
      if consul_agent_user.key?('uid')
        it { is_expected.to have_uid consul_agent_user['uid'] }
      end
    end

    describe 'Package prereqs' do
      property['_consul_agent_pkgs']["#{distrib}-#{os[:release].split('.').first}"].each do |pkg|
        subject { package(pkg) }
        it { should be_installed }
      end
    end
  end
end
