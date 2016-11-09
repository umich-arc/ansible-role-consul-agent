# -*- encoding: utf-8 -*-
# frozen_string_literal: true

require 'spec_helper'
require 'support/security'

if property['consul_agent_manage_acls']
  consul_agent_sec_cfg = consul_agent_security_config
  sec_skip = false
  sec_skip = true if consul_agent_sec_cfg.nil?
  # skip attempting to run these tests if no config can be loaded
  RSpec.describe ENV['KITCHEN_INSTANCE'] || host_inventory['hostname'], skip: sec_skip do
    context 'CONSUL_AGENT:ACLS' do
      describe 'ACL Config' do
        it 'should match generated security config' do
          expect(property['consul_agent_acls']).to eq(consul_agent_sec_cfg['acl']['acls'])
        end
        it 'should have a uuid for each acl' do
          expect(property['consul_agent_acls'].keys).to eq(
            consul_agent_sec_cfg['acl']['uuid'].keys
          )
          consul_agent_sec_cfg['acl']['uuid'].each do |_, v|
            expect(v).to match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/)
          end
        end
      end
    end
  end
end
