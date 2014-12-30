require 'orocos'
require 'orocos/test/ruby_tasks'
require 'utilrb/module/include'

module Orocos
    module Test
        module Component
            include Test::RubyTasks

            attribute(:processes)  { Array.new }
            attribute(:data_readers)  { Array.new }
            attribute(:data_writers) { Array.new }
            def setup
                if !Orocos.initialized?
                    Orocos.initialize
                end

                self.class.run_specs.each do |name, task_name, run_spec|
                    start(run_spec)
                    instance_variable_set("@#{name}", Orocos.name_service.get(task_name))
                end

                self.class.reader_specs.each do |task_name, port_name, reader_name, policy|
                    reader = self.data_reader(send(task_name).port(port_name), policy)
                    instance_variable_set("@#{reader_name}", reader)
                end
                self.class.writer_specs.each do |task_name, port_name, writer_name, policy|
                    writer = self.data_writer(send(task_name).port(port_name), policy)
                    instance_variable_set("@#{writer_name}", writer)
                end
                super if defined? super
            end

            def teardown
                data_readers.each { |r| r.disconnect }
                data_readers.clear
                data_writers.each { |w| w.disconnect }
                data_writers.clear
                processes.each { |p| p.kill }
                processes.clear
                super if defined? super
            end

            # Verify that no sample arrives on +reader+ within +timeout+ seconds
            def assert_has_no_new_sample(reader, timeout = 0.2)
                sleep timeout
                assert(!reader.read_new, "#{reader} has one new sample, but none was expected")
            end

            # Verifies that +reader+ gets one sample within +timeout+ seconds
            def assert_has_one_new_sample(reader, timeout = 3, poll_period = 0.01)
                Integer(timeout / poll_period).times do
                    if sample = reader.read_new
                        return sample
                    end
                    sleep poll_period
                end
                flunk("expected to get one new sample out of #{reader.port.name}, but got none")
            end

            # call-seq:
            #   assert_state_change(task, timeout = 1) { |state|   test_if_state_is_the_expected_state }
            #   
            # Tests if the state of +task+ changes to an expected value.  The
            # block should return whether the passed state is the expected state
            # or not.
            def assert_state_change(task, timeout = 1)
                sleep_time = Float(timeout) / 10
                10.times do
                    queued_state_changes = task.peek_state
                    if queued_state_changes.any? { |s| yield(s) }
                        return
                    end
                    sleep sleep_time
                end

                flunk("could not find the expected state change for #{task.name} in #{task.peek_state.inspect}")
            end

            # call-seq:
            #   start 'model_name', 'task_name'
            #   start 'deployment_name', 'task_name'[, 'prefix']
            #
            # Requires the unit test to start a deployment/task at the point of
            # the call, and make sure to shut it down during teardown. In test
            # methods, the task object is made accessible with the
            # 'attribute_name' attribute
            #
            # In the first form, the task is given through its model. The
            # global task name is registered with 'task_name', which defaults
            # to 'attribute_name'
            #
            # In the second form, the task is given through a deployment
            # name / task name pair. If a prefix is given, task_name must
            # include the prefix as well, i.e.:
            #
            #   start 'task', 'rock_logger', 'source_logger', 'source'
            #
            # where 'logger' is a task of the 'rock_logger' deployment.
            #
            # For instance:
            #
            #   describe 'xsens_imu::Task' do
            #       include Orocos::Test::Component
            #
            #       it "should fail to configure if no device is present" do
            #         start 'xsens_imu::Task' => 'task'
            #         task = Orocos.name_service.get 'task'
            #         task.device = ""
            #         assert_raises(Orocos::StateTransitionFailed) { task.configure }
            #       end
            #   end
            #
            def start(*args)
                processes.concat(Orocos.run(*args))
                nil
            end

            # Gets the data reader for this port. It gets disconnected on
            # teardown
            def data_reader(port, policy = Hash.new)
                reader = port.reader(policy)
                data_readers << reader
                reader
            end

            # Gets the data writer for this port. It gets disconnected on
            # teardown
            def data_writer(port, policy = Hash.new)
                writer = port.writer(policy)
                data_writers << writer
                writer
            end

            # Support module for declarations in tests
            module ClassExtension
                attribute(:run_specs) { Array.new }
                attribute(:reader_specs) { Array.new }
                attribute(:writer_specs) { Array.new }

                # Starts a new task context on test setup and assigns it to a local variable
                #
                # @overload start(attr_name, task_name, run_spec)
                #   @param [String,Symbol] attr_name the attribute name
                #   @param [String] task_name the name of the orocos task that
                #     should be assigned to 
                #   @param [Hash] run_spec arguments that should be passed to
                #     {Orocos.run}. Once Orocos.run is called, there should
                #     exists a task called task_name
                #
                # @overload start(attr_name, run_spec)
                #   @param [String,Symbol] attr_name the attribute name as well
                #     as the orocos task name. See above.
                #   @param [Hash] run_spec arguments that should be passed to
                #     {Orocos.run}. Once Orocos.run is called, there should
                #     exists a task called attr_name
                #
                # Requires the unit test to start a deployment/task at startup
                # and shut it down during teardown. In test methods, the task
                # object can be accessed as the attr_name attribute
                #
                # @example start a task context and tests that configuration fails
                #
                #   require 'minitest/spec'
                #   require 'orocos/test/component'
                #   describe 'xsens_imu::Task' do
                #     include Orocos::Test::Component
                #     start 'task', 'xsens_imu::Task' => 'task'
                #
                #     def test_configure_fails_if_no_device_is_present
                #       task.device = ""
                #       assert_raises(Orocos::StateTransitionFailed) { task.configure }
                #     end
                #   end
                #
                def start(attr_name, *options)
                    attr_reader attr_name
                    if options.size == 2
                        run_specs << [attr_name, *options]
                    elsif options.size == 1
                        run_specs << [attr_name, attr_name, *options]
                    else
                        raise ArgumentError, "expected two or three arguments, got #{options.size}"
                    end
                end

                def reader(name, port_name, options = Hash.new)
                    if options.respond_to?(:to_str)
                        options = { :attr_name => options }
                    end
                    options, policy = Kernel.filter_options options,
                        :attr_name => "#{name}_#{port_name}"
                    attr_reader options[:attr_name]
                    reader_specs << [name, port_name, options[:attr_name], policy]
                end

                def writer(name, port_name, options = Hash.new)
                    if options.respond_to?(:to_str)
                        options = { :attr_name => options }
                    end
                    options, policy = Kernel.filter_options options,
                        :attr_name => "#{name}_#{port_name}"
                    attr_reader options[:attr_name]
                    writer_specs << [name, port_name, options[:attr_name], policy]
                end
            end
        end
    end
end
