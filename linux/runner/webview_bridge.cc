#include "webview_bridge.h"

#include <cstring>
#include <map>
#include <string>
#include <sys/stat.h>

#include <gdk/gdk.h>
#include <webkit2/webkit2.h>

static GtkOverlay* g_overlay = nullptr;
static WebKitWebView* g_webview = nullptr;
static GtkWidget* g_webview_widget = nullptr;
static GtkFixed* g_fixed = nullptr;       // Container for precise positioning
static FlMethodChannel* g_method_channel = nullptr;
static FlEventChannel* g_event_channel = nullptr;
static gboolean g_listening = FALSE;
static WebKitUserContentManager* g_content_manager = nullptr;
static WebKitWebContext* g_web_context = nullptr;

static std::map<std::string, gulong> g_handler_signals;

// Bottom inset in pixels (space reserved for Flutter's bottom nav bar).
static int g_bottom_inset = 0;

// Resize the webview within the fixed container to fill the available space
// minus the bottom inset.
static void apply_webview_layout() {
  if (g_webview_widget == nullptr || g_overlay == nullptr) return;
  GtkAllocation alloc;
  gtk_widget_get_allocation(GTK_WIDGET(g_overlay), &alloc);
  int h = alloc.height - g_bottom_inset;
  if (h < 100) h = 100;
  // Move to (0,0) and size to (width, height - inset).
  if (g_fixed != nullptr) {
    gtk_fixed_move(g_fixed, g_webview_widget, 0, 0);
  }
  gtk_widget_set_size_request(g_webview_widget, alloc.width, h);
}

static void on_overlay_size_allocate(GtkWidget* widget, GdkRectangle* allocation,
                                     gpointer user_data) {
  apply_webview_layout();
}

// JS shim to emulate window.flutter_inappwebview.callHandler()
static const char* JS_BRIDGE_SHIM = R"JS(
(function() {
  if (window.flutter_inappwebview) return;
  window.flutter_inappwebview = {
    callHandler: function(name) {
      var args = Array.prototype.slice.call(arguments, 1);
      window.webkit.messageHandlers[name].postMessage(JSON.stringify(args));
    }
  };
})();
)JS";

// Forward declarations
static void on_method_call(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data);

// Send event to Dart
static void send_event(const char* type, FlValue* data) {
  if (!g_listening || g_event_channel == nullptr) return;
  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "type", fl_value_new_string(type));
  if (data != nullptr) {
    fl_value_set_string_take(event, "data", fl_value_ref(data));
  }
  g_autoptr(GError) error = nullptr;
  fl_event_channel_send(g_event_channel, event, nullptr, &error);
  if (error != nullptr) {
    g_warning("Failed to send event: %s", error->message);
  }
}

static void on_load_changed(WebKitWebView* web_view, WebKitLoadEvent event,
                            gpointer user_data) {
  if (event == WEBKIT_LOAD_FINISHED) {
    const gchar* uri = webkit_web_view_get_uri(web_view);
    g_autoptr(FlValue) data = fl_value_new_map();
    fl_value_set_string_take(data, "url",
                             fl_value_new_string(uri ? uri : ""));
    send_event("onLoadStop", data);
  }
}

static void on_uri_changed(GObject* object, GParamSpec* pspec,
                           gpointer user_data) {
  WebKitWebView* web_view = WEBKIT_WEB_VIEW(object);
  const gchar* uri = webkit_web_view_get_uri(web_view);
  g_autoptr(FlValue) data = fl_value_new_map();
  fl_value_set_string_take(data, "url",
                           fl_value_new_string(uri ? uri : ""));
  send_event("onUpdateVisitedHistory", data);
}

static GtkWidget* on_create(WebKitWebView* web_view,
                             WebKitNavigationAction* navigation_action,
                             gpointer user_data) {
  WebKitURIRequest* request =
      webkit_navigation_action_get_request(navigation_action);
  const gchar* uri = webkit_uri_request_get_uri(request);
  if (uri != nullptr && g_webview != nullptr) {
    gchar* uri_copy = g_strdup(uri);
    g_idle_add(
        [](gpointer data) -> gboolean {
          gchar* u = static_cast<gchar*>(data);
          if (g_webview != nullptr) {
            webkit_web_view_load_uri(g_webview, u);
          }
          g_free(u);
          return G_SOURCE_REMOVE;
        },
        uri_copy);
  }
  return nullptr;
}

static void on_script_message(WebKitUserContentManager* manager,
                              WebKitJavascriptResult* js_result,
                              gpointer user_data) {
  const char* handler_name = static_cast<const char*>(user_data);
  JSCValue* value = webkit_javascript_result_get_js_value(js_result);
  gchar* json = jsc_value_to_string(value);

  g_autoptr(FlValue) data = fl_value_new_map();
  fl_value_set_string_take(data, "name",
                           fl_value_new_string(handler_name));
  fl_value_set_string_take(data, "args",
                           fl_value_new_string(json ? json : "[]"));
  send_event("onJavaScriptHandler", data);

  g_free(json);
}

// ---- Method handlers ----

static void handle_create(FlMethodCall* method_call) {
  FlValue* args = fl_method_call_get_args(method_call);
  const char* url = fl_value_get_string(fl_value_lookup_string(args, "url"));
  FlValue* ua_val = fl_value_lookup_string(args, "userAgent");
  const char* user_agent =
      (ua_val != nullptr && fl_value_get_type(ua_val) == FL_VALUE_TYPE_STRING)
          ? fl_value_get_string(ua_val)
          : nullptr;

  if (g_webview == nullptr) {
    g_content_manager = webkit_user_content_manager_new();

    WebKitUserScript* script = webkit_user_script_new(
        JS_BRIDGE_SHIM, WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
        WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, nullptr, nullptr);
    webkit_user_content_manager_add_script(g_content_manager, script);
    webkit_user_script_unref(script);

    gchar* data_dir =
        g_build_filename(g_get_user_data_dir(), "frank_karaoke", "webview", nullptr);
    gchar* cache_dir =
        g_build_filename(g_get_user_cache_dir(), "frank_karaoke", "webview", nullptr);
    g_mkdir_with_parents(data_dir, 0700);
    g_mkdir_with_parents(cache_dir, 0700);

    WebKitWebsiteDataManager* data_manager = webkit_website_data_manager_new(
        "base-data-directory", data_dir,
        "base-cache-directory", cache_dir,
        nullptr);

    g_web_context =
        webkit_web_context_new_with_website_data_manager(data_manager);

    WebKitCookieManager* cookie_manager =
        webkit_web_context_get_cookie_manager(g_web_context);
    gchar* cookie_file = g_build_filename(data_dir, "cookies.sqlite", nullptr);
    webkit_cookie_manager_set_persistent_storage(
        cookie_manager, cookie_file,
        WEBKIT_COOKIE_PERSISTENT_STORAGE_SQLITE);
    webkit_cookie_manager_set_accept_policy(
        cookie_manager, WEBKIT_COOKIE_POLICY_ACCEPT_ALWAYS);
    g_free(cookie_file);
    g_free(data_dir);
    g_free(cache_dir);

    g_webview = WEBKIT_WEB_VIEW(g_object_new(
        WEBKIT_TYPE_WEB_VIEW,
        "web-context", g_web_context,
        "user-content-manager", g_content_manager,
        nullptr));
    g_webview_widget = GTK_WIDGET(g_webview);

    g_object_unref(data_manager);

    g_signal_connect(g_webview, "load-changed",
                     G_CALLBACK(on_load_changed), nullptr);
    g_signal_connect(g_webview, "notify::uri",
                     G_CALLBACK(on_uri_changed), nullptr);
    g_signal_connect(g_webview, "create",
                     G_CALLBACK(on_create), nullptr);

    // Use a GtkFixed container for precise pixel positioning.
    // This prevents GtkOverlay from expanding the webview to fill the window.
    g_fixed = GTK_FIXED(gtk_fixed_new());
    gtk_widget_set_halign(GTK_WIDGET(g_fixed), GTK_ALIGN_FILL);
    gtk_widget_set_valign(GTK_WIDGET(g_fixed), GTK_ALIGN_FILL);
    gtk_fixed_put(g_fixed, g_webview_widget, 0, 0);
    gtk_widget_show(GTK_WIDGET(g_fixed));

    gtk_overlay_add_overlay(g_overlay, GTK_WIDGET(g_fixed));

    // Pass input through the GtkFixed container — only the webview
    // (which has an explicit size) will receive events in its area.
    gtk_overlay_set_overlay_pass_through(g_overlay, GTK_WIDGET(g_fixed), TRUE);

    g_signal_connect(GTK_WIDGET(g_overlay), "size-allocate",
                     G_CALLBACK(on_overlay_size_allocate), nullptr);
  }

  if (user_agent != nullptr) {
    WebKitSettings* settings = webkit_web_view_get_settings(g_webview);
    webkit_settings_set_user_agent(settings, user_agent);
  }

  WebKitSettings* settings = webkit_web_view_get_settings(g_webview);
  webkit_settings_set_enable_javascript(settings, TRUE);
  webkit_settings_set_enable_html5_database(settings, TRUE);
  webkit_settings_set_enable_html5_local_storage(settings, TRUE);
  webkit_settings_set_javascript_can_open_windows_automatically(settings, TRUE);
  webkit_settings_set_hardware_acceleration_policy(
      settings, WEBKIT_HARDWARE_ACCELERATION_POLICY_ON_DEMAND);

  webkit_web_view_load_uri(g_webview, url);
  gtk_widget_show(g_webview_widget);
  apply_webview_layout();

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_set_frame(FlMethodCall* method_call) {
  FlValue* args = fl_method_call_get_args(method_call);
  g_bottom_inset = static_cast<int>(
      fl_value_get_float(fl_value_lookup_string(args, "bottom")));
  apply_webview_layout();

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_evaluate_javascript(FlMethodCall* method_call) {
  if (g_webview == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("NO_WEBVIEW", "WebView not created", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  FlValue* args = fl_method_call_get_args(method_call);
  const char* source =
      fl_value_get_string(fl_value_lookup_string(args, "source"));
  gsize length = strlen(source);

  g_object_ref(method_call);

  auto callback = [](GObject* object, GAsyncResult* result, gpointer user_data) {
    FlMethodCall* mc = FL_METHOD_CALL(user_data);
    GError* error = nullptr;
    JSCValue* value = webkit_web_view_evaluate_javascript_finish(
        WEBKIT_WEB_VIEW(object), result, &error);

    if (error != nullptr) {
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("JS_ERROR", error->message, nullptr));
      fl_method_call_respond(mc, response, nullptr);
      g_error_free(error);
    } else {
      gchar* str = nullptr;
      g_autoptr(FlValue) result_val = nullptr;

      if (jsc_value_is_string(value)) {
        str = jsc_value_to_string(value);
        result_val = fl_value_new_string(str);
      } else if (jsc_value_is_boolean(value)) {
        result_val = fl_value_new_bool(jsc_value_to_boolean(value));
      } else if (jsc_value_is_number(value)) {
        result_val = fl_value_new_float(jsc_value_to_double(value));
      } else if (jsc_value_is_null(value) || jsc_value_is_undefined(value)) {
        result_val = fl_value_new_null();
      } else {
        str = jsc_value_to_string(value);
        result_val = fl_value_new_string(str);
      }

      g_autoptr(FlMethodResponse) response =
          FL_METHOD_RESPONSE(fl_method_success_response_new(result_val));
      fl_method_call_respond(mc, response, nullptr);

      g_free(str);
      g_object_unref(value);
    }

    g_object_unref(mc);
  };

  webkit_web_view_evaluate_javascript(g_webview, source, length, nullptr,
                                      nullptr, nullptr, callback,
                                      method_call);
}

static void handle_add_js_handler(FlMethodCall* method_call) {
  if (g_content_manager == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("NO_WEBVIEW", "WebView not created", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  FlValue* args = fl_method_call_get_args(method_call);
  const char* name =
      fl_value_get_string(fl_value_lookup_string(args, "name"));

  if (g_handler_signals.find(name) != g_handler_signals.end()) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(TRUE)));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  char* name_copy = g_strdup(name);

  gboolean registered =
      webkit_user_content_manager_register_script_message_handler(
          g_content_manager, name);

  if (registered) {
    gchar* signal_name =
        g_strdup_printf("script-message-received::%s", name);
    gulong sig_id = g_signal_connect(g_content_manager, signal_name,
                                     G_CALLBACK(on_script_message), name_copy);
    g_handler_signals[name] = sig_id;
    g_free(signal_name);
  }

  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(registered)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_set_visible(FlMethodCall* method_call) {
  FlValue* args = fl_method_call_get_args(method_call);
  gboolean visible = fl_value_get_bool(fl_value_lookup_string(args, "visible"));

  // Show/hide the fixed container (which contains the webview).
  GtkWidget* target = g_fixed != nullptr ? GTK_WIDGET(g_fixed) : g_webview_widget;
  if (target != nullptr) {
    if (visible) {
      gtk_widget_show(target);
      if (g_webview_widget != nullptr) gtk_widget_show(g_webview_widget);
      apply_webview_layout();
    } else {
      gtk_widget_hide(target);
    }
  }

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_destroy(FlMethodCall* method_call) {
  GtkWidget* container = g_fixed != nullptr ? GTK_WIDGET(g_fixed) : g_webview_widget;
  if (container != nullptr && g_overlay != nullptr) {
    gtk_widget_hide(container);
    gtk_container_remove(GTK_CONTAINER(g_overlay), container);
  }
  g_webview = nullptr;
  g_webview_widget = nullptr;
  g_fixed = nullptr;
  g_content_manager = nullptr;
  if (g_web_context != nullptr) {
    g_object_unref(g_web_context);
    g_web_context = nullptr;
  }
  g_handler_signals.clear();

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
  fl_method_call_respond(method_call, response, nullptr);
}

// Method channel dispatcher
static void on_method_call(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "create") == 0) {
    handle_create(method_call);
  } else if (strcmp(method, "setFrame") == 0) {
    handle_set_frame(method_call);
  } else if (strcmp(method, "evaluateJavascript") == 0) {
    handle_evaluate_javascript(method_call);
  } else if (strcmp(method, "addJavaScriptHandler") == 0) {
    handle_add_js_handler(method_call);
  } else if (strcmp(method, "setVisible") == 0) {
    handle_set_visible(method_call);
  } else if (strcmp(method, "destroy") == 0) {
    handle_destroy(method_call);
  } else {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
  }
}

// Event channel handlers
static FlMethodErrorResponse* on_event_listen(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  g_listening = TRUE;
  return nullptr;
}

static FlMethodErrorResponse* on_event_cancel(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  g_listening = FALSE;
  return nullptr;
}

// Public API
void webview_bridge_init(FlBinaryMessenger* messenger, GtkOverlay* overlay) {
  g_overlay = overlay;

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_method_channel = fl_method_channel_new(messenger, "frank_karaoke/webview",
                                           FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_method_channel, on_method_call,
                                            nullptr, nullptr);

  g_autoptr(FlStandardMethodCodec) event_codec =
      fl_standard_method_codec_new();
  g_event_channel = fl_event_channel_new(
      messenger, "frank_karaoke/webview_events", FL_METHOD_CODEC(event_codec));
  fl_event_channel_set_stream_handlers(g_event_channel, on_event_listen,
                                       on_event_cancel, nullptr, nullptr);
}

void webview_bridge_dispose(void) {
  GtkWidget* container = g_fixed != nullptr ? GTK_WIDGET(g_fixed) : g_webview_widget;
  if (container != nullptr && g_overlay != nullptr) {
    gtk_container_remove(GTK_CONTAINER(g_overlay), container);
  }
  g_webview = nullptr;
  g_webview_widget = nullptr;
  g_fixed = nullptr;
  g_content_manager = nullptr;
  g_handler_signals.clear();
  g_listening = FALSE;

  if (g_web_context != nullptr) {
    g_object_unref(g_web_context);
    g_web_context = nullptr;
  }
}
