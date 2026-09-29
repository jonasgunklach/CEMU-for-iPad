#include "util/MemMapper/JitMemory.h"

#include <TargetConditionals.h>
#include <libkern/OSCacheControl.h>
#include <mach/mach.h>
#include <signal.h>
#include <sys/mman.h>
#include <unistd.h>

// iPadOS JIT, following the protocol used by StikDebug's "universal" script (see StikJIT INTEGRATION.md):
//  brk #0xf00d with x16=1, x0=address, x1=size -> the debugger prepares (blesses) the executable region
//  brk #0xf00d with x16=0                      -> the debugger detaches
// Executable pages stay usable for the lifetime of the process after the debugger detached.

extern "C" int csops(pid_t pid, unsigned int ops, void* useraddr, size_t usersize);

namespace
{
	constexpr unsigned int CS_OPS_STATUS = 0;
	constexpr uint32 CS_DEBUGGED = 0x10000000;

	constexpr size_t kPoolSize = 512 * 1024 * 1024;
	constexpr size_t kAlignment = 64;
	// StikDebug encodes addresses as 36 bit values, keep the pool below 64GiB
	constexpr uintptr_t kPoolAddressHint = 0x200000000;
	constexpr uintptr_t kPoolAddressLimit = 0x1000000000;

	constexpr uint32 kBrkF00d = 0xD4200000 | (0xF00D << 5);

	uint8* s_rx = nullptr; // executable alias
	uint8* s_rw = nullptr; // writable alias
	bool s_reserved = false;
	bool s_enabled = false;
	const char* s_lastError = "JIT has not been enabled";

	std::mutex s_allocMutex;
	std::map<size_t, size_t> s_freeList; // offset -> size

	std::atomic_bool s_trapUnhandled = false;

	__attribute__((noinline, optnone, naked)) void* JIT26PrepareRegion(void* addr, size_t size)
	{
		asm("mov x16, #1\n"
			"brk #0xf00d\n"
			"ret");
	}

	__attribute__((noinline, optnone, naked)) void JIT26Detach()
	{
		asm("mov x16, #0\n"
			"brk #0xf00d\n"
			"ret");
	}

	// a debugger that does not understand the protocol forwards the trap to us: skip the instruction
	void TrapHandler(int, siginfo_t*, void* context)
	{
		auto* uc = (ucontext_t*)context;
		uint64 pc = uc->uc_mcontext->__ss.__pc;
		if (*(uint32*)pc == kBrkF00d)
		{
			s_trapUnhandled = true;
			uc->uc_mcontext->__ss.__pc = pc + 4;
		}
	}

	// returns false if nobody handled the request
	bool SendDebuggerRequest(bool prepare)
	{
		struct sigaction action{}, previous{};
		action.sa_sigaction = TrapHandler;
		action.sa_flags = SA_SIGINFO;
		sigemptyset(&action.sa_mask);
		sigaction(SIGTRAP, &action, &previous);
		s_trapUnhandled = false;
		if (prepare)
			JIT26PrepareRegion(s_rx, kPoolSize);
		else
			JIT26Detach();
		sigaction(SIGTRAP, &previous, nullptr);
		return !s_trapUnhandled;
	}

	bool SelfTest()
	{
		// mov w0, #42; ret
		const uint32 code[] = {0x52800540, 0xD65F03C0};
		void* fn = JitMemory::CommitCode(code, sizeof(code));
		if (!fn)
			return false;
		const int result = ((int (*)())fn)();
		JitMemory::FreeCode(fn, sizeof(code));
		return result == 42;
	}
}

void JitMemory::ReserveAddressRange()
{
	if (s_reserved)
		return;
	void* p = mmap((void*)kPoolAddressHint, kPoolSize, PROT_NONE, MAP_ANON | MAP_PRIVATE, -1, 0);
	if (p == MAP_FAILED)
	{
		cemuLog_log(LogType::Force, "JIT: failed to reserve {}MB address range", kPoolSize / 1024 / 1024);
		return;
	}
	if ((uintptr_t)p + kPoolSize > kPoolAddressLimit)
		cemuLog_log(LogType::Force, "JIT: pool at {} is above 64GiB, StikDebug may not be able to prepare it", p);
	s_rx = (uint8*)p;
	s_reserved = true;
}

bool JitMemory::IsDebuggerAttached()
{
#if TARGET_OS_SIMULATOR
	return true;
#else
	uint32 flags = 0;
	csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags));
	return (flags & CS_DEBUGGED) != 0;
#endif
}

bool JitMemory::Enable()
{
	if (s_enabled)
		return true;
	ReserveAddressRange();
	if (!s_reserved)
	{
		s_lastError = "Unable to reserve memory for the JIT";
		return false;
	}
	if (!IsDebuggerAttached())
	{
		s_lastError = "JIT requires an attached debugger (for example StikDebug)";
		return false;
	}

	if (mmap(s_rx, kPoolSize, PROT_READ | PROT_EXEC, MAP_ANON | MAP_PRIVATE | MAP_FIXED, -1, 0) == MAP_FAILED)
	{
		s_lastError = "Unable to map executable memory";
		return false;
	}

#if !TARGET_OS_SIMULATOR
	// on TXM devices the debugger has to touch every page before it can be executed
	const bool debuggerPrepared = SendDebuggerRequest(true);
	cemuLog_log(LogType::Force, "JIT: debugger {} the executable region", debuggerPrepared ? "prepared" : "did not prepare");
#endif

	vm_address_t rw = 0;
	vm_prot_t curProt, maxProt;
	kern_return_t kr = vm_remap(mach_task_self(), &rw, kPoolSize, 0, VM_FLAGS_ANYWHERE, mach_task_self(), (vm_address_t)s_rx, FALSE, &curProt, &maxProt, VM_INHERIT_NONE);
	if (kr != KERN_SUCCESS || mprotect((void*)rw, kPoolSize, PROT_READ | PROT_WRITE) != 0)
	{
		s_lastError = "Unable to create the writable JIT mapping";
		return false;
	}
	s_rw = (uint8*)rw;
	s_freeList = {{0, kPoolSize}};
	s_enabled = true;

#if !TARGET_OS_SIMULATOR
	// let StikDebug detach, the pages stay executable
	if (debuggerPrepared)
		SendDebuggerRequest(false);
#endif

	if (!SelfTest())
	{
		s_enabled = false;
		s_lastError = "JIT self test failed";
		return false;
	}
	cemuLog_log(LogType::Force, "JIT: enabled, {}MB pool at {} (writable alias at {})", kPoolSize / 1024 / 1024, (void*)s_rx, (void*)s_rw);
	return true;
}

bool JitMemory::IsEnabled()
{
	return s_enabled;
}

const char* JitMemory::GetLastError()
{
	return s_lastError;
}

void* JitMemory::CommitCode(const void* code, size_t size)
{
	if (!s_enabled || size == 0)
		return nullptr;
	const size_t allocSize = (size + kAlignment - 1) & ~(kAlignment - 1);
	size_t offset;
	{
		std::scoped_lock lock(s_allocMutex);
		auto it = std::find_if(s_freeList.begin(), s_freeList.end(), [allocSize](const auto& entry) { return entry.second >= allocSize; });
		if (it == s_freeList.end())
		{
			cemuLog_log(LogType::Force, "JIT: code pool exhausted");
			return nullptr;
		}
		offset = it->first;
		const size_t remaining = it->second - allocSize;
		s_freeList.erase(it);
		if (remaining > 0)
			s_freeList.emplace(offset + allocSize, remaining);
	}
	memcpy(s_rw + offset, code, size);
	sys_icache_invalidate(s_rx + offset, size);
	return s_rx + offset;
}

void JitMemory::FreeCode(void* executableCode, size_t size)
{
	if (!executableCode || size == 0)
		return;
	cemu_assert_debug((uint8*)executableCode >= s_rx && (uint8*)executableCode < s_rx + kPoolSize);
	size_t offset = (uint8*)executableCode - s_rx;
	size_t allocSize = (size + kAlignment - 1) & ~(kAlignment - 1);

	std::scoped_lock lock(s_allocMutex);
	// merge with the following free block
	auto next = s_freeList.find(offset + allocSize);
	if (next != s_freeList.end())
	{
		allocSize += next->second;
		s_freeList.erase(next);
	}
	// merge with the preceding free block
	auto it = s_freeList.lower_bound(offset);
	if (it != s_freeList.begin())
	{
		auto prev = std::prev(it);
		if (prev->first + prev->second == offset)
		{
			prev->second += allocSize;
			return;
		}
	}
	s_freeList.emplace(offset, allocSize);
}
