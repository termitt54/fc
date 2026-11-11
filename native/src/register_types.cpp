#include "fc_sim_core.h"
#include <godot_cpp/godot.hpp>
using namespace godot;
void initialize_fc(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE)
        ClassDB::register_class<FCSimCore>();
}
void uninitialize_fc(ModuleInitializationLevel) {}
extern "C" {
GDExtensionBool GDE_EXPORT fc_sim_core_init(GDExtensionInterfaceGetProcAddress get_proc_address,
                                            GDExtensionClassLibraryPtr library,
                                            GDExtensionInitialization* initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize_fc);
    init.register_terminator(uninitialize_fc);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
}
