# -*- encoding: utf-8 -*-
# frozen_string_literal: true

require 'spec_helper'
require 'support/users_and_groups'

RSpec.describe ENV['KITCHEN_INSTANCE'] || host_inventory['hostname'] do
  context 'CONSUL_AGENT:INSTALL' do
    let(:consul_agent_group) { gen_consul_group_config }
    describe 'Consul Agent Binary' do
      subject { file('/usr/local/bin/consul') }
      it { is_expected.to exist }
      it { is_expected.to be_file }
      it { is_expected.to be_owned_by 'root' }
      it { is_expected.to be_grouped_into consul_agent_group['name'] }
      it { is_expected.to be_mode 755 }
    end
    describe 'Consul Agent version installed' do
      subject { command('/usr/local/bin/consul --version') }
      its(:stdout) { should match(/Consul v#{Regexp.escape(property['consul_agent_version'])}$/) }
    end
  end
end
