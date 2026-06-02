#include <ctype.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define SCRIPT "/Library/Application Support/ControllerKeys/RemoteMicBridge/Scripts/apple-tv-remote-packetlogger-live.py"
#define HID_PROBE "/Library/Application Support/ControllerKeys/RemoteMicBridge/Scripts/apple-tv-remote-mic-probe.swift"
#define PACKETLOGGER "/Applications/PacketLogger.app/Contents/Resources/packetlogger"

static int is_number(const char *value) {
    if (value == NULL || *value == '\0') return 0;
    int dot_count = 0;
    for (const char *cursor = value; *cursor != '\0'; ++cursor) {
        if (*cursor == '.') {
            if (++dot_count > 1) return 0;
        } else if (!isdigit((unsigned char)*cursor)) {
            return 0;
        }
    }
    return 1;
}

static int has_dotdot(const char *path) {
    return strstr(path, "/../") != NULL || strstr(path, "/..") == path + strlen(path) - 3;
}

static int starts_with(const char *value, const char *prefix) {
    return strncmp(value, prefix, strlen(prefix)) == 0;
}

static int allowed_output_path(const char *path, const char *home) {
    char prefix[4096];
    snprintf(prefix, sizeof(prefix), "%s/Library/Application Support/ControllerKeys/RemoteMic/", home);
    return path != NULL && starts_with(path, prefix) && !has_dotdot(path);
}

int main(int argc, char **argv) {
    const char *seconds = "20";
    const char *release_grace = "0.20";
    const char *output = NULL;
    const char *transcript = NULL;
    int transcribe = 0;
    int stream_coreaudio = 0;

    struct passwd *pw = getpwuid(getuid());
    if (pw == NULL || pw->pw_dir == NULL) {
        fprintf(stderr, "controllerkeys helper: cannot resolve invoking user\n");
        return 70;
    }

    for (int index = 1; index < argc; ++index) {
        if (strcmp(argv[index], "--seconds") == 0 && index + 1 < argc) {
            seconds = argv[++index];
        } else if (strcmp(argv[index], "--release-grace") == 0 && index + 1 < argc) {
            release_grace = argv[++index];
        } else if ((strcmp(argv[index], "-o") == 0 || strcmp(argv[index], "--output") == 0) && index + 1 < argc) {
            output = argv[++index];
        } else if (strcmp(argv[index], "--transcript") == 0 && index + 1 < argc) {
            transcript = argv[++index];
        } else if (strcmp(argv[index], "--transcribe") == 0) {
            transcribe = 1;
        } else if (strcmp(argv[index], "--stream-coreaudio") == 0) {
            stream_coreaudio = 1;
        } else {
            fprintf(stderr, "controllerkeys helper: unsupported argument %s\n", argv[index]);
            return 64;
        }
    }

    if (!is_number(seconds) || !is_number(release_grace)) {
        fprintf(stderr, "controllerkeys helper: invalid numeric option\n");
        return 64;
    }
    if (!stream_coreaudio && (!allowed_output_path(output, pw->pw_dir) || !allowed_output_path(transcript, pw->pw_dir))) {
        fprintf(stderr, "controllerkeys helper: output paths must stay under ControllerKeys RemoteMic support directory\n");
        return 64;
    }

    char *exec_argv[28];
    int count = 0;
    exec_argv[count++] = "/usr/bin/python3";
    exec_argv[count++] = SCRIPT;
    exec_argv[count++] = "--capture";
    exec_argv[count++] = "--enable-hid";
    if (!stream_coreaudio) {
        exec_argv[count++] = "--stop-on-release";
    }
    exec_argv[count++] = "--no-sudo";
    exec_argv[count++] = "--feed-coreaudio";
    if (stream_coreaudio) {
        exec_argv[count++] = "--coreaudio-only";
    }
    exec_argv[count++] = "--hid-probe";
    exec_argv[count++] = HID_PROBE;
    exec_argv[count++] = "--packetlogger";
    exec_argv[count++] = PACKETLOGGER;
    exec_argv[count++] = "--seconds";
    exec_argv[count++] = (char *)seconds;
    exec_argv[count++] = "--release-grace";
    exec_argv[count++] = (char *)release_grace;
    if (!stream_coreaudio) {
        exec_argv[count++] = "-o";
        exec_argv[count++] = (char *)output;
        exec_argv[count++] = "--transcript";
        exec_argv[count++] = (char *)transcript;
    }
    if (transcribe && !stream_coreaudio) {
        exec_argv[count++] = "--transcribe";
    }
    exec_argv[count] = NULL;

    char home_env[4096];
    char user_env[1024];
    char logname_env[1024];
    snprintf(home_env, sizeof(home_env), "HOME=%s", pw->pw_dir);
    snprintf(user_env, sizeof(user_env), "USER=%s", pw->pw_name);
    snprintf(logname_env, sizeof(logname_env), "LOGNAME=%s", pw->pw_name);
    char *exec_env[] = { home_env, user_env, logname_env, "PATH=/usr/bin:/bin:/usr/sbin:/sbin", NULL };

    execve(exec_argv[0], exec_argv, exec_env);
    perror("controllerkeys helper: execve");
    return 127;
}
