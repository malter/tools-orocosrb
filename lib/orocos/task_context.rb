require 'utilrb/object/attribute'

module Orocos
    class Attribute
	class << self
	    # The only way to create an Attribute object is
	    # TaskContext#attribute
	    private :new
	end

        attr_reader :task
        attr_reader :name
        attr_reader :type

        def initialize
            if @type_name == "string"
                @type_name = "/std/string"
            end
            if !(@type = Orocos.registry.get(@type_name))
                raise "can not find #{@type_name} in the registry"
            end
        end

        def read
            if @type_name == "/std/string"
                do_read_string
            else
                value = type.new
                do_read(@type_name, value)
                value.to_ruby
            end
        end

        def write(value)
            if @type_name == "/std/string" && value.respond_to?(:to_str)
                do_write_string(value.to_str)
            else
                value = Typelib.from_ruby(value, type)
                do_write(@type_name, value)
            end
        end

        def pretty_print(pp) # :nodoc:
            pp.text "attribute #{name} (#{type.name})"
        end
    end

    # A proxy for a remote task context. The communication between Ruby and the
    # RTT component is done through the CORBA transport.
    #
    # See README.txt for information on how you can manipulate a task context
    # through this class.
    #
    # The available information about this task context can be displayed using
    # Ruby's pretty print library:
    #
    #   require 'pp'
    #   pp task_object
    #
    class TaskContext
        # The name of this task context
        attr_reader :name
	# The process that supports it
	attr_reader :process

        RUNNING_STATES = []
        RUNNING_STATES[STATE_PRE_OPERATIONAL] = false
        RUNNING_STATES[STATE_ACTIVE]          = false
        RUNNING_STATES[STATE_STOPPED]         = false
        RUNNING_STATES[STATE_RUNNING]         = true
        RUNNING_STATES[STATE_RUNTIME_ERROR]   = true
        RUNNING_STATES[STATE_RUNTIME_WARNING] = true
        RUNNING_STATES[STATE_FATAL_ERROR]     = false

        def initialize
            @ports ||= Hash.new
        end

	class << self
	    # The only way to create TaskContext is TaskContext.get
	    private :new
	end

        # Returns a task which provides the +type+ interface.
        #
        # Use TaskContext.get(:provides => name) instead.
        def self.get_provides(type) # :nodoc:
            results = Orocos.enum_for(:each_task).find_all do |task|
                task.implements?(type)
            end

            if results.empty?
                raise Orocos::NotFound, "no task implements #{type}"
            elsif results.size > 1
                candidates = results.map { |t| t.name }.join(", ")
                raise Orocos::NotFound, "more than one task implements #{type}: #{candidates}"
            end
            get(results.first.name)
        end

	# call-seq:
        #   TaskContext.get(name) => task
        #   TaskContext.get(:provides => interface_name) => task
        #
        # In the first form, returns the TaskContext instance representing the
        # remote task context with the given name.
        #
        # In the second form, searches for a task context that implements the given
        # interface. This is doable only if orogen has been used to generate the
        # components.
        #
        # Raises Orocos::NotFound if the task name does not exist, or if no task
        # implements the given interface.
	def self.get(options, process = nil)
            if options.kind_of?(Hash)
                # Right now, the only allowed option is :provides
                options = Kernel.validate_options options, :provides => nil
                return get_provides(options[:provides].to_str)
            else
                name = options.to_str
            end

            # Try to find ourselves a process object if none is given
            if !process
                process = Orocos.enum_for(:each_process).
                    find do |p|
                        p.task_names.any? { |n| n == name }
                    end
            end

            result = CORBA.refine_exceptions("naming service") do
                do_get(name)
            end
            result.instance_variable_set(:@process, process)
            result
	end

        # Returns true if the task is in a state where code is executed. This
        # includes of course the running state, but also runtime error states.
        def running?; RUNNING_STATES[state] end
        # Returns true if the task has been configured.
        def ready?;   state != STATE_PRE_OPERATIONAL end
        # Returns true if the task is in an error state (runtime or fatal)
        def error?
            s = state
            s == STATE_RUNTIME_ERROR || s == STATE_FATAL_ERROR
        end

        # Automated wrapper to handle CORBA exceptions coming from the C
        # extension
        def self.corba_wrap(m, *args) # :nodoc:
            class_eval <<-EOD
            def #{m}(#{args.join(". ")})
                CORBA.refine_exceptions(self) { do_#{m}(#{args.join(", ")}) }
            end
            EOD
        end

        # :method: state
        #
        # call-seq:
        #  task.state => value
        #
        # Returns the state of the task, as an integer value. The possible values are
        # represented by the various +STATE_+ constants:
        # 
        #   STATE_PRE_OPERATIONAL
        #   STATE_STOPPED
        #   STATE_ACTIVE
        #   STATE_RUNNING
        #   STATE_RUNTIME_WARNING
        #   STATE_RUNTIME_ERROR
        #   STATE_FATAL_ERROR
        #
        # See Orocos own documentation for their meaning
        corba_wrap :state

        ##
        # :method: configure
        #
        # Configures the component, i.e. do the transition from STATE_PRE_OPERATIONAL into
        # STATE_STOPPED.
        #
        # Raises StateTransitionFailed if the component was not in
        # STATE_PRE_OPERATIONAL state before the call, or if the component
        # refused to do the transition (startHook() returned false)
        corba_wrap :configure

        ##
        # :method: start
        #
        # Starts the component, i.e. do the transition from STATE_STOPPED into
        # STATE_RUNNING.
        #
        # Raises StateTransitionFailed if the component was not in STATE_STOPPED
        # state before the call, or if the component refused to do the
        # transition (startHook() returned false)
        corba_wrap :start

        ##
        # :method: stop
        #
        # Stops the component, i.e. do the transition from STATE_RUNNING into
        # STATE_STOPPED.
        #
        # Raises StateTransitionFailed if the component was not in STATE_RUNNING
        # state before the call. The component cannot refuse to perform the
        # transition (but can take an arbitrarily long time to do it).
        corba_wrap :stop

        ##
        # :method: cleanup
        #
        # Cleans the component, i.e. do the transition from STATE_STOPPED into
        # STATE_PRE_OPERATIONAL.
        #
        # Raises StateTransitionFailed if the component was not in STATE_STOPPED
        # state before the call. The component cannot refuse to perform the
        # transition (but can take an arbitrarily long time to do it).
        corba_wrap :cleanup

        # Returns true if this task context has a port with the given name
        def has_port?(name)
            name = name.to_s
            CORBA.refine_exceptions(self) do
                do_has_port?(name)
            end
        end

        # Returns an Attribute object representing the given attribute or
        # property.
        #
        # Raises NotFound if no such attribute or property exists.
        #
        # Ports can also be accessed by calling directly the relevant
        # method on the task context:
        #
        #   task.attribute("myProperty")
        #
        # is equivalent to
        #
        #   task.myProperty
        #
        def attribute(name)
            name = name.to_s
            CORBA.refine_exceptions(self) do
                do_attribute(name)
            end
        end

        # Returns an object that represents the given port on the remote task
        # context. The returned object is either an InputPort or an OutputPort
        #
        # Raises NotFound if no such port exists.
        #
        # Ports can also be accessed by calling directly the relevant
        # method on the task context:
        #
        #   task.port("myPort")
        #
        # is equivalent to
        #
        #   task.myPort
        #
        def port(name)
            name = name.to_str
            CORBA.refine_exceptions(self) do
                if @ports[name]
                    if has_port?(name) # Check that this port is still valid
                        @ports[name]
                    else
                        @ports.delete(name)
                        raise NotFound, "no port named '#{name}' on task '#{self.name}'"
                    end
                else
                    @ports[name] = do_port(name)
                end
            end
        end

        # call-seq:
        #  task.each_port { |p| ... } => task
        # 
        # Enumerates the ports that are available on this task, as instances of
        # either Orocos::InputPort or Orocos::OutputPort
        def each_port(&block)
            CORBA.refine_exceptions(self) do
                do_each_port(&block)
            end
            self
        end

        # call-seq:
        #  task.each_attribute { |a| ... } => task
        # 
        # Enumerates the attributes and properties that are available on
        # this task, as instances of Orocos::Attribute
        def each_attribute(&block)
            CORBA.refine_exceptions(self) do
                do_each_attribute(&block)
            end
            self
        end

        # Returns a RTTMethod object that represents the given method on the
        # remote component.
        #
        # Raises NotFound if no such method exists.
        def rtt_method(name)
            CORBA.refine_exceptions(self) do
                do_rtt_method(name.to_s)
            end
        end
        # Returns a Command object that represents the given command on the
        # remote component.
        #
        # Raises NotFound if no such command exists.
        #
        # See also #rtt_command
	def command(name)
            CORBA.refine_exceptions(self) do
                do_command(name.to_s)
            end
	end
        # Like #command. Provided for consistency with #rtt_method
        def rtt_command(name); command(name) end

        def method_missing(m, *args) # :nodoc:
            m = m.to_s
            if m =~ /^(\w+)=/
                name = $1
                begin
                    return attribute(name).write(*args)
                rescue Orocos::NotFound
                end

            else
                if has_port?(m)
                    return port(m)
                end

                begin
                    return attribute(m).read(*args)
                rescue Orocos::NotFound
                end
            end
            super(m.to_sym, *args)
        end

        # Returns the Orogen specification object for this task instance.
        # This is available only if the deployment in which this task context
        # runs has been generated by orogen.
        #
        # See also #model
        def info
            process.orogen.task_activities.find { |act| act.name == name }
        end

        # Returns the Orogen specification object for this task's model
        # This is available only if the deployment in which this task context
        # runs has been generated by orogen.
        #
        # See also #info
        def model
            info.context
        end

        # True if this task's model is a subclass of the provided class name
        #
        # This is available only if the deployment in which this task context
        # runs has been generated by orogen.
        def implements?(class_name)
            model.implements?(class_name)
        end

        def pretty_print(pp) # :nodoc:
            states_description = TaskContext.constants.grep(/^STATE_/).
                inject([]) do |map, name|
                    map[TaskContext.const_get(name)] = name.gsub /^STATE_/, ''
                    map
                end

            pp.text "Component #{name}"
            pp.breakable
            pp.text "  state: #{states_description[state]}"
            pp.breakable

            attributes = enum_for(:each_attribute).to_a
            if attributes.empty?
                pp.text "No attributes"
                pp.breakable
            else
                pp.text "Attributes:"
                pp.breakable
                pp.nest(2) do
                    pp.text "  "
                    each_attribute do |attribute|
                        attribute.pretty_print(pp)
                        pp.breakable
                    end
                end
                pp.breakable
            end

            ports = enum_for(:each_port).to_a
            if ports.empty?
                pp.text "No ports"
                pp.breakable
            else
                pp.text "Ports:"
                pp.breakable
                pp.nest(2) do
                    pp.text "  "
                    each_port do |port|
                        port.pretty_print(pp)
                        pp.breakable
                    end
                end
                pp.breakable
            end
        end
    end
end

