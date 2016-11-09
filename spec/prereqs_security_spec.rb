# -*- encoding: utf-8 -*-
# frozen_string_literal: true

require 'spec_helper'
require 'support/security'

if property['consul_agent_manage_gossip_encryption'] || property['consul_agent_manage_acls']
  consul_agent_sec_cfg = consul_agent_security_config
  sec_skip = false
  sec_skip = true if consul_agent_sec_cfg.nil?
  # skip attempting to run these tests if no config can be loaded
  RSpec.describe ENV['KITCHEN_INSTANCE'] || host_inventory['hostname'], skip: sec_skip do
    context 'CONSUL_AGENT:PREREQS:SECURITY' do
      describe 'Security Config File' do
        subject { file(property['consul_agent_security_config_file']['path']) }
        it { is_expected.to be_file }
        it { is_expected.to be_owned_by property['consul_agent_security_config_file']['owner'] }
        it do
          is_expected.to be_grouped_into property['consul_agent_security_config_file']['group']
        end
        it { is_expected.to be_mode property['consul_agent_security_config_file']['mode'].to_i }
        it 'should have the correct json schema' do
          expect(consul_agent_sec_cfg).to have_key('encrypt')
          expect(consul_agent_sec_cfg).to have_key('acl')
          expect(consul_agent_sec_cfg['acl']).to have_key('acls')
          expect(consul_agent_sec_cfg['acl']).to have_key('master_token')
          expect(consul_agent_sec_cfg['acl']).to have_key('uuid')
        end
      end
    end

    if property['consul_agent_manage_gossip_encryption']
      context 'CONSUL_AGENT:PREREQS:SECURITY:GOSSIP' do
        describe 'Gossip Encryption Key' do
          it 'should be a 16-byte base64 value' do
            expect(consul_agent_sec_cfg['encrypt']).to match(/^[0-9a-z]{22}==$/i)
          end
        end
      end
    end
    if property['consul_agent_manage_acls']
      context 'CONSUL_AGENT:PREREQS:SECURITY:ACLS' do
        describe 'ACL Master Token' do
          let(:uuid_match) do
            Regexp.new(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/)
          end
          it 'should be a uuid' do
            # This isn't 100% accurate for uuids, but gets the job done.
            expect(consul_agent_sec_cfg['acl']['master_token']).to match(uuid_match)
          end
        end
      end
    end
  end
end
