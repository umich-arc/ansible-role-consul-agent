# -*- encoding: utf-8 -*-
# frozen_string_literal: true

require 'aws-sdk'
require 'rake'
require 'rspec'
require 'kitchen/rake_tasks'

task default: 'test:vagrant'

def task_runner(config, suite_name, action, concurrency) # rubocop:disable Metrics/MethodLength
  task_queue = Queue.new
  instances = config.instances.select { |obj| obj.suite.name =~ /^#{suite_name}$/ }
  instances.each { |i| task_queue << i }
  workers = (0...concurrency).map do
    Thread.new do
      begin
        while instance = task_queue.pop(true) # rubocop:disable Lint/AssignmentInCondition
          instance.send(action)
        end
      rescue ThreadError # rubocop:disable Lint/HandleExceptions
      end
    end
  end
  workers.map(&:join)
end

namespace :integration do
  aws_env_vars = %w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SSH_KEY_ID
                    AWS_SGROUP_ID AWS_REGION KITCHEN_SSH_KEY)
  missing_aws_vars = []

  aws_env_vars.each do |aws_var|
    ENV.key?(aws_var) || missing_aws_vars.push(aws_var)
  end

  Kitchen.logger = Kitchen.default_file_logger

  desc 'Execute all test suites using the Vagrant Provider'
  task :vagrant do
    @loader = Kitchen::Loader::YAML.new(local_config: '.kitchen.yml')
    config = Kitchen::Config.new(loader: @loader)
    concurrency = (ENV['concurrency'] || '1').to_i
    task_runner(config, '.*', 'test', concurrency)
  end

  namespace :vagrant do
    @loader = Kitchen::Loader::YAML.new(local_config: '.kitchen.yml')
    config = Kitchen::Config.new(loader: @loader)
    concurrency = (ENV['concurrency'] || '1').to_i

    desc 'Execute the Vagrant test suite for Consul Agent.'
    task :consul do
      task_runner(config, 'consul-agent', 'test', concurrency)
    end

    desc 'Destroy all Vagrant instances.'
    task :destroy do
      task_runner(config, '.*', 'destroy', concurrency)
    end
  end

  if missing_aws_vars.empty?

    desc 'Execute all test suites using the Cloud Provider'
    task :cloud do
      @loader = Kitchen::Loader::YAML.new(local_config: '.kitchen.cloud.yml')
      config = Kitchen::Config.new(loader: @loader)
      concurrency = (ENV['concurrency'] || '10').to_i
      task_runner(config, '.*', 'test', concurrency)
    end

    namespace :cloud do
      @loader = Kitchen::Loader::YAML.new(local_config: '.kitchen.cloud.yml')
      config = Kitchen::Config.new(loader: @loader)
      concurrency = (ENV['concurrency'] || '10').to_i

      desc 'Execute the Cloud test suite for the Consul Agent.'
      task :consul do
        task_runner(config, 'consul-agent', 'test', concurrency)
      end

      desc 'Destroy all Cloud instances.'
      task :destroy do
        task_runner(config, '.*', 'destroy', concurrency)
      end

      desc 'Destroys ALL cloud instances and volumes in the security group.'
      task :'sgroup-destroy' do
        aws_creds = Aws::Credentials.new(ENV['AWS_ACCESS_KEY_ID'], ENV['AWS_SECRET_ACCESS_KEY'])
        ec2_client = Aws::EC2::Client.new(region: ENV['AWS_REGION'], credentials: aws_creds)
        ec2 = Aws::EC2::Resource.new(client: ec2_client)
        instance_filter = [
          { name: 'instance.group-id', values: [ENV['AWS_SGROUP_ID']] },
          { name: 'instance-state-name', values: %w(running pending) }
        ]
        destroy_instances = []
        destroy_volumes = []
        ec2_instances = ec2.instances(filters: instance_filter)
        ec2_instances.each do |instance|
          destroy_instances.push(instance.instance_id)
          instance.volumes.each do |volume|
            destroy_volumes.push(volume.volume_id)
          end
          puts "Sending Terminate request for instance: #{instance.instance_id}"
          instance.terminate
        end
        unless destroy_instances.empty?
          ec2_client.wait_until(:instance_terminated, instance_ids: destroy_instances) do |w|
            w.before_attempt do
              puts 'Polling for instance termination...'
            end
          end
        end
        destroy_volumes.each do |volume_id|
          begin
            puts "Deleting volume: #{volume_id}"
            ec2_client.delete_volume(volume_id: volume_id)
          rescue Aws::EC2::Errors::InvalidVolumeNotFound
            next
          end
        end
        unless destroy_volumes.empty?
          ec2_client.wait_until(:volume_deleted, volume_ids: destroy_volumes) do |w|
            w.before_attempt do
              puts 'Polling for volume deletion...'
            end
          end
        end
      end
    end
  end
end
