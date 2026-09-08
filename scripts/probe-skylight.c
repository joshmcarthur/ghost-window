#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

static void *lookup(void *handle, const char *name) {
    dlerror();
    void *symbol = dlsym(handle, name);
    if (symbol) {
        return symbol;
    }
    dlerror();
    return dlsym(RTLD_DEFAULT, name);
}

static void probe_list(void *handle, const char *const *names, bool *saw_set_alpha, bool *saw_connection) {
    for (size_t i = 0; names[i] != NULL; i++) {
        void *symbol = lookup(handle, names[i]);
        printf("  %-40s %s\n", names[i], symbol ? "loaded" : "missing");
        if (symbol == NULL) {
            continue;
        }
        if (strcmp(names[i], "SLSSetWindowAlpha") == 0 || strcmp(names[i], "CGSSetWindowAlpha") == 0) {
            *saw_set_alpha = true;
        }
        if (strcmp(names[i], "SLSMainConnectionID") == 0 || strcmp(names[i], "CGSMainConnectionID") == 0) {
            *saw_connection = true;
        }
    }
}

int main(void) {
    const char *sky_path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight";
    const char *hi_path = "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices";

    void *sky = dlopen(sky_path, RTLD_LAZY | RTLD_LOCAL);
    printf("dlopen %s\n  %s\n", sky_path, sky ? "ok (shared cache is fine)" : dlerror());

    void *hi = dlopen(hi_path, RTLD_LAZY | RTLD_LOCAL);
    printf("dlopen %s\n  %s\n", hi_path, hi ? "ok" : (dlerror() ? dlerror() : "missing on disk; trying RTLD_DEFAULT"));

    const char *sky_names[] = {
        "SLSMainConnectionID",
        "CGSMainConnectionID",
        "_CGSDefaultConnection",
        "SLSGetWindowAlpha",
        "CGSGetWindowAlpha",
        "SLSSetWindowAlpha",
        "CGSSetWindowAlpha",
        "_CGSWindowSetAlpha",
        "SLSGetWindowOpacity",
        "CGSGetWindowOpacity",
        "SLSSetWindowOpacity",
        "CGSSetWindowOpacity",
        "SLSTransactionCreate",
        "SLSTransactionCommit",
        "SLSTransactionSetWindowAlpha",
        "SLSTransactionSetWindowSystemAlpha",
        "SLSTransactionSetWindowOpaque",
        NULL
    };
    const char *ax_names[] = {
        "_AXUIElementGetWindow",
        NULL
    };

    bool saw_set_alpha = false;
    bool saw_connection = false;

    printf("\n== SkyLight dlsym ==\n");
    probe_list(sky ? sky : RTLD_DEFAULT, sky_names, &saw_set_alpha, &saw_connection);

    printf("\n== HIServices dlsym ==\n");
    bool unused_alpha = false;
    bool unused_connection = false;
    probe_list(hi ? hi : RTLD_DEFAULT, ax_names, &unused_alpha, &unused_connection);

    if (!saw_set_alpha || !saw_connection) {
        fprintf(stderr, "Required opacity symbols did not resolve via dlopen/dlsym.\n");
        return 1;
    }
    return 0;
}
