$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

describe Orocos::CORBA do
    TEST_DIR = File.dirname(__FILE__)
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    include Orocos::Spec

    it "should be already initialized" do
        assert !Orocos::CORBA::init
    end

    it "should allow listing task names" do
        Orocos.task_names
    end

    it "should be able to list types that can be transported through CORBA" do
        types = Orocos::CORBA.transportable_type_names
        assert(types.include?("int"), "'int' is not part of #{types.join(", ")}")
    end

    it "should be able to load toolkit plugins" do
        assert(! Orocos::CORBA.loaded_toolkit?('process'))
        Orocos::CORBA.load_toolkit 'process'
        assert( Orocos::CORBA.loaded_toolkit?('process'))
        types = Orocos::CORBA.transportable_type_names
        assert(types.include?("/process/Simple"))
    end

    it "should load type registries associated with the plugins" do
        assert_raises(Typelib::NotFound) { Orocos.registry.get("/process/Simple") }
        Orocos::CORBA.load_toolkit 'process'
        assert(Orocos.registry.get("/process/Simple"))
    end
end

