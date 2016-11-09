# -*- encoding: utf-8 -*-
# frozen_string_literal: true

require 'spec_helper'
require 'support/config'
require 'support/security'
require 'support/users_and_groups'

def service_def_path
  return '/etc/init/consul.conf' if os[:family] == 'ubuntu' &&
                                    os[:release].split('.').first == '14'
  '/lib/systemd/system/consul.service'
end

RSpec.describe ENV['KITCHEN_INSTANCE'] || host_inventory['hostname'] do
  context 'CONSUL_AGENT:CONFIG' do
    consul_agent_sec_cfg = consul_agent_security_config
    sec_skip = false
    sec_skip = true if consul_agent_sec_cfg.nil?
    consul_agent_opts =
      gen_consul_agent_opts(opts: property['consul_agent_opts'],
                            sec_conf: consul_agent_sec_cfg,
                            sec_skip: sec_skip)
    consul_agent_config =
      gen_consul_agent_config(conf: property['consul_agent_config'],
                              opts: consul_agent_opts,
                              sec_conf: consul_agent_sec_cfg,
                              sec_skip: sec_skip)
    let(:consul_agent_group) { gen_consul_group_config }
    let(:consul_agent_user) { gen_consul_user_config }
    if property['consul_agent_config_dir']
      describe 'Consul Agent Config Directory' do
        subject { file(property['consul_agent_config_dir']) }
        it { is_expected.to be_directory }
        it { is_expected.to be_owned_by 'root' }
        it { is_expected.to be_grouped_into consul_agent_group['name'] }
        it { is_expected.to be_mode 770 }
      end
    end
    if property['consul_agent_data_dir']
      describe 'Consul Agent Data Directory' do
        subject { file(property['consul_agent_data_dir']) }
        it { is_expected.to be_directory }
        it { is_expected.to be_owned_by consul_agent_user['name'] }
        it { is_expected.to be_grouped_into consul_agent_group['name'] }
        it { is_expected.to be_mode 770 }
      end
    end
    if property['consul_agent_scripts_dir']
      describe 'Consul Agent Scripts Directory' do
        subject { file(property['consul_agent_scripts_dir']) }
        it { is_expected.to be_directory }
        it { is_expected.to be_owned_by consul_agent_user['name'] }
        it { is_expected.to be_grouped_into consul_agent_group['name'] }
        it { is_expected.to be_mode 770 }
      end
    end
    if property['consul_agent_certs_dir']
      describe 'Consul Agent Certificates Directory' do
        subject { file(property['consul_agent_certs_dir']) }
        it { is_expected.to be_directory }
        it { is_expected.to be_owned_by consul_agent_user['name'] }
        it { is_expected.to be_grouped_into consul_agent_group['name'] }
        it { is_expected.to be_mode 700 }
      end
    end
    if property['consul_agent_manage_rpc_encryption']
      context 'Consul Managed Certificates' do
        describe 'CA Certificate' do
          subject { file("#{property['consul_agent_certs_dir']}/ca.crt") }
          it { is_expected.to exist }
          it { is_expected.to be_file }
          it { is_expected.to be_owned_by consul_agent_user['name'] }
          it { is_expected.to be_grouped_into consul_agent_group['name'] }
          it { is_expected.to be_mode 644 }
        end
        describe 'Consul Agent Certificate' do
          subject { file("#{property['consul_agent_certs_dir']}/consul.crt") }
          it { is_expected.to exist }
          it { is_expected.to be_file }
          it { is_expected.to be_owned_by consul_agent_user['name'] }
          it { is_expected.to be_grouped_into consul_agent_group['name'] }
          it { is_expected.to be_mode 644 }
        end
        describe 'Consul Agent Key' do
          subject { file("#{property['consul_agent_certs_dir']}/consul.key") }
          it { is_expected.to exist }
          it { is_expected.to be_file }
          it { is_expected.to be_owned_by consul_agent_user['name'] }
          it { is_expected.to be_grouped_into consul_agent_group['name'] }
          it { is_expected.to be_mode 640 }
        end
        describe 'Certificate validated by CA' do
          let(:ca_path) { "#{property['consul_agent_certs_dir']}/ca.crt" }
          let(:cert_path) { "#{property['consul_agent_certs_dir']}/consul.crt" }
          subject { command("openssl verify -CAfile #{ca_path} #{cert_path}") }
          its(:stdout) { is_expected.to match('consul.crt: OK') }
        end
      end
    end
    if property['consul_agent_scripts']
      context 'Synched Check Scripts' do
        property['consul_agent_scripts'].each do |script|
          describe file("#{property['consul_agent_scripts_dir']}/#{File.basename(script)}") do
            it { is_expected.to exist }
            it { is_expected.to be_file }
            it { is_expected.to be_owned_by consul_agent_user['name'] }
            it { is_expected.to be_grouped_into consul_agent_group['name'] }
            it { is_expected.to be_mode 770 }
          end
        end
      end
    end
    describe 'Consul Agent Config File' do
      let(:consul_conf) { fetch_conf("#{property['consul_agent_config_dir']}/config.json") }
      subject { file("#{property['consul_agent_config_dir']}/config.json") }
      it { is_expected.to exist }
      it { is_expected.to be_file }
      it { is_expected.to be_owned_by consul_agent_user['name'] }
      it { is_expected.to be_grouped_into consul_agent_group['name'] }
      it { is_expected.to be_mode 770 }
      it 'should match content with generated config' do
        expect(consul_agent_config).to eq(consul_conf)
      end
    end
    if property['consul_agent_checks']
      describe 'Consul Agent Checks Config' do
        let(:checks_conf) { fetch_conf("#{property['consul_agent_config_dir']}/checks.json") }
        subject { file("#{property['consul_agent_config_dir']}/checks.json") }
        it { is_expected.to exist }
        it { is_expected.to be_file }
        it { is_expected.to be_owned_by consul_agent_user['name'] }
        it { is_expected.to be_grouped_into consul_agent_group['name'] }
        it { is_expected.to be_mode 770 }
        it 'should match content with generated config' do
          expect(property['consul_agent_checks']).to eq(checks_conf)
        end
      end
    end
    if property['consul_agent_services']
      describe 'Consul Agent Services Config' do
        let(:service_conf) { fetch_conf("#{property['consul_agent_config_dir']}/services.json") }
        subject { file("#{property['consul_agent_config_dir']}/services.json") }
        it { is_expected.to exist }
        it { is_expected.to be_file }
        it { is_expected.to be_owned_by consul_agent_user['name'] }
        it { is_expected.to be_grouped_into consul_agent_group['name'] }
        it { is_expected.to be_mode 770 }
        it 'should match content with generated config' do
          expect(property['consul_agent_services']).to eq(service_conf)
        end
      end
    end
    describe 'Consul Agent Service Definition' do
      subject { file(service_def_path) }
      it { is_expected.to exist }
      it { is_expected.to be_file }
      it { is_expected.to be_owned_by 'root' }
      it { is_expected.to be_grouped_into 'root' }
      it { is_expected.to be_mode 644 }
    end
    describe 'Consul Agent Service Status' do
      subject { service('consul') }
      it { should be_enabled }
      it { should be_running }
    end
    describe 'Consul Agent Process should have the arguments' do
      subject { process('consul') }
      consul_agent_opts.each do |k, v|
        if v.nil?
          its(:args) { should match("-#{k}") }
        else
          v.each do |opt|
            its(:args) { should match("-#{k}=#{opt}") }
          end
        end
      end
    end
  end
end
