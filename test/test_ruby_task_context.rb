require 'orocos/test'

describe Orocos::RubyTasks::TaskContext do
    it "should be registered on the name server" do
        task = new_ruby_task_context("task")
        assert Orocos.name_service.get("task")
    end

    it "should refer to a LocalTaskContext object that refers to it back" do
        task = new_ruby_task_context("task")
        assert_same task, task.instance_variable_get(:@local_task).remote_task
    end

    it "can create output ports" do
        task = new_ruby_task_context("producer")
        port = task.create_output_port("p", "/int32_t")
        assert_kind_of Orocos::OutputPort, port
        assert_equal task, port.task
        assert_equal "p", port.name

        assert task.has_port?("p")
        assert_kind_of Orocos::OutputPort, task.port("p")
        assert_equal "/int32_t", task.port("p").orocos_type_name
    end

    it "can create input ports" do
        task = new_ruby_task_context("producer")
        port = task.create_input_port("p", "/int32_t")

        assert_kind_of Orocos::InputPort, port
        assert task.has_port?("p")
        assert_kind_of Orocos::InputPort, task.port("p")
        assert_equal "/int32_t", task.port("p").orocos_type_name
    end

    it "can write and read on ports" do
        producer = new_ruby_task_context("producer")
        out_p = producer.create_output_port("p", "/int32_t")
        consumer = new_ruby_task_context("consumer")
        in_p = consumer.create_input_port("p", "/int32_t")

        out_p.connect_to in_p
        out_p.write 10
        assert_equal 10, in_p.read
    end

    describe "#create_property" do
        it "can create a property" do
            task = new_ruby_task_context("task")
            property = task.create_property('prop', 'int')
            assert_kind_of Orocos::Property, property
            assert_same property, task.property('prop')
            assert task.has_property?('prop')
        end
        it "initializes the property with a sample" do
            Orocos.load_typekit 'echo'
            opaque_t       = Orocos.registry.get '/OpaquePoint'
            intermediate_t = Orocos.registry.get '/echo/Point'
            initial_sample = intermediate_t.new
            initial_sample.x = 1
            initial_sample.y = 0
            flexmock(intermediate_t).should_receive(:new).and_return(initial_sample)
            task = new_ruby_task_context('task')
            task.create_property 'p', '/OpaquePoint'
            assert_equal initial_sample, task.p
        end
    end

    it "can read and write properties" do
        task = new_ruby_task_context("task")
        property = task.create_property('prop', 'int')
        property.write(10)
        assert_equal 10, property.read
        property.write(20)
        assert_equal 20, property.read
    end

    it "allows to get access to the model name if one is given" do
        project = OroGen::Spec::Project.new(Orocos.default_loader)
        model = OroGen::Spec::TaskContext.new(project, 'myModel')
        task = new_ruby_task_context('task', :model => model)
        assert_equal "myModel", task.getModelName
    end

    it "makes #model returns the oroGen model if given" do
        project = OroGen::Spec::Project.new(Orocos.default_loader)
        model = Orocos::Spec::TaskContext.new(project)
        task = new_ruby_task_context('task', :model => model)
        assert_same model, task.model
    end

    it "allows to handle the normal state changes" do
        task = new_ruby_task_context('task')
        assert_equal :PRE_OPERATIONAL, task.rtt_state
        task.configure
        assert_equal :STOPPED, task.rtt_state
        task.start
        assert_equal :RUNNING, task.rtt_state
        task.stop
        assert_equal :STOPPED, task.rtt_state
    end

end

