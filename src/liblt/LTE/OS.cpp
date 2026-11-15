#include "OS.h"
#include "Profiler.h"
#include "ProgramLog.h"
#include "StackFrame.h"
#include "Luau/Luau.h"
#include "String.h"

#include <csignal>
#include <cstring>
#include <iostream>

#include <sys/stat.h>

#ifdef LIBLT_WINDOWS

  /* (in small letters, as they are on a disk that tells the two apart:
     the build for Windows is made on Linux, with MinGW) */
  #include "process.h"
  #include "shlobj.h"
  #include "dbghelp.h"
  #ifdef _MSC_VER
    #include "windirent.h"
  #else
    #include <dirent.h>
  #endif
  #include "windows.h"
  #include "tchar.h"
  #include "direct.h"

  #undef CreateDirectory
  #undef MessageBox

#else

  #include <dirent.h>
  #include <execinfo.h>
  #include <spawn.h>
  #include <unistd.h>

  extern char **environ;

#endif

/* A process that dies on a signal reports 128 + the signal number, as a
   shell would, so scripts and test runners can tell a crash from a clean
   exit. _exit skips static destructors, which may not survive a crash. */
static void ExitOnSignal(int value) {
  fflush(stdout);
  fflush(stderr);
#ifdef LIBLT_WINDOWS
  exit(128 + value);
#else
  _exit(128 + value);
#endif
}

void IntHandler(int value) {
  StackFrame_Print();
  ExitOnSignal(value);
}

void OS_PrintBacktrace() {
  void* frames[62];
#ifdef LIBLT_WINDOWS
  USHORT count = CaptureStackBackTrace(0, 62, frames, NULL);
  char* base = (char*)GetModuleHandleA(NULL);
  printf("Native stack (%u frames; the program is loaded at %p):\n", (unsigned)count, (void*)base);
  for (USHORT i = 0; i < count; ++i)
    printf("  %p +0x%llx\n", frames[i], (unsigned long long)((char*)frames[i] - base));
#else
  int count = backtrace(frames, 62);
  printf("Native stack (%d frames):\n", count);
  fflush(stdout);
  backtrace_symbols_fd(frames, count, fileno(stdout));
#endif
  fflush(stdout);
}

void SegHandler(int value) {
  /* Restore the default action first: a second fault while reporting this
     one then ends the process instead of re-entering the handler. */
  signal(SIGSEGV, SIG_DFL);
  printf("\nAccess Violation\n");
  printf(" Doing : %s\n", StackFrame_Get().c_str());
  fflush(stdout);
  Luau_PrintTrace();
  OS_PrintBacktrace();
  StackFrame_Print();
  ExitOnSignal(value);
}

#ifdef LIBLT_WINDOWS
  /* Windows tells of a crash by an exception nobody handled: say what it
     was and where, on the program's output (an installed game's
     log.txt), and end. (Once: a second while saying it is left to
     Windows.) */
  LONG __stdcall Win32SegHandler(EXCEPTION_POINTERS* pExcept) {
    static bool reporting = false;
    if (reporting)
      return EXCEPTION_CONTINUE_SEARCH;
    reporting = true;
    char* base = (char*)GetModuleHandleA(NULL);
    if (pExcept && pExcept->ExceptionRecord) {
      EXCEPTION_RECORD* record = pExcept->ExceptionRecord;
      printf("\nThe program has crashed: exception 0x%08lx at %p +0x%llx\n",
        (unsigned long)record->ExceptionCode, record->ExceptionAddress,
        (unsigned long long)((char*)record->ExceptionAddress - base));
    } else
      printf("\nThe program has crashed\n");
    printf(" Doing : %s\n", StackFrame_Get().c_str());
    fflush(stdout);
    Luau_PrintTrace();
    OS_PrintBacktrace();
    fflush(stdout);
    fflush(stderr);
    TerminateProcess(GetCurrentProcess(), 128 + 11);
    return EXCEPTION_EXECUTE_HANDLER;
  }
#endif

bool OS_ChangeDir(const String& path) {
#ifdef LIBLT_WINDOWS
  return SetCurrentDirectoryA(path) != 0;
#else
  return chdir(path) == 0;
#endif
}

void OS_ConfigureSignalHandlers() {
#ifndef LIBLT_WINDOWS
  signal(SIGABRT, IntHandler);
  signal(SIGINT, IntHandler);
  signal(SIGSEGV, SegHandler);
#else
  SetUnhandledExceptionFilter(Win32SegHandler);
#endif
}

bool OS_CreateDir(const String& path) {
#ifdef LIBLT_WINDOWS
  return CreateDirectoryA(path, NULL) != 0;
#else
  return mkdir(path, 0777) == 0;
#endif
}

void OS_CreatePath(const String& path) {
  if (!path.size())
    return;

  std::stringstream stream(path);
  String buf;
  String partialPath;
  std::vector<String> partials;
  while (getline(stream, buf, '/'))
    partials.push_back(buf);
  for (size_t i = 0; i+ 1 < partials.size(); ++i) {
    partialPath += partials[i] + '/';
    OS_CreateDir(partialPath);
  }

  if (path.back() == '/')
    OS_CreateDir(path);
}

bool OS_FileExists(String const& path) {
  struct stat s;
  return stat(path, &s) == 0;
}

String OS_GetAppDir() {
#ifdef LIBLT_WINDOWS
  char path[MAX_PATH];
  SHGetFolderPath(NULL, CSIDL_APPDATA, NULL, SHGFP_TYPE_CURRENT, path);
  return path;
#else
  // TODO
  return "/usr/bin";
#endif
}

String OS_GetDocumentsDir() {
#ifdef LIBLT_WINDOWS
  char path[MAX_PATH];
  SHGetFolderPath(NULL, CSIDL_MYDOCUMENTS, NULL, SHGFP_TYPE_CURRENT, path);
  return path;
#else
  return "./data";
#endif
}

String OS_GetUserDataPath() {
  static bool created = false;
  if (!created) {
    created = true;
    OS_CreateDir("./cache/");
  }
  return "./cache/";
}

String OS_GetWorkingDir() {
  char path[1024];
#ifdef LIBLT_WINDOWS
  if (!_getcwd(path, sizeof(path)))
    return "";
#else
  if (!getcwd(path, sizeof(path)))
    return "";
#endif
  return path;
}

bool OS_IsDir(String const& path) {
  struct stat s;
  return stat(path, &s) == 0 && (s.st_mode & S_IFDIR);
}

bool OS_IsFile(String const& path) {
  struct stat s;
  return stat(path, &s) == 0 && (s.st_mode & S_IFREG);
}

Vector<String> OS_ListDir(String const& path) {
  Vector<String> result;
  DIR* dir = opendir(path);
  if (!dir)
    return result;

  dirent* entry;
  while ((entry = readdir(dir)))
    result.push(entry->d_name);
  closedir(dir);
  return result;
}

void OS_MessageBox(String const& title, String const& message) {
#ifdef LIBLT_WINDOWS
  MessageBoxA(NULL, message, title, MB_OK);
#else
  std::cout << "[" << title << "] : " << message << '\n';
  std::cerr << "[" << title << "] : " << message << '\n';
#endif
}

bool OS_Spawn(String const& path) {
  char* const argv[] = {strdup(path), NULL};
#ifdef LIBLT_WINDOWS
  STARTUPINFO info={sizeof(info)};
  PROCESS_INFORMATION processInfo;
  return CreateProcess(
    path, "", NULL, NULL, TRUE, 0, NULL, NULL, &info, &processInfo)
    != 0;
#else
  pid_t pid;
  return posix_spawn(&pid, path, NULL, NULL, argv, environ) == 0;
#endif
}

void OS_WriteDump(String const& path) {
#ifdef LIBLT_WINDOWS
  typedef BOOL (__stdcall *pDumpFn)
    (HANDLE hProcess, DWORD ProcessId, HANDLE hFile, MINIDUMP_TYPE DumpType,
     PMINIDUMP_EXCEPTION_INFORMATION ExceptionParam,
     PMINIDUMP_USER_STREAM_INFORMATION UserStreamParam,
     PMINIDUMP_CALLBACK_INFORMATION CallbackParam);

  HANDLE hFile = CreateFileA(path,
    GENERIC_READ | GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
    FILE_ATTRIBUTE_NORMAL, NULL);

  HMODULE h = LoadLibrary(_T("DbgHelp.dll"));
  LTE_ASSERT(h);
  if (!h)
    return;

  pDumpFn dumpFn = (pDumpFn)GetProcAddress(h, "MiniDumpWriteDump");
  if (!dumpFn)
    return;

  if(hFile && hFile != INVALID_HANDLE_VALUE) {
    BOOL rv = (*dumpFn)(GetCurrentProcess(), GetCurrentProcessId(),
                        hFile, MiniDumpNormal, 0, 0, 0);
    CloseHandle(hFile);
  }
  FreeLibrary(h);
#else
  /* TODO. */
#endif
}
