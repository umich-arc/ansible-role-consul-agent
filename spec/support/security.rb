# -*- encoding: utf-8 -*-
# frozen_string_literal: true

require 'json'
require 'spec_helper'
require 'specinfra'

def consul_agent_security_config
  if File.file?(property['consul_agent_security_config_file']['path'])
    sec_cfg = JSON.parse(File.read(property['consul_agent_security_config_file']['path']))
    return sec_cfg['consul_agent_sec_cfg']
  else
    sec_cfg = fetch_consul_sec_cfg
    return sec_cfg['consul_agent_sec_cfg'] unless sec_cfg.nil?
  end
  nil
end

def sec_cfg_exist?
  cmd = Specinfra.command.get(:check_file_is_file,
                              property['consul_agent_security_config_file']['path'])
  return true if Specinfra.backend.run_command(cmd).exit_status == 0
  false
end

def fetch_consul_sec_cfg
  if sec_cfg_exist?
    cmd = Specinfra.command.get(:get_file_content,
                                property['consul_agent_security_config_file']['path'])
    return JSON.parse(Specinfra.backend.run_command(cmd).stdout)
  end
  nil
end
