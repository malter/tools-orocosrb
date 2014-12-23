require 'rake'
require './lib/orocos/version'

begin
    require 'hoe'
    Hoe::plugin :yard
    Hoe::RUBY_FLAGS.gsub!(/-w/, '')

    hoe_spec = Hoe.spec('orocos.rb') do |p|
        self.developer("Sylvain Joyeux", "sylvain.joyeux@dfki.de")

        self.summary = 'Controlling Orocos modules from Ruby'
        self.description = paragraphs_of('README.markdown', 3..5).join("\n\n")
        self.urls = ["https://gitorious.org/rock-toolchain/orocos-rb.git"]
        self.changes = ""
        licenses << "GPL v2 or later"

        self.extra_deps <<
            ['utilrb', ">= 1.1"] <<
            ['rake', ">= 0.8"] <<
            ["rake-compiler",   "~> 0.8.0"] <<
            ["hoe-yard",   ">= 0.1.2"]

    end

    hoe_spec.spec.extensions = FileList["ext/**/extconf.rb"]
    hoe_spec.test_globs = ['test/suite.rb']

    def build_orogen(name, options = Hash.new)
        require './lib/orocos/rake'

        parsed_options = Hash.new
        parsed_options[:keep_wc] =
            if ['1', 'true'].include?(options[:keep_wc]) then true
            else false
            end
        parsed_options[:transports] = (options[:transports] || "corba typelib mqueue").split(" ")
        if parsed_options[:transports].empty?
            parsed_options[:transports] = nil
        elsif parsed_options[:transports] == 'none'
            parsed_options[:transports] = []
        end

        parsed_options[:make_options] = Shellwords.split(options[:make_options] || "").
            map { |opt| opt.gsub(';', ',') }
        work_dir = File.expand_path(File.join('test', 'working_copy'))
        data_dir = File.expand_path(File.join('test', 'data'))
    
        Orocos::Rake.generate_and_build \
            File.join(data_dir, name, "#{name}.orogen"),
            work_dir, parsed_options
    end

    # Making sure that native extension will be build with gem
    require 'rubygems/package_task'
    Gem::PackageTask.new(hoe_spec.spec) do |pkg|
        pkg.need_zip = true
        pkg.need_tar = true
    end

    Rake.clear_tasks(/^default$/)
    task 'default' do
        Rake::Task['clean'].invoke
        Rake::Task['compile'].invoke
    end

    # Leave in top level namespace to allow rake-compiler to build native gem: 'rake native gem'
    require 'rake/extensiontask'
    desc "builds Orocos.rb C extension"
    rorocos_task = Rake::ExtensionTask.new('rorocos', hoe_spec.spec) do |ext|
        # Same info as in ext/rocoros/extconf.rb where cmake
        # is used to generate the Makefile
        ext.name = "rorocos"
        ext.ext_dir = "ext/rorocos"
        ext.lib_dir = "lib/orocos"
        ext.gem_spec = hoe_spec.spec
        ext.source_pattern = "*.{c,cpp,cc}"

        if not Dir.exists?(ext.tmp_dir)
            FileUtils.mkdir_p ext.tmp_dir
        end
    end

    namespace :setup do
        desc "builds the oroGen modules that are needed by the tests"
        task :orogen_all, [:keep_wc,:transports,:make_options] do |_, args|
            build_orogen 'process', args
            build_orogen 'simple_sink', args
            build_orogen 'simple_source', args
            build_orogen 'echo', args
            build_orogen 'operations', args
            build_orogen 'configurations', args
            build_orogen 'states', args
            build_orogen 'uncaught', args
            build_orogen 'system', args
        end

        desc "builds the test 'process' module"
        task :orogen_process, [:keep_wc,:transports,:update] do |_, args| build_orogen 'process', args end
        desc "builds the test 'simple_sink' module"
        task :orogen_sink, [:keep_wc,:transports,:update]    do |_, args| build_orogen 'simple_sink', args end
        desc "builds the test 'simple_source' module"
        task :orogen_source, [:keep_wc,:transports,:update]  do |_, args| build_orogen 'simple_source', args end
        desc "builds the test 'echo' module"
        task :orogen_echo, [:keep_wc,:transports,:update]    do |_, args| build_orogen 'echo', args end
        desc "builds the test 'states' module"
        task :orogen_states, [:keep_wc,:transports,:update]    do |_, args| build_orogen 'states', args end
        desc "builds the test 'uncaught' module"
        task :orogen_uncaught, [:keep_wc,:transports,:update]    do |_, args| build_orogen 'uncaught', args end
        desc "builds the test 'system' module"
        task :orogen_system, [:keep_wc,:transports,:update]    do |_, args| build_orogen 'system', args end
        desc "builds the test 'operations' module"
        task :orogen_operations, [:keep_wc,:transports,:update]    do |_, args| build_orogen 'operations', args end
        desc "builds the test 'configurations' module"
        task :orogen_configurations, [:keep_wc,:transports,:update]    do |_, args| build_orogen 'configurations', args end
        desc "builds the test 'ros_test' module"
        task :orogen_ros_test, [:keep_wc,:transports,:update]    do |_, args| build_orogen 'ros_test', args end

        task :test do |t, args|
            Rake::Task['setup:orogen_all'].invoke('1', '', '1')
        end

        UIFILES = %w{}
        desc 'generate all Qt UI files using rbuic4'
        task :uic do
            rbuic = 'rbuic4'
            if File.exists?('/usr/lib/kde4/bin/rbuic4')
                rbuic = '/usr/lib/kde4/bin/rbuic4'
            end

            UIFILES.each do |file|
                file = 'lib/orocos/roby/gui/' + file
                if !system(rbuic, '-o', file.gsub(/\.ui$/, '_ui.rb'), file)
                    STDERR.puts "Failed to generate #{file}"
                end
            end
        end
    end

    task :test
    task :doc => :yard
    task :docs => :yard
    task :redoc => :yard
    task :redocs => :yard

    # Add removal of by-products of test setup to the clean task
    CLEAN.include("test/working_copy")

rescue LoadError
    STDERR.puts "cannot load the Hoe gem. Distribution is disabled"
rescue Exception => e
    if e.message !~ /\.rubyforge/
        STDERR.puts "cannot load the Hoe gem, or Hoe fails. Distribution is disabled"
        STDERR.puts "error message is: #{e.message}"
    end
end

