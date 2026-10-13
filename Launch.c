/*
 * PSIT OAS Launcher — Compiled Linux Native Executable
 * Starts the Linux stealth overlay runner (launch_linux.py) and opens test harness.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libgen.h>
#include <limits.h>

int main(int argc, char *argv[]) {
    char exe_path[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", exe_path, sizeof(exe_path) - 1);
    if (len == -1) {
        perror("readlink");
        return 1;
    }
    exe_path[len] = '\0';

    char *dir = dirname(exe_path);
    if (chdir(dir) != 0) {
        perror("chdir");
        return 1;
    }

    printf("=========================================\n");
    printf("🚀 PSIT OAS Launcher (Modded) — Linux\n");
    printf("=========================================\n");
    printf("[*] Working Directory: %s\n", dir);

    int launch_wine = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--oas") == 0 || strcmp(argv[i], "-o") == 0) {
            launch_wine = 1;
        }
    }

    if (launch_wine) {
        printf("[*] Launching PSITOAS.exe under Wine...\n");
        system("wine PSITOAS.exe >/dev/null 2>&1 &");
    }

    printf("[*] Launching Stealth Overlay (launch_linux.py)...\n");
    printf("[*] Three stealth dots will appear at the bottom-left corner.\n");
    printf("    - Blue Dot: Snip full screen to clipboard\n");
    printf("    - Green Dot: Open test page / AI chat\n");
    printf("    - Orange Dot: Targeted Question OCR + AI Auto-Solver\n");
    printf("    - Right-click dots to Quit.\n\n");

    char cmd[PATH_MAX + 64];
    snprintf(cmd, sizeof(cmd), "python3 \"%s/launch_linux.py\"", dir);
    return system(cmd);
}
