module Orocos
    module Test
        # Support for using ruby tasks in tests
        module RubyTasks
            def setup
                @allocated_task_contexts = Array.new
                super
            end

            def teardown
                super
                @allocated_task_contexts.each(&:dispose)
            end

            def new_ruby_task_context(name, options = Hash.new, &block)
                task = Orocos::RubyTasks::TaskContext.new(name, options, &block)
                @allocated_task_contexts << task
                task
            end
        end
    end
end

