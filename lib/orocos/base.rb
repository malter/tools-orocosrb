require 'orogen'
require 'typelib'
require 'utilrb/module/attr_predicate'
require 'orogen'

module Orocos
    class InternalError < Exception; end

    def self.register_pkgconfig_path(path)
    	base_path = caller(1).first.gsub(/:\d+:.*/, '')
	ENV['PKG_CONFIG_PATH'] = "#{File.expand_path(path, File.dirname(base_path))}:#{ENV['PKG_CONFIG_PATH']}"
    end

    # Exception raised when the user tries an operation that requires the
    # component to be generated by oroGen, while the component is not
    class NotOrogenComponent < Exception; end

    class << self
        # The Typelib::Registry instance that is the union of all the loaded
        # component's type registries
        attr_reader :registry

        # The master oroGen project through  which all the other oroGen projects
        # are imported
        attr_reader :master_project

        # The main configuration manager object
        attr_reader :conf

        # The set of orogen projects that are available, as a mapping from a
        # name into the project's orogen description file
        attr_reader :available_projects

        # The set of available deployments, as a mapping from the deployment
        # name into the Utilrb::PkgConfig object that represents it
        attr_reader :available_deployments

        # The set of available task libraries, as a mapping from the task
        # library name into the Utilrb::PkgConfig object that represent it
        attr_reader :available_task_libraries

        # The set of available task models, as a mapping from the model name
        # into the task library name that defines it
        attr_reader :available_task_models

        # The set of available typekits, as a mapping from the typekit name to a
        # PkgConfig object
        attr_reader :available_typekits

        # The set of available types, as a mapping from the type name to a
        # [typekit_name, exported] pair, where +typekit_name+ is the name of the
        # typekit that defines it, and +exported+ is a boolean which is true if
        # the type is registered on the RTT type system and false otherwise.
        attr_reader :available_types
    end
    @use_mq_warning = true

    def self.max_sizes_for(type)
        Orocos.master_project.max_sizes[type.name]
    end

    def self.max_sizes(*args)
        Orocos.master_project.max_sizes(*args)
    end

    # True if there is a typekit named +name+ on the file system
    def self.has_typekit?(name)
        pkg, _ = available_projects[name]
        pkg && pkg.type_registry
    end

    def self.orocos_target
        if ENV['OROCOS_TARGET']
            ENV['OROCOS_TARGET']
        else
            'gnulinux'
        end
    end

    # Helper method for initialize
    def self.add_project_from(pkg) # :nodoc:
        project = pkg.project_name
        if project.empty?
            Orocos.warn "#{pkg.name}.pc does not have a project_name field"
        end
        if description = available_projects[project]
            return description
        end

        if pkg.deffile.empty?
            Orocos.warn "#{pkg.name}.pc does not have a deffile field"
        else
            available_projects[pkg.project_name] = [pkg, pkg.deffile]
        end
    end

    class << self
        # The set of extension names seen so far
        #
        # Whenever a new extension is encountered, Orocos.task_model_from_name
        # tries to require 'extension_name/runtime', which might no exist. Once
        # it has done that, it registers the extension name in this set to avoid
        # trying loading it again
        attr_reader :known_orogen_extensions
    end
    @known_orogen_extensions = Set.new

    # Returns the task model object whose name is +name+, or raises
    # Orocos::NotFound if none exists
    def self.task_model_from_name(name)
        tasklib_name = available_task_models[name]
        if !tasklib_name
            raise Orocos::NotFound, "no task model #{name} is registered"
        end

        tasklib = Orocos.master_project.using_task_library(tasklib_name)
        result = tasklib.tasks[name]
        if !result
            raise InternalError, "while looking up model of #{name}: found project #{tasklib_name}, but this project does not actually have a task model called #{name}"
        end

        result.each_extension do |name, ext|
            if !known_orogen_extensions.include?(name)
                begin
                    require "#{name}/runtime"
                rescue LoadError
                end
                known_orogen_extensions << name
            end
        end
        result
    end

    # Loads a directory containing configuration files
    #
    # See the documentation of ConfigurationManager#load_dir for more
    # information
    def self.load_config_dir(dir)
        conf.load_dir(dir)
    end

    # Returns true if Orocos.load has been called
    def self.loaded?
        !!@master_project
    end

    def self.load
        @master_project = Orocos::Generation::Component.new
        if registry && export_types?
            registry.clear_exports(type_export_namespace)
        end
        @registry = master_project.registry
        @conf = ConfigurationManager.new
        @available_projects ||= Hash.new
        @loaded_typekit_registries.clear
        @loaded_typekit_plugins.clear

        load_standard_typekits

        # Finally, update the set of available projects
        Utilrb::PkgConfig.each_package(/^orogen-project-/) do |pkg_name|
            if !available_projects.has_key?(pkg_name)
                pkg = Utilrb::PkgConfig.new(pkg_name)
                add_project_from(pkg)
            end
        end

        # Load the name of all available task libraries
        if !available_task_libraries
            @available_task_libraries = Hash.new
            Utilrb::PkgConfig.each_package(/-tasks-#{Orocos.orocos_target}$/) do |pkg_name|
                pkg = Utilrb::PkgConfig.new(pkg_name)
                tasklib_name = pkg_name.gsub(/-tasks-#{Orocos.orocos_target}$/, '')
                available_task_libraries[tasklib_name] = pkg

                add_project_from(pkg)
            end
        end

        if !available_deployments
            @available_deployments = Hash.new
            Utilrb::PkgConfig.each_package(/^orogen-\w+$/) do |pkg_name|
                pkg = Utilrb::PkgConfig.new(pkg_name)
                deployment_name = pkg_name.gsub(/^orogen-/, '')
                available_deployments[deployment_name] = pkg

                add_project_from(pkg)
            end
        end

        # Create a class_name => tasklib mapping for all task models available
        # on this sytem
        if !available_task_models
            @available_task_models = Hash.new
            available_task_libraries.each do |tasklib_name, tasklib_pkg|
                tasklib_pkg.task_models.split(",").
                    each { |class_name| available_task_models[class_name] = tasklib_name }
            end
        end

        if !available_typekits
            @available_typekits = Hash.new
            Utilrb::PkgConfig.each_package(/-typekit-#{Orocos.orocos_target}$/) do |pkg_name|
                pkg = Utilrb::PkgConfig.new(pkg_name)
                typekit_name = pkg_name.gsub(/-typekit-#{Orocos.orocos_target}$/, '')
                available_typekits[typekit_name] = pkg
            end
        end

        if !available_types
            @available_types = Hash.new
            available_typekits.each do |typekit_name, typekit_pkg|
                typelist = typekit_pkg.type_registry.gsub(/tlb$/, 'typelist')
                typelist, typelist_exported =
                    Orocos::Generation::ImportedTypekit.parse_typelist(File.read(typelist))
                typelist.each do |typename|
                    @available_types[typename] = [typekit_name, false]
                end
                typelist_exported.each do |typename|
                    @available_types[typename] = [typekit_name, true]
                end
            end
        end
    end

    def self.load_dummy_models(file_or_dir)
        paths = []
        if File.file?(file_or_dir)
            paths << file_or_dir
        else
            Dir.glob(File.join(file_or_dir, "*.orogen")) do |orogen_file|
                paths << orogen_file
            end
        end

        old_value = Orocos.master_project.define_dummy_types?
        begin
            Orocos.master_project.define_dummy_types = true
            paths.each do |file|
                tasklib = Orocos.master_project.
                    using_task_library(file, :define_dummy_types => true)
                tasklib.self_tasks.each do |task|
                    Orocos.available_task_models[task.name] = file
                end
            end
        ensure
            Orocos.master_project.define_dummy_types = old_value
        end
    end

    class << self
        attr_predicate :disable_sigchld_handler, true
    end

    # Returns true if Orocos.initialize has been called and completed
    # successfully
    def self.initialized?
        CORBA.initialized?
    end

    # Initialize the Orocos communication layer and load all the oroGen models
    # that are available.
    #
    # This method will verify that the pkg-config environment is sane, as it is
    # demanded by the oroGen deployments. If it is not the case, it will raise
    # a RuntimeError exception whose message will describe the particular
    # problem. See the "Error messages" package in the user's guide for more
    # information on how to fix those.
    def self.initialize(name = nil)
        if !registry
            self.load
        end

        # oroGen components use pkg-config --list-all to find where all typekit
        # files are.  Unfortunately, Debian and debian-based system sometime
        # have pkg-config --list-all broken because of missing dependencies
        #
        # Detect it and present an error message to the user if it is the case
        if !system("pkg-config --list-all > /dev/null 2>&1")
            raise RuntimeError, "pkg-config --list-all returns an error. Run it in a console and install packages that are reported."
        end

        # Install the SIGCHLD handler if it has not been disabled
        if !disable_sigchld_handler?
            trap('SIGCHLD') do
                begin
                    while dead = ::Process.wait(-1, ::Process::WNOHANG)
                        if mod = Orocos::Process.from_pid(dead)
                            mod.dead!($?)
                        end
                    end
                rescue Errno::ECHILD
                end
            end
        end

        if !Orocos::CORBA.initialized?
            Orocos::CORBA.init(name)
        end
        @initialized = true
    end

    # call-seq:
    #   Orocos.each_task do |task| ...
    #   end
    #
    # Enumerates the tasks that are currently available on this sytem (i.e.
    # registered on the name server). They are provided as TaskContext
    # instances.
    def self.each_task
        task_names.each do |name|
            task = begin TaskContext.get(name)
                   rescue Orocos::NotFound
                       CORBA.unregister(name)
                   end
            yield(task) if task
        end
    end

    # Polls the state of this set of task, and announces when a state changed
    def self.watch(*tasks)
        tasks.each do |t|
            s = t.state
            puts "#{t.name}: in state #{s}"
        end

        while true
            tasks.each do |t|
                if t.state_changed?
                    s = t.state(false)
                    puts "#{t.name}: state changed to #{s}"
                end
            end
            yield if block_given?
            sleep 0.1
        end
    end
end

