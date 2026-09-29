#pragma once

#include <cstddef>

// Executable memory for the PPC recompiler on platforms that forbid turning writable pages executable (iPadOS).
//
// A single pool is mapped twice: code is written through a read/write alias and executed from a separate
// read/execute mapping of the same physical pages. On iPadOS 26+ devices with TXM the executable pages must
// additionally be prepared by an attached debugger (StikDebug), which is why the whole pool is set up at once.
namespace JitMemory
{
	// claims a low address range for the pool. Call early, before the guest address space is reserved
	void ReserveAddressRange();

	// maps the pool executable. On iPadOS this requires an attached debugger. Safe to call repeatedly
	bool Enable();
	bool IsEnabled();

	// true if the process is currently marked as debugged (CS_DEBUGGED), i.e. JIT can be enabled
	bool IsDebuggerAttached();

	// human readable reason when Enable() failed
	const char* GetLastError();

	// copies finished code into the pool and returns its executable address, or nullptr if the pool is full
	void* CommitCode(const void* code, size_t size);
	void FreeCode(void* executableCode, size_t size);
}
