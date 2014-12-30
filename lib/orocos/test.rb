require 'minitest/autorun'
require 'minitest/spec'
require 'flexmock/test_unit'

# simplecov must be loaded FIRST. Only the files required after it gets loaded
# will be profiled !!!
if ENV['TEST_ENABLE_COVERAGE'] == '1'
    begin
        require 'simplecov'
        SimpleCov.start
        pid = Process.pid
        SimpleCov.at_exit do
        end
        Minitest.after_run do
            SimpleCov.result.format!
        end
    rescue LoadError
        require 'orocos'
        Orocos.warn "coverage is disabled because the 'simplecov' gem cannot be loaded"
    rescue Exception => e
        require 'orocos'
        Orocos.warn "coverage is disabled: #{e.message}"
    end
elsif ENV['TEST_ENABLE_PRY'] != '0'
    begin
        require 'pry'
        if ENV['TEST_DEBUG'] == '1'
            require 'pry-rescue/minitest'
        end
    rescue Exception
        require 'orocos'
        Orocos.warn "debugging is disabled because the 'pry' gem cannot be loaded"
    end
end

if ENV['TEST_ENABLE_PRY'] != '0'
    begin
        require 'pry'
    rescue Exception
        Orocos.warn "debugging is disabled because the 'pry' gem cannot be loaded"
    end
end

require 'orocos'
require 'orocos/rake'
require 'orocos/test/mocks'
require 'orocos/test/ruby_tasks'

module Orocos
    module SelfTest
        include Test::Mocks
        include Test::RubyTasks

        # A set of "modes" that can be used to control how the tests will be
        # performed
        TEST_MODES = (ENV['OROCOS_TEST_MODES'] || "").split(',')
        # Test without models
        TEST_MODEL_LESS = TEST_MODES.include?('no_model')
        # Test with models that cannot be loaded
        TEST_MISSING_MODELS = TEST_MODES.include?('missing_model')
        # Whether we should enable MQ support during tests
        USE_MQUEUE = Orocos::Rake::USE_MQUEUE

        if defined? FlexMock
            include FlexMock::ArgumentTypes
            include FlexMock::MockContainer
        end

        def work_dir; File.join(@test_dir, 'working_copy') end
        def data_dir; File.join(@test_dir, 'data') end

        def setup
            @old_pkg_config_path = ENV['PKG_CONFIG_PATH'].dup
            @__warn_for_missing_default_loggers = Orocos.warn_for_missing_default_loggers?
            Orocos.warn_for_missing_default_loggers = false
            Orocos::MQueue.auto = USE_MQUEUE

            @test_dir = File.expand_path(File.join("..", "..", 'test'), File.dirname(__FILE__))

            # Since we are loading typekits over and over again, we need to
            # disable type export
            Orocos.export_types = false
            if File.directory?(work_dir)
                Orocos.default_working_directory = work_dir
                ENV['PKG_CONFIG_PATH'] += ":#{File.join(work_dir, "prefix", 'lib', 'pkgconfig')}"
                Orocos.default_pkgconfig_loader.update
            end

            if defined?(Orocos::Async)
                Orocos::Async::NameServiceBase.default_period = 0
                Orocos::Async::TaskContextBase.default_period = 0
                Orocos::Async::CORBA::Attribute.default_period = 0
                Orocos::Async::CORBA::Property.default_period = 0
                Orocos::Async::CORBA::OutputReader.default_period = 0
            end

            @processes = Array.new

            Orocos.initialize
            @__orocos_corba_timeouts = [Orocos::CORBA.call_timeout, Orocos::CORBA.connect_timeout]
            Orocos::CORBA.call_timeout = 10000
            Orocos::CORBA.connect_timeout = 10000

	    if TEST_MODEL_LESS
		flexmock(Orocos::TaskContext).new_instances(:get_from_ior).should_receive('model').and_return(nil)
		flexmock(Orocos::TaskContext).new_instances(:do_get).should_receive('model').and_return(nil)
	    elsif TEST_MISSING_MODELS
		flexmock(Orocos).should_receive(:task_model_from_name).and_raise(Orocos::NotFound)
	    end
            super
        end

        def teardown
            if defined? FlexMock
                flexmock_teardown
            end
            processes.each do |p|
                begin p.kill
                rescue Exception => e
                    Orocos.warn "failed, in teardown, to stop process #{p}: #{e}"
                end
            end
            processes.clear
            super
            if @__orocos_corba_timeouts # can be nil if setup failed
                Orocos::CORBA.call_timeout, Orocos::CORBA.connect_timeout = *@__orocos_corba_timeouts
            end
            if @old_pkg_config_path # can be nil if setup failed
                ENV['PKG_CONFIG_PATH'] = @old_pkg_config_path
            end
            Orocos::CORBA.instance_variable_set :@loaded_typekits, []
            Orocos.clear
            Orocos.warn_for_missing_default_loggers = @__warn_for_missing_default_loggers
        end

        attr_reader :processes

        def start(*spec)
            processes.concat Orocos.run(*spec)
        end

        def get(name)
            Orocos.get name
        end

        def spawn_and_get(component, task = component)
            begin
                process = Orocos::Process.new component
                process.spawn
                process.wait_running(0.5)
            rescue Exception
                process.kill if process
                raise
            end

            processes << process
            Orocos::TaskContext.get "#{component}.#{task}"
        end

        def read_one_sample(reader, timeout = 1)
            Integer(timeout / 0.01).times do
                if value = reader.read_new
                    return value
                end
                sleep 0.01

            end
            flunk("expected to receive one new sample on #{reader}, but got none (state: #{reader.port.task.rtt_state}")
        end

        def assert_state_equals(state, task, timeout = 1)
            expected_toplevel = task.toplevel_state(state)
            toplevel = task.rtt_state
            if expected_toplevel != toplevel
                flunk("#{task} was expected to be in toplevel state #{expected_toplevel} because of #{state} but is in #{toplevel}")
            end

            Integer(timeout / 0.01).times do
                if task.state == state
                    return
                end
                sleep 0.01
            end
            flunk("#{task} was expected to be in state #{state} but is in #{task.state}")
        end

        def wait_for(timeout = 5, &block)
            Orocos::Async.wait_for(0.005, timeout, &block)
        end

        def name_service
            Orocos.name_service
        end

        # helper for generating an ior from a name
        def ior(name)
            name_service.ior(name)
        rescue Orocos::NotFound
            "IOR:010000001f00000049444c3a5254542f636f7262612f435461736b436f6e746578743a312e300000010000000000000064000000010102000d00000031302e3235302e332e31363000002bc80e000000fe8a95a65000004d25000000000000000200000000000000080000000100000000545441010000001c00000001000000010001000100000001000105090101000100000009010100"
        end
    end
end

# Workaround a problem with flexmock and minitest not being compatible with each
# other (currently). See github.com/jimweirich/flexmock/issues/15.
if defined?(FlexMock) && !FlexMock::TestUnitFrameworkAdapter.method_defined?(:assertions)
    class FlexMock::TestUnitFrameworkAdapter
        attr_accessor :assertions
    end
    FlexMock.framework_adapter.assertions = 0
end

module Minitest
    class Test
        include Orocos::SelfTest
    end
end

