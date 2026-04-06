#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include "moonbit.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <limits.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif
#endif

#if defined(_MSC_VER)
#define MB_THREAD_LOCAL __declspec(thread)
#else
#define MB_THREAD_LOCAL _Thread_local
#endif

#define MB_STATUS_OK 0
#define MB_STATUS_ERROR -1
#define MB_PROCESS_ERROR -1

static MB_THREAD_LOCAL int32_t mb_last_error_code = 0;
static MB_THREAD_LOCAL char mb_last_error_message[1024] = "";

static void mb_set_error(int32_t code, const char *message) {
  mb_last_error_code = code;
  if (message == NULL) {
    mb_last_error_message[0] = '\0';
    return;
  }
  snprintf(mb_last_error_message, sizeof(mb_last_error_message), "%s", message);
}

static void mb_clear_error(void) {
  mb_set_error(0, "");
}

static int mb_set_errno_error(const char *fallback) {
  mb_set_error(errno, fallback);
  return MB_STATUS_ERROR;
}

static moonbit_bytes_t mb_make_bytes_from_buffer(const char *buf, size_t len) {
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);
  if (len > 0) {
    memcpy(out, buf, len);
  }
  return out;
}

#ifdef _WIN32
static moonbit_bytes_t mb_make_bytes_from_wide_buffer(const wchar_t *buf, size_t len) {
  return mb_make_bytes_from_buffer((const char *)buf, len * sizeof(wchar_t));
}
#endif

static char *mb_allocate_c_string(size_t len, const char *fallback) {
  char *buffer = (char *)malloc(len + 1);
  if (buffer == NULL) {
    mb_set_error(ENOMEM, fallback);
    return NULL;
  }
  buffer[len] = '\0';
  return buffer;
}

static char *mb_bytes_to_c_string(moonbit_bytes_t bytes) {
  size_t len = (size_t)Moonbit_array_length(bytes);
  char *buffer = mb_allocate_c_string(len, "Failed to allocate string buffer");
  if (buffer == NULL) {
    return NULL;
  }
  if (len > 0) {
    memcpy(buffer, bytes, len);
  }
  return buffer;
}

#ifdef _WIN32
static void mb_set_windows_error(DWORD code, const char *fallback) {
  char message[512] = "";
  DWORD flags = FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS;
  DWORD len = FormatMessageA(
    flags,
    NULL,
    code,
    MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
    message,
    (DWORD)sizeof(message),
    NULL
  );
  if (len == 0) {
    mb_set_error((int32_t)code, fallback);
    return;
  }
  while (len > 0 &&
         (message[len - 1] == '\r' || message[len - 1] == '\n' || message[len - 1] == ' ')) {
    message[--len] = '\0';
  }
  mb_set_error((int32_t)code, message);
}

static wchar_t *mb_utf8_to_wide(const char *value) {
  int length = 0;
  wchar_t *wide = NULL;
  if (value == NULL) {
    return NULL;
  }
  length = MultiByteToWideChar(CP_UTF8, 0, value, -1, NULL, 0);
  if (length <= 0) {
    mb_set_windows_error(GetLastError(), "Failed to convert UTF-8 path");
    return NULL;
  }
  wide = (wchar_t *)malloc((size_t)length * sizeof(wchar_t));
  if (wide == NULL) {
    mb_set_error(ENOMEM, "Failed to allocate wide string buffer");
    return NULL;
  }
  if (MultiByteToWideChar(CP_UTF8, 0, value, -1, wide, length) <= 0) {
    free(wide);
    mb_set_windows_error(GetLastError(), "Failed to convert UTF-8 path");
    return NULL;
  }
  return wide;
}

static char *mb_wide_to_c_string(const wchar_t *value) {
  int length = 0;
  char *buffer = NULL;
  if (value == NULL) {
    return NULL;
  }
  length = WideCharToMultiByte(CP_UTF8, 0, value, -1, NULL, 0, NULL, NULL);
  if (length <= 0) {
    mb_set_windows_error(GetLastError(), "Failed to convert wide path");
    return NULL;
  }
  buffer = (char *)malloc((size_t)length);
  if (buffer == NULL) {
    mb_set_error(ENOMEM, "Failed to allocate UTF-8 string buffer");
    return NULL;
  }
  if (WideCharToMultiByte(CP_UTF8, 0, value, -1, buffer, length, NULL, NULL) <= 0) {
    free(buffer);
    mb_set_windows_error(GetLastError(), "Failed to convert wide path");
    return NULL;
  }
  return buffer;
}

static int mb_write_utf8_text_file(const wchar_t *path, const char *contents) {
  FILE *file = NULL;
  errno_t status = _wfopen_s(&file, path, L"wb");
  size_t len = 0;
  if (status != 0 || file == NULL) {
    mb_set_error((int32_t)status, "Failed to create helper script");
    return MB_STATUS_ERROR;
  }
  len = strlen(contents);
  if (len > 0 && fwrite(contents, 1, len, file) != len) {
    fclose(file);
    mb_set_error(errno, "Failed to write helper script");
    return MB_STATUS_ERROR;
  }
  if (fclose(file) != 0) {
    mb_set_error(errno, "Failed to close helper script");
    return MB_STATUS_ERROR;
  }
  return MB_STATUS_OK;
}

static int mb_create_temp_script_path(wchar_t *buffer, DWORD buffer_len) {
  DWORD temp_len = GetTempPathW(buffer_len, buffer);
  DWORD pid = GetCurrentProcessId();
  if (temp_len == 0 || temp_len >= buffer_len) {
    mb_set_windows_error(GetLastError(), "Failed to get temp directory");
    return MB_STATUS_ERROR;
  }
  if (_snwprintf_s(
        buffer + temp_len,
        buffer_len - temp_len,
        _TRUNCATE,
        L"mb_replace_self_%lu_%llu.cmd",
        (unsigned long)pid,
        (unsigned long long)GetTickCount64()
      ) < 0) {
    mb_set_error(ENOMEM, "Failed to build helper script path");
    return MB_STATUS_ERROR;
  }
  return MB_STATUS_OK;
}

static int mb_spawn_detached_cmd_script(const wchar_t *script_path) {
  wchar_t command_line[4096];
  STARTUPINFOW startup_info;
  PROCESS_INFORMATION process_info;
  ZeroMemory(&startup_info, sizeof(startup_info));
  ZeroMemory(&process_info, sizeof(process_info));
  startup_info.cb = sizeof(startup_info);
  startup_info.dwFlags = STARTF_USESHOWWINDOW;
  startup_info.wShowWindow = SW_HIDE;
  if (_snwprintf_s(
        command_line,
        sizeof(command_line) / sizeof(command_line[0]),
        _TRUNCATE,
        L"cmd.exe /d /c \"%ls\"",
        script_path
      ) < 0) {
    mb_set_error(ENOMEM, "Failed to build helper command line");
    return MB_STATUS_ERROR;
  }
  if (!CreateProcessW(
        NULL,
        command_line,
        NULL,
        NULL,
        FALSE,
        DETACHED_PROCESS | CREATE_NO_WINDOW,
        NULL,
        NULL,
        &startup_info,
        &process_info
      )) {
    mb_set_windows_error(GetLastError(), "Failed to launch helper script");
    return MB_STATUS_ERROR;
  }
  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);
  return MB_STATUS_OK;
}

static int mb_schedule_windows_action(const char *script_body) {
  wchar_t script_path[MAX_PATH];
  if (mb_create_temp_script_path(script_path, MAX_PATH) != MB_STATUS_OK) {
    return MB_STATUS_ERROR;
  }
  if (mb_write_utf8_text_file(script_path, script_body) != MB_STATUS_OK) {
    return MB_STATUS_ERROR;
  }
  if (mb_spawn_detached_cmd_script(script_path) != MB_STATUS_OK) {
    _wremove(script_path);
    return MB_STATUS_ERROR;
  }
  mb_clear_error();
  return MB_STATUS_OK;
}

static int mb_build_windows_self_action_script(
  char *buffer,
  size_t buffer_len,
  const char *current_path,
  const char *replacement_path,
  const char *action_name
) {
  int written = replacement_path == NULL
    ? snprintf(
        buffer,
        buffer_len,
        "@echo off\r\n"
        "setlocal enableextensions\r\n"
        ":retry\r\n"
        "del /f /q \"%s\" >nul 2>nul\r\n"
        "if exist \"%s\" (\r\n"
        "  timeout /t 1 /nobreak >nul\r\n"
        "  goto retry\r\n"
        ")\r\n"
        "del /f /q \"%%~f0\" >nul 2>nul\r\n",
        current_path,
        current_path
      )
    : snprintf(
        buffer,
        buffer_len,
        "@echo off\r\n"
        "setlocal enableextensions\r\n"
        ":retry\r\n"
        "del /f /q \"%s\" >nul 2>nul\r\n"
        "if exist \"%s\" (\r\n"
        "  timeout /t 1 /nobreak >nul\r\n"
        "  goto retry\r\n"
        ")\r\n"
        "move /y \"%s\" \"%s\" >nul 2>nul\r\n"
        "if errorlevel 1 (\r\n"
        "  timeout /t 1 /nobreak >nul\r\n"
        "  goto retry\r\n"
        ")\r\n"
        "del /f /q \"%%~f0\" >nul 2>nul\r\n",
        current_path,
        current_path,
        replacement_path,
        current_path
      );
  if (written < 0 || (size_t)written >= buffer_len) {
    mb_set_error(ENOMEM, action_name);
    return MB_STATUS_ERROR;
  }
  return MB_STATUS_OK;
}

static int mb_schedule_windows_self_action(
  const char *current_path,
  const char *replacement_path,
  const char *build_error_message
) {
  char script[8192];
  if (mb_build_windows_self_action_script(
        script,
        sizeof(script),
        current_path,
        replacement_path,
        build_error_message
      ) != MB_STATUS_OK) {
    return MB_STATUS_ERROR;
  }
  return mb_schedule_windows_action(script);
}

static int mb_windows_replace_self(const char *replacement_path, const char *current_path) {
  return mb_schedule_windows_self_action(
    current_path,
    replacement_path,
    "Failed to build replace-self helper script"
  );
}

static int mb_windows_delete_self(const char *current_path) {
  return mb_schedule_windows_self_action(
    current_path,
    NULL,
    "Failed to build delete-self helper script"
  );
}

static wchar_t *mb_current_executable_path_wide(void) {
  DWORD size = MAX_PATH;
  while (1) {
    DWORD written = 0;
    wchar_t *buffer = (wchar_t *)malloc((size_t)size * sizeof(wchar_t));
    if (buffer == NULL) {
      mb_set_error(ENOMEM, "Failed to allocate executable path buffer");
      return NULL;
    }
    written = GetModuleFileNameW(NULL, buffer, size);
    if (written == 0) {
      free(buffer);
      mb_set_windows_error(GetLastError(), "Failed to get current executable path");
      return NULL;
    }
    if (written < size - 1) {
      buffer[written] = L'\0';
      mb_clear_error();
      return buffer;
    }
    free(buffer);
    size *= 2;
  }
}
#endif

static char *mb_current_executable_path_cstr(void) {
#ifdef _WIN32
  wchar_t *buffer = mb_current_executable_path_wide();
  char *result = NULL;
  if (buffer == NULL) {
    return NULL;
  }
  result = mb_wide_to_c_string(buffer);
  free(buffer);
  if (result == NULL) {
    return NULL;
  }
  mb_clear_error();
  return result;
#elif defined(__APPLE__)
  uint32_t size = 0;
  char *buffer = NULL;
  char *resolved = NULL;
  _NSGetExecutablePath(NULL, &size);
  buffer = (char *)malloc((size_t)size + 1);
  if (buffer == NULL) {
    mb_set_error(ENOMEM, "Failed to allocate executable path buffer");
    return NULL;
  }
  if (_NSGetExecutablePath(buffer, &size) != 0) {
    free(buffer);
    mb_set_error(errno, "Failed to get current executable path");
    return NULL;
  }
  resolved = realpath(buffer, NULL);
  free(buffer);
  if (resolved == NULL) {
    mb_set_errno_error("Failed to resolve current executable path");
    return NULL;
  }
  mb_clear_error();
  return resolved;
#elif defined(__linux__)
  char buffer[PATH_MAX];
  ssize_t written = readlink("/proc/self/exe", buffer, sizeof(buffer) - 1);
  if (written < 0) {
    mb_set_errno_error("Failed to read /proc/self/exe");
    return NULL;
  }
  buffer[written] = '\0';
  mb_clear_error();
  return strdup(buffer);
#else
  mb_set_error(ENOTSUP, "Unsupported platform");
  return NULL;
#endif
}

static int mb_replace_self_impl(const char *replacement_path) {
  char *current_path = mb_current_executable_path_cstr();
  if (current_path == NULL) {
    return MB_STATUS_ERROR;
  }
#ifdef _WIN32
  if (mb_windows_replace_self(replacement_path, current_path) != MB_STATUS_OK) {
    free(current_path);
    return MB_STATUS_ERROR;
  }
#else
  if (rename(replacement_path, current_path) != 0) {
    free(current_path);
    return mb_set_errno_error("Failed to rename replacement executable");
  }
  mb_clear_error();
#endif
  free(current_path);
  return MB_STATUS_OK;
}

static int mb_delete_self_impl(void) {
  char *current_path = mb_current_executable_path_cstr();
  if (current_path == NULL) {
    return MB_STATUS_ERROR;
  }
#ifdef _WIN32
  if (mb_windows_delete_self(current_path) != MB_STATUS_OK) {
    free(current_path);
    return MB_STATUS_ERROR;
  }
#else
  if (unlink(current_path) != 0) {
    free(current_path);
    return mb_set_errno_error("Failed to unlink current executable");
  }
  mb_clear_error();
#endif
  free(current_path);
  return MB_STATUS_OK;
}

static int mb_split_newline_args(const char *joined, char ***out_args) {
  size_t count = 0;
  size_t i = 0;
  char **args = NULL;
  if (joined == NULL || joined[0] == '\0') {
    *out_args = NULL;
    return 0;
  }
  for (i = 0; joined[i] != '\0'; i++) {
    if (joined[i] == '\n') {
      count++;
    }
  }
  count++;
  args = (char **)calloc(count + 1, sizeof(char *));
  if (args == NULL) {
    mb_set_error(ENOMEM, "Failed to allocate argument array");
    return MB_STATUS_ERROR;
  }
  {
    const char *start = joined;
    size_t index = 0;
    for (i = 0;; i++) {
      if (joined[i] == '\n' || joined[i] == '\0') {
        size_t len = (size_t)(&joined[i] - start);
        args[index] = (char *)malloc(len + 1);
        if (args[index] == NULL) {
          size_t j;
          for (j = 0; j < index; j++) {
            free(args[j]);
          }
          free(args);
          mb_set_error(ENOMEM, "Failed to allocate argument string");
          return MB_STATUS_ERROR;
        }
        memcpy(args[index], start, len);
        args[index][len] = '\0';
        index++;
        if (joined[i] == '\0') {
          break;
        }
        start = &joined[i + 1];
      }
    }
  }
  *out_args = args;
  return (int)count;
}

static void mb_free_split_args(char **args, int count) {
  int i;
  if (args == NULL) {
    return;
  }
  for (i = 0; i < count; i++) {
    free(args[i]);
  }
  free(args);
}

#ifdef _WIN32
static void mb_free_wide_args(wchar_t **args, int count) {
  int i;
  if (args == NULL) {
    return;
  }
  for (i = 0; i < count; i++) {
    free(args[i]);
  }
  free(args);
}

static int mb_append_quoted_windows_arg(
  wchar_t *buffer,
  size_t buffer_len,
  size_t *offset,
  const wchar_t *argument
) {
  int written = _snwprintf_s(
    buffer + *offset,
    buffer_len - *offset,
    _TRUNCATE,
    L" \"%ls\"",
    argument
  );
  if (written < 0) {
    mb_set_error(ENOMEM, "Failed to build process command line");
    return MB_STATUS_ERROR;
  }
  *offset += (size_t)written;
  return MB_STATUS_OK;
}

static int mb_run_process_windows(const char *executable, const char *joined_args) {
  wchar_t *wide_executable = NULL;
  wchar_t **wide_args = NULL;
  wchar_t command_line[8192];
  size_t offset = 0;
  STARTUPINFOW startup_info;
  PROCESS_INFORMATION process_info;
  char **args = NULL;
  int arg_count = 0;
  int exit_code = MB_PROCESS_ERROR;
  int i = 0;

  wide_executable = mb_utf8_to_wide(executable);
  if (wide_executable == NULL) {
    return MB_PROCESS_ERROR;
  }
  command_line[0] = L'\0';
  if (_snwprintf_s(
        command_line,
        sizeof(command_line) / sizeof(command_line[0]),
        _TRUNCATE,
        L"\"%ls\"",
        wide_executable
      ) < 0) {
    free(wide_executable);
    mb_set_error(ENOMEM, "Failed to build process command line");
    return MB_PROCESS_ERROR;
  }
  offset = wcslen(command_line);

  arg_count = mb_split_newline_args(joined_args, &args);
  if (arg_count == MB_STATUS_ERROR) {
    free(wide_executable);
    return MB_PROCESS_ERROR;
  }
  if (arg_count > 0) {
    wide_args = (wchar_t **)calloc((size_t)arg_count, sizeof(wchar_t *));
    if (wide_args == NULL) {
      mb_free_split_args(args, arg_count);
      free(wide_executable);
      mb_set_error(ENOMEM, "Failed to allocate wide argument array");
      return MB_PROCESS_ERROR;
    }
    for (i = 0; i < arg_count; i++) {
      wide_args[i] = mb_utf8_to_wide(args[i]);
      if (wide_args[i] == NULL) {
        mb_free_wide_args(wide_args, i);
        mb_free_split_args(args, arg_count);
        free(wide_executable);
        return MB_PROCESS_ERROR;
      }
      if (mb_append_quoted_windows_arg(
            command_line,
            sizeof(command_line) / sizeof(command_line[0]),
            &offset,
            wide_args[i]
          ) != MB_STATUS_OK) {
        mb_free_wide_args(wide_args, i + 1);
        mb_free_split_args(args, arg_count);
        free(wide_executable);
        return MB_PROCESS_ERROR;
      }
    }
  }

  ZeroMemory(&startup_info, sizeof(startup_info));
  ZeroMemory(&process_info, sizeof(process_info));
  startup_info.cb = sizeof(startup_info);
  if (!CreateProcessW(
        wide_executable,
        command_line,
        NULL,
        NULL,
        FALSE,
        0,
        NULL,
        NULL,
        &startup_info,
        &process_info
      )) {
    mb_set_windows_error(GetLastError(), "Failed to launch child process");
    goto cleanup;
  }
  WaitForSingleObject(process_info.hProcess, INFINITE);
  {
    DWORD child_status = 0;
    if (!GetExitCodeProcess(process_info.hProcess, &child_status)) {
      mb_set_windows_error(GetLastError(), "Failed to get child exit code");
      CloseHandle(process_info.hThread);
      CloseHandle(process_info.hProcess);
      goto cleanup;
    }
    exit_code = (int)child_status;
  }
  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);
  mb_clear_error();

cleanup:
  mb_free_wide_args(wide_args, arg_count);
  mb_free_split_args(args, arg_count > 0 ? arg_count : 0);
  free(wide_executable);
  return exit_code;
}
#else
static int mb_run_process_unix(const char *executable, const char *joined_args) {
  char **args = NULL;
  int arg_count = 0;
  pid_t pid;
  int status = 0;
  char **argv = NULL;
  int i = 0;

  arg_count = mb_split_newline_args(joined_args, &args);
  if (arg_count == MB_STATUS_ERROR) {
    return MB_PROCESS_ERROR;
  }
  argv = (char **)calloc((size_t)arg_count + 2, sizeof(char *));
  if (argv == NULL) {
    mb_free_split_args(args, arg_count > 0 ? arg_count : 0);
    mb_set_error(ENOMEM, "Failed to allocate argv");
    return MB_PROCESS_ERROR;
  }
  argv[0] = (char *)executable;
  for (i = 0; i < arg_count; i++) {
    argv[i + 1] = args[i];
  }
  argv[arg_count + 1] = NULL;

  pid = fork();
  if (pid < 0) {
    free(argv);
    mb_free_split_args(args, arg_count > 0 ? arg_count : 0);
    mb_set_errno_error("Failed to fork child process");
    return MB_PROCESS_ERROR;
  }
  if (pid == 0) {
    execvp(executable, argv);
    _exit(127);
  }
  if (waitpid(pid, &status, 0) < 0) {
    free(argv);
    mb_free_split_args(args, arg_count > 0 ? arg_count : 0);
    mb_set_errno_error("Failed to wait for child process");
    return MB_PROCESS_ERROR;
  }
  free(argv);
  mb_free_split_args(args, arg_count > 0 ? arg_count : 0);
  mb_clear_error();
  if (WIFEXITED(status)) {
    return WEXITSTATUS(status);
  }
  mb_set_error(ECHILD, "Child process terminated unexpectedly");
  return MB_PROCESS_ERROR;
}
#endif

MOONBIT_FFI_EXPORT int32_t mb_replace_self_platform_code(void) {
#ifdef _WIN32
  return 1;
#elif defined(__APPLE__)
  return 2;
#elif defined(__linux__)
  return 3;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t mb_replace_self_current_executable_path(void) {
#ifdef _WIN32
  wchar_t *buffer = mb_current_executable_path_wide();
  moonbit_bytes_t out;
  if (buffer == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  out = mb_make_bytes_from_wide_buffer(buffer, wcslen(buffer) + 1);
  free(buffer);
  return out;
#else
  char *path = mb_current_executable_path_cstr();
  moonbit_bytes_t out;
  if (path == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  out = mb_make_bytes_from_buffer(path, strlen(path));
  free(path);
  return out;
#endif
}

MOONBIT_FFI_EXPORT int32_t mb_replace_self_replace_self(moonbit_bytes_t replacement_path) {
  char *replacement = mb_bytes_to_c_string(replacement_path);
  int status;
  if (replacement == NULL) {
    return MB_STATUS_ERROR;
  }
  status = mb_replace_self_impl(replacement);
  free(replacement);
  return status;
}

MOONBIT_FFI_EXPORT int32_t mb_replace_self_delete_self(void) {
  return mb_delete_self_impl();
}

MOONBIT_FFI_EXPORT int32_t mb_replace_self_last_error_code(void) {
  return mb_last_error_code;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t mb_replace_self_last_error_message(void) {
  return mb_make_bytes_from_buffer(
    mb_last_error_message,
    strlen(mb_last_error_message)
  );
}

MOONBIT_FFI_EXPORT int32_t mb_replace_self_run_process(
  moonbit_bytes_t executable,
  moonbit_bytes_t arguments
) {
  char *exe = mb_bytes_to_c_string(executable);
  char *args = mb_bytes_to_c_string(arguments);
  int status = MB_PROCESS_ERROR;
  if (exe == NULL || args == NULL) {
    free(exe);
    free(args);
    return MB_PROCESS_ERROR;
  }
#ifdef _WIN32
  status = mb_run_process_windows(exe, args);
#else
  status = mb_run_process_unix(exe, args);
#endif
  free(exe);
  free(args);
  return status;
}

MOONBIT_FFI_EXPORT void mb_replace_self_sleep_millis(int32_t milliseconds) {
#ifdef _WIN32
  Sleep((DWORD)milliseconds);
#else
  struct timespec duration;
  duration.tv_sec = milliseconds / 1000;
  duration.tv_nsec = (long)(milliseconds % 1000) * 1000000L;
  nanosleep(&duration, NULL);
#endif
}
