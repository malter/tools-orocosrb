#ifndef OROCOS_RB_EXT_CORBA_HH
#define OROCOS_RB_EXT_CORBA_HH

#include <omniORB4/CORBA.h>

#include <exception>
#include "TaskContextC.h"
#include "DataFlowC.h"
#include <iostream>
#include <string>
#include <stack>
#include <list>
#include <ruby.h>
#include <typelib_ruby.hh>

using namespace std;

extern VALUE mCORBA;
extern VALUE corba_access;
extern VALUE eCORBA;
extern VALUE eComError;
namespace RTT
{
    class TaskContext;
    namespace base {
        class PortInterface;
    }
    namespace corba
    {
        class TaskContextServer;
    }
}

/**
 * This class locates and connects to a Corba TaskContext.
 * It can do that through an IOR or through the NameService.
 */
class CorbaAccess
{
    static CORBA::ORB_var orb;
    static CosNaming::NamingContext_var rootContext;

    RTT::TaskContext* m_task;
    RTT::corba::TaskContextServer* m_task_server;
    RTT::corba::CTaskContext_ptr m_corba_task;
    RTT::corba::CDataFlowInterface_ptr m_corba_dataflow;

    CorbaAccess(std::string const& name, int argc, char* argv[] );
    ~CorbaAccess();
    static CorbaAccess* the_instance;

    // This counter is used to generate local port names that are unique
    int64_t port_id_counter;

public:
    static void init(std::string const& name, int argc, char* argv[]);
    static void deinit();
    static CorbaAccess* instance() { return the_instance; }

    /** Returns an automatic name for a port used to access the given remote
     * port
     */
    std::string getLocalPortName(VALUE remote_port);

    /** Returns the CORBA object that is a representation of our dataflow
     * interface
     */
    RTT::corba::CDataFlowInterface_ptr getDataFlowInterface() const;

    /** Adds a local port to the RTT interface for this Ruby process
     */
    void addPort(RTT::base::PortInterface* local_port);

    /** De-references a port that had been added by addPort
     */
    void removePort(RTT::base::PortInterface* local_port);

    /** Returns the list of tasks that are registered on the name service. Some
     * of them can be invalid references, as for instance a process crashed and
     * did not clean up its references
     */
    std::list<std::string> knownTasks();

    /** Returns a TaskContext reference to a remote control task. The reference
     * is assured to be valid.
     */
    RTT::corba::CTaskContext_ptr findByName(std::string const& name);

    /**
     * Returns a ControlTask reference to a remote control task, based on the IOR. 
     */
    RTT::corba::CTaskContext_ptr findByIOR(std::string const& ior);

    /** Unbinds a particular control task on the name server
     */
    void unbind(std::string const& name);
};
extern VALUE corba_to_ruby(std::string const& type_name, Typelib::Value dest, CORBA::Any& src);
extern CORBA::Any* ruby_to_corba(std::string const& type_name, Typelib::Value src);

#define CORBA_EXCEPTION_HANDLERS \
    catch(CORBA::COMM_FAILURE&) { rb_raise(eComError, "CORBA communication failure"); } \
    catch(CORBA::TRANSIENT&) { rb_raise(eComError, "CORBA transient exception"); } \
    catch(CORBA::Exception& e) { rb_raise(eCORBA, "unspecified error in the CORBA layer: %s", typeid(e).name()); }

#endif

