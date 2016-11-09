Testing and Contributing
------------------------
## Index
* [Overview](#overview)
* [Style Suggestions](#style-suggestions)
* [Testing Prerequisites](#testing-prerequisites)
* [Testing with Vagrant](#testing-with-vagrant)
* [Testing with AWS](#testing-with-aws)
* [Rake Tasks](#rake-tasks)
* [CI Integration](#ci-integration)



#### Overview

Testing and verification is done with a combination of several tools. All roles should pass the in-build idempotency test (executing twice with no changes), and then pass all integration tests with [test-kitchen](http://kitchen.ci/)and [serverspec](http://serverspec.org/) on all supplied platforms.

For full playbook testing, the role spec file should conform with [ansiblespec](https://github.com/volanja/ansible_spec). (See included  [spec/spec_helper.rb](spec/_spec_helper.rb) for guidance.)

Full usage of these tools is out of scope for this document; however usage is well documented at the sites linked to above.

#### Style Suggestions
* All tasks should be named.
* Lines within tasks should not exceed 120 characters. Use of `|` or `>` can generally be used to achieve this.
* Avoid using variable names that could possibly collide with something else. e.g. prefixing variables not intended for use outside of a role with an `_`.
* Avoid extraneous whitespace e.g. `foo[ bar ]` vs. `foo[bar]` excluding jinja brackets ( `{{ }}`, `{% %}` etc).
* When possible, use single quotes `'` over double quotes `"`.
* If adding a feature, add associated test. Alternatively, request assistance in writing appropriate tests.


#### Testing Prerequisites
* Ruby (1.9.1 or greater)
* Bundler
* [Vagrant](https://www.vagrantup.com/downloads.html) or an AWS Account
* [Virtualbox](https://www.virtualbox.org/wiki/Downloads) (if using Vagrant)


#### Testing with Vagrant
1. Within the project directory, execute `bundle install` to install all gem prerequisites.
2. The command `kitchen list` will supply a list of all available testing suites and platforms.
3. Perform a converge on a given suite with `kitchen converge <suite-name>-<platform>`. A converge will install ansible and execute the associated playbook with the suite name on the target.
4. Verify that the role executed as intended with `kitchen verify <suite-name>-<platform>`. This will verify that everything executed as intended following the defined tests in the spec file (`spec/*_spec.rb`).
5. Destroy the system with the command `kitchen destroy <suite-name>-<platform>`.


#### Testing with AWS
Test kitchen uses the [kitchen-aws](https://github.com/test-kitchen/kitchen-ec2) driver for provising systems within AWS. Before executing any tests, there are 5 environment variables that must be set.

|      Variable Name      |                                           Description                                           |
|:-----------------------:|:-----------------------------------------------------------------------------------------------:|
|   `AWS_ACCESS_KEY_ID`   |                                         AWS access key.                                         |
| `AWS_AVAILABILITY_ZONE` |               The availability zone within th aws region specified by `AWS_REGION`              |
|   `AWS_INSTANCE_TYPE`   |             The instance type to be used for test execution. Defaults to `t2.micro`             |
|       `AWS_REGION`      |                       The aws region used for execution. e.g. `us-west-2`                       |
| `AWS_SECRET_ACCESS_KEY` |                      AWS secret key associated with the `AWS_ACCESS_KEY_ID`                     |
|     `AWS_SGROUP_ID`     | The ec2 security group associated with the vpc that the test-kitchen will use to run instances. |
|     `AWS_SSH_KEY_ID`    |                   The ID of the AWS key pair used to configured the instances.                  |
|    `KITCHEN_SSH_KEY`    |        The name or full path to the aws private key associated with the `AWS_SSH_KEY_ID`        |

After doing so, rename the `.kitchen.cloud.yml` file to `.kitchen.yml`.

At this point, the execution environment will be changed and the instructions used for vagrant will now be applicable.

#### Rake Tasks

The role contains a Rakefile with series of tasks for executing each suite on all platforms. They are viewable with the command:
`bundle exec rake --tasks`. Each Rake task is in the form of `<test type>:<driver>:<suite>`.

The default task that would be executed with `bundle exec rake` will execute all tests (`integration:vagrant`) with the vagrant driver.

The tasks associated with the AWS driver are only available if the AWS environment variables are set.

Concurrency of the tests may be set by providing an environment variable in the form `CONCURRENCY=<execution thread count>`. The default concurrency using the vagrant driver is 1, and 10 for AWS.

**Note:** When an AWS task fails, depending on the point at which it failed, executing a `kitchen destroy` or `bundle exec rake integration:cloud:destroy` may not fully remove the instances or volumes. There are two alternatives that can provide a more consistent method of removal. `integration:cloud:tagged-destroy` and `integration:cloud:sgroup-destroy`. a `tagged-destroy` will destroy all instances and volumes tagged with `ansible-role=<role-name>`. An `sgroup-destroy` is the more destructive option that will destroy all instances and volumes within a vpc that matches the security group via the instance filter: `instance.group-id`.

The `sgroup-destroy` is the best option if dedicating a specific vpc or security group for each individual role test.


#### CI Integration
The supplied spec_helper supports outputting serverspec results as junit xml files for consumption by a CI system (e.g. Jenkins) by setting the environment variable `RSPEC_FORMAT` to `junit`. These files will placed in the same directory as role and be titled `<suite>-<platform>.junit.xml`.


