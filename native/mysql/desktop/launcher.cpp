#include <cstdlib>
#include <iostream>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string>
#include <vector>

namespace {
std::wstring quote(const wchar_t *argument)
{
    std::wstring value = L"\"";
    size_t slashes = 0;
    for (const wchar_t *cursor = argument; *cursor; ++cursor) {
        if (*cursor == L'\\') { ++slashes; continue; }
        value.append(slashes * (*cursor == L'"' ? 2 : 1), L'\\');
        slashes = 0;
        if (*cursor == L'"') value += L'\\';
        value += *cursor;
    }
    value.append(slashes * 2, L'\\');
    return value + L'"';
}
}

int wmain(int argc, wchar_t **argv)
{
    if (argc < 3) return 64;
    wchar_t *end = nullptr;
    const auto owner_id = std::wcstoul(argv[1], &end, 10);
    if (!end || *end || !owner_id || owner_id > MAXDWORD) return 64;
    HANDLE owner = OpenProcess(SYNCHRONIZE, FALSE, static_cast<DWORD>(owner_id));
    if (!owner || WaitForSingleObject(owner, 0) != WAIT_TIMEOUT) return 65;
    HANDLE job = CreateJobObjectW(nullptr, nullptr);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!job || !SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) return 66;

    // Assign the child to its lifetime job at creation, before it can execute.
    SIZE_T size = 0;
    InitializeProcThreadAttributeList(nullptr, 1, 0, &size);
    std::vector<char> storage(size);
    auto *attributes = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage.data());
    if (!InitializeProcThreadAttributeList(attributes, 1, 0, &size) ||
        !UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_JOB_LIST,
                                   &job, sizeof(job), nullptr, nullptr)) return 67;
    STARTUPINFOEXW startup{};
    startup.StartupInfo.cb = sizeof(startup);
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    startup.StartupInfo.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    startup.StartupInfo.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    startup.lpAttributeList = attributes;
    std::wstring command;
    for (int index = 2; index < argc; ++index) {
        if (index != 2) command += L' ';
        command += quote(argv[index]);
    }
    PROCESS_INFORMATION process{};
    const BOOL started = CreateProcessW(argv[2], command.data(), nullptr, nullptr, TRUE,
        EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW, nullptr, nullptr, &startup.StartupInfo, &process);
    DeleteProcThreadAttributeList(attributes);
    if (!started) return 68;
    CloseHandle(process.hThread);
    HANDLE handles[] = {owner, process.hProcess};
    const DWORD waited = WaitForMultipleObjects(2, handles, FALSE, INFINITE);
    if (waited != WAIT_OBJECT_0 + 1) TerminateJobObject(job, 125);
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD status = 125;
    GetExitCodeProcess(process.hProcess, &status);
    CloseHandle(process.hProcess);
    CloseHandle(owner);
    CloseHandle(job);
    return static_cast<int>(status);
}
#else
#include <cerrno>
#include <csignal>
#include <unistd.h>
#ifdef __linux__
#include <sys/prctl.h>
#else
#include <sys/event.h>
#include <sys/wait.h>
#endif

int main(int argc, char **argv)
{
    if (argc < 3) return 64;
    char *end = nullptr;
    const long owner = std::strtol(argv[1], &end, 10);
    if (!end || *end || owner <= 0 || owner != getppid()) return 65;
#ifdef __linux__
    if (prctl(PR_SET_PDEATHSIG, SIGTERM) != 0 || getppid() != owner) return 66;
    execv(argv[2], argv + 2);
    std::cerr << "Could not execute bundled mysqld: " << errno << '\n';
    return 68;
#else
    const int queue = kqueue();
    if (queue < 0) return 66;
    struct kevent parent;
    EV_SET(&parent, owner, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, nullptr);
    if (kevent(queue, &parent, 1, nullptr, 0, nullptr) != 0 || getppid() != owner) return 66;
    const pid_t child = fork();
    if (child < 0) return 67;
    if (child == 0) { close(queue); execv(argv[2], argv + 2); _exit(68); }
    struct kevent child_event;
    EV_SET(&child_event, child, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, nullptr);
    if (kevent(queue, &child_event, 1, nullptr, 0, nullptr) != 0) {
        kill(child, SIGKILL); waitpid(child, nullptr, 0); return 67;
    }
    struct kevent event;
    if (kevent(queue, nullptr, 0, &event, 1, nullptr) <= 0 || event.ident == static_cast<uintptr_t>(owner)) {
        kill(child, SIGTERM);
        for (int attempt = 0; attempt < 100; ++attempt) {
            int status;
            if (waitpid(child, &status, WNOHANG) == child) return 125;
            usleep(100000);
        }
        kill(child, SIGKILL);
    }
    int status = 0;
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
    close(queue);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 125;
#endif
}
#endif
