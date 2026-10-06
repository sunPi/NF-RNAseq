/* Minimal Linux launcher for the adjacent NF-RNAseq Python UI. */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    char executable[PATH_MAX];
    char script[PATH_MAX];
    ssize_t length = readlink("/proc/self/exe", executable, sizeof executable - 1);
    if (length < 0 || (size_t)length >= sizeof executable - 1) {
        perror("NFRNASEQ: cannot locate launcher");
        return 1;
    }
    executable[length] = '\0';
    const char *directory = dirname(executable);
    int written = snprintf(script, sizeof script, "%s/nf_rnaseq_ui.py", directory);
    if (written < 0 || (size_t)written >= sizeof script) {
        fputs("NFRNASEQ: UI path is too long\n", stderr);
        return 1;
    }
    if (access(script, R_OK) != 0) {
        fprintf(stderr, "NFRNASEQ: UI script not found: %s\n", script);
        return 1;
    }
    char *const arguments[] = {"python3", script, NULL};
    execvp(arguments[0], arguments);
    fprintf(stderr, "NFRNASEQ: could not start python3: %s\n", strerror(errno));
    return 1;
}
