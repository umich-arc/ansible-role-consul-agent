# -*- encoding: utf-8 -*-
# frozen_string_literal: true

require 'json'
require 'specinfra'
require 'spec_helper'

def gen_consul_agent_config(conf:, opts:, sec_conf:, sec_skip:)
  unless sec_skip
    conf.update(encrypt: sec_conf['encrypt']) if sec_conf.key?('encrypt')
    conf.update(rpc_config) if property['consul_agent_manage_rpc_encryption']
    conf.update(acl_config(conf, opts, sec_conf)) if property['consul_agent_manage_acls']
  end
  # This converts any possible symbols to strings before returning
  Hash[conf.map { |k, v| [k.to_s, v] }]
end

def gen_consul_agent_opts(opts:, sec_conf:, sec_skip:)
  unless sec_skip
    opts.update('encrypt': [sec_conf['encrypt']]) unless property['consul_agent_config']
  end
  opts
end

def rpc_config
  {
    ca_file: "#{property['consul_agent_certs_dir']}/ca.crt",
    cert_file: "#{property['consul_agent_certs_dir']}/consul.crt",
    key_file: "#{property['consul_agent_certs_dir']}/consul.key"
  }
end

def acl_config(conf, opts, sec_conf)
  acl_conf = {}
  acl_conf.update('acl_master_token': sec_conf['acl']['master_token'])
  acl_conf.update('acl_datacenter': dc?(conf, opts)) unless conf.key?('acl_datacenter')
  acl_conf
end

def dc?(conf, opts)
  return opts['dc'][0] if opts.key?('dc')
  return conf['dc'] if conf.key?('dc')
  'dc1'
end

def fetch_conf(path)
  cmd = Specinfra.command.get(:get_file_content, path.to_s)
  ret = Specinfra.backend.run_command(cmd)
  JSON.parse(ret.stdout)
end
