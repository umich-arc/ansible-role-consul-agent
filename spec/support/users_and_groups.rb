# -*- encoding: utf-8 -*-
# frozen_string_literal: true

require 'spec_helper'

def gen_consul_user_config
  user = property['_consul_agent_user_defaults']
  return user.merge!(property['consul_agent_user']) if
    property.key?('consul_agent_user')
  user
end

def gen_consul_group_config
  group = property['_consul_agent_group_defaults']
  return group.merge!(property['consul_agent_group']) if
    property.key?('consul_agent_group')
  group
end
