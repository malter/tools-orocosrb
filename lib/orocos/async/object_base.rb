module Orocos::Async

    class EventListener
        attr_reader :event
        attr_reader :last_args

        def initialize(obj,event,use_last_value=true,&block)
            @block = block
            if !obj
                raise ArgumentError, "no object given"
            end
            @obj = obj
            @event = event
            @use_last_value = use_last_value
            @last_args
        end

        # returns true if the listener shall be called
        # with the last available value when started
        def use_last_value?
            !!@use_last_value
        end

        def pretty_print(pp) # :nodoc:
            pp.text "EventListener #{@event}"
        end

        # stop listing to the event
        def stop
            @last_args = nil
            @obj.remove_listener(self)
            self
        end

        # start listing  to the event
        def start(use_last_value = @use_last_value)
            @use_last_value = use_last_value
            @obj.add_listener(self)
            self
        end

        #return true if the listener is listing to 
        #the event
        def listening?
            @obj.listener?(self)
        end

        # calls the callback
        def call(*args)
            @last_args = args
            @block.call *args
        end
    end

    class DelegatorDummy
        attr_reader :event_loop
        attr_reader :name
        def initialize(parent,name,event_loop)
            @parent = parent
            @name = name
            @event_loop = event_loop
        end

        def method_missing(m,*args,&block)
            return super if m == :to_ary
            error = Orocos::NotFound.new "#{@name} is not reachable while accessing #{m}"
            error.set_backtrace(Kernel.caller)
            if !block
                raise error
            else
                @event_loop.defer :on_error => @parent.method(:emit_error),:callback => block,:known_errors => Orocos::Async::KNOWN_ERRORS do
                    raise error
                end
            end
        end
    end

    class ObjectBase
        module Periodic
            module ClassMethods
                attr_writer :default_period

                # Returns the default period for all instances of this class. It
                # inherits the value from parent classes
                def default_period
                    if @default_period then @default_period
                    elsif superclass.respond_to?(:default_period)
                        superclass.default_period
                    end
                end
            end

            def default_period
                self.class.default_period
            end

            def period
                @options[:period]
            end

            def period=(value)
                @options[:period]= if value
                                       value
                                   else
                                       default_period
                                   end
            end
        end

        class << self
            def event_names
                @event_names ||= if self != ObjectBase
                                     superclass.event_names.dup
                                 else
                                     []
                                 end
            end

            def define_event(name)
                define_events(name)
            end

            def define_events(*names)
                names.flatten!
                names.each do |n|
                    raise "Cannot add event #{n}. It is already added" if event_names.include? n
                    event_names << n
                    str =  %Q{ def on_#{n}(use_last_value = true,&block)
                                on_event #{n.inspect},use_last_value,&block
                            end
                            def once_on_#{n}(use_last_value = true,&block)
                                l = on_event #{n.inspect},use_last_value do |*args|
                                       block.call(*args)
                                       l.stop
                                    end
                            end
                            def emit_#{n}(*args)
                                event #{n.inspect},*args
                            end }
                    class_eval(str)
                end
            end

            def valid_event?(name)
                event_names.include?(name)
            end

            def validate_event(name)
                name = name.to_sym
                if !valid_event?(name)
                    raise "event #{name} is not emitted by #{self}. The following events are emitted #{event_names.join(", ")}"
                end
                name
            end
        end

        attr_reader :event_loop
        attr_reader :options
        attr_accessor :emitting
        attr_accessor :name
        define_events :error,:reachable,:unreachable

        # Queue of listener that are going to be added by callbacks registered
        # in the event loop. This is filled and processed by #add_listener and
        # #remove_listener
        #
        # Some entries might be nil if #remove_listener has been called before
        # the event loop processed the addition callbacks.
        #
        # @return [Array<EventLoop,nil>]
        attr_reader :pending_adds

        def initialize(name,event_loop)
            raise ArgumentError, "no name was given" if !name
            @listeners ||= Hash.new{ |hash,key| hash[key] = []}
            @proxy_listeners ||= Hash.new{|hash,key| hash[key] = Hash.new}
            @name ||= name
            @event_loop ||= event_loop
            @options ||= Hash.new
            @emitting = true
            @pending_adds = Array.new
            invalidate_delegator!
            on_error do |e|
                if e.kind_of?(Orocos::ComError)
                    unreachable!(:error => e)
                end
            end
        end

        def invalidate_delegator!
            @delegator_obj = DelegatorDummy.new self,@name,@event_loop
        end

        # sets @emitting to value for the time the given block is called
        def emitting(value,&block)
            old,@emitting = @emitting,value
            instance_eval(&block)
        ensure
            @emitting = old
        end

        def disable_emitting(&block)
            emitting(false,&block)
        end

        #returns true if the event is known
        def valid_event?(event)
            self.class.valid_event?(event)
        end

        def validate_event(event)
            self.class.validate_event(event)
        end

        def event_names
            self.class.event_names
        end

        def on_event(event,use_last_value=true,&block)
            event = validate_event event
            EventListener.new(self,event,use_last_value,&block).start
        end

        # returns the number of listener for the given event
        def number_of_listeners(event)
            event = validate_event event
            @listeners[event].size
        end

        #returns true if the listener is active
        def listener?(listener)
            @listeners[listener.event].include? listener
        end

        #returns the listeners for the given event
        def listeners(event)
            event = validate_event event
            @listeners[event]
        end

        # adds a listener to obj and proxies
        # event like it would be emitted from self
        #
        # if no listener is registererd to event it 
        # also removes the listener from obj
        def proxy_event(obj,*events)
            return if obj == self
            events = events.flatten
            events.each do |e|
                if existing = @proxy_listeners[obj].delete(e)
                    existing.stop
                end
                l = @proxy_listeners[obj][e] = EventListener.new(obj,e,true) do |*val|
                    process_event e,*val
                end
                l.start if number_of_listeners(e) > 0
            end
        end

        def remove_proxy_event(obj,*events)
            return if obj == self
            events = events.flatten
            if events.empty?
                remove_proxy_event(obj,@proxy_listeners[obj].keys)
                @proxy_listeners.delete(obj)
            else
                events.each do |e|
                    if listener = @proxy_listeners[obj].delete(e)
                        listener.stop
                    end
                end
            end
        end

        def add_listener(listener)
            event = validate_event listener.event
            return listener if pending_adds.include? listener
            pending_adds << listener
            event_loop.once do
                expected = pending_adds.shift
                # 'expected' is nil if the listener has been removed before this
                # block got processed
                if expected
                    if expected != listener
                        raise RuntimeError, "internal error in #{self}#add_listener: pending addition and expected addition mismatch"
                    end
                    really_add_listener(listener)
                end
            end
            listener
        end

        def really_add_listener(listener)
            if listener.use_last_value?
                if listener.event == :reachable
                    listener.call if valid_delegator?
                elsif listener.event == :unreachable
                    listener.call if !valid_delegator?
                end
            end
            @proxy_listeners.each do |obj,listeners|
                if l = listeners[listener.event]
                    if listener.use_last_value? && !listener.last_args
                        # replay last value if requested
                        obj.really_add_listener(listener)
                        obj.remove_listener(listener)
                    end
                    l.start(false) unless l.listening?
                end
            end
            @listeners[listener.event] << listener unless @listeners[listener.event].include?(listener)
            listener
        end

        def remove_listener(listener)
            if idx = pending_adds.index(listener)
                pending_adds[idx] = nil
            end
            @listeners[listener.event].delete listener

            # Check whether the only listeners left are proxy listeners. If they
            # are, remove them
            if number_of_listeners(listener.event) == 0
                @proxy_listeners.each do |obj, listeners|
                    if l = listeners[listener.event]
                        obj.remove_listener(l)
                    end
                end
            end
        end

        # calls all listener which are registered for the given event
        # the next step
        def event(event_name,*args)
            validate_event event_name
            return unless @emitting
            @event_loop.once do
                process_event event_name,*args
            end
            self
        end

        # waits until object gets reachable raises Orocos::NotFound if the
        # object was not reachable after the given time spawn
        def wait(timeout = 5.0)
            time = Time.now
            @event_loop.wait_for do
                if timeout && timeout <= Time.now-time
                    Utilrb::EventLoop.cleanup_backtrace do
                        raise Orocos::NotFound,"#{self.class}: #{respond_to?(:full_name) ? full_name : name} is not reachable after #{timeout} seconds"
                    end
                end
                reachable?
            end
            self
        end

        # TODO CODE BLOCK 
        def reachable?(&block)
            valid_delegator?
        end

        def reachable!(obj,options = Hash.new)
            @delegator_obj = obj
            event :reachable if valid_delegator?
        end

        def unreachable!(options = Hash.new)
            if valid_delegator?
                invalidate_delegator!
                event :unreachable
            end
        end

        def valid_delegator?
            !@delegator_obj.is_a? DelegatorDummy
        end

        def remove_all_listeners
            !@listeners.each do |event,listeners|
                while !listeners.empty?
                    remove_listener listeners.first
                end
            end
        end

        private
        # calls all listener which are registered for the given event
        def process_event(event_name,*args)
            event = validate_event event_name
            #@listeners have to be cloned because it might get modified 
            #by listener.call
            @listeners[event_name].clone.each do |listener|
                listener.call *args
            end
            self
        end
    end
end
