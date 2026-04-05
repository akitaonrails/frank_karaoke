#include "my_application.h"

#include <cstdlib>
#include <cstring>

namespace {

void set_default_env(const char* key, const char* value) {
  if (std::getenv(key) == nullptr) {
    setenv(key, value, 1);
  }
}

}  // namespace

int main(int argc, char** argv) {
  // Safe defaults for NVIDIA/Wayland — prevent blank screens and crashes.
  set_default_env("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
  set_default_env("__NV_DISABLE_EXPLICIT_SYNC", "1");

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
