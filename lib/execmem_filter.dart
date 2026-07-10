import 'dart:ffi';

final class SockFilter extends Struct {
  @Uint16()
  external int code;

  @Uint8()
  external int jumpIfTrue;

  @Uint8()
  external int jumpIfFalse;

  @Uint32()
  external int value;
}

final class SockFprog extends Struct {
  @Uint16()
  external int length;

  external Pointer<SockFilter> filter;
}

typedef _MallocNative = Pointer<Void> Function(UintPtr);
typedef _MallocDart = Pointer<Void> Function(int);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);
typedef _PrctlNative = Int32 Function(Int32, Uint64, Uint64, Uint64, Uint64);
typedef _PrctlDart = int Function(int, int, int, int, int);
typedef _SyscallNative = IntPtr Function(IntPtr, IntPtr, IntPtr, Pointer<Void>);
typedef _SyscallDart = int Function(int, int, int, Pointer<Void>);

const _bpfLoadWordAbsolute = 0x20;
const _bpfJumpEqual = 0x15;
const _bpfJumpBitsSet = 0x45;
const _bpfReturn = 0x06;
const _seccompReturnErrno = 0x00050000;
const _seccompReturnAllow = 0x7fff0000;

const _linuxErrnoAccess = 13;
const _linuxMprotectArm64 = 226;
const _linuxSeccompArm64 = 277;
const _prSetNoNewPrivileges = 38;
const _seccompSetModeFilter = 1;
const _seccompFilterFlagTsync = 1;
const _protExecute = 4;

/// Installs an irreversible, process-wide test filter on Android ARM64.
///
/// The filter returns EACCES only when `mprotect` requests `PROT_EXEC`. It is
/// a controlled model of the syscall failure, not a GrapheneOS implementation
/// or a reusable security sandbox. Force-stopping the app removes the filter.
void installExecMemoryDenial() {
  if (Abi.current() != Abi.androidArm64) {
    throw UnsupportedError('The controlled harness requires Android ARM64.');
  }

  final libc = DynamicLibrary.open('libc.so');
  final malloc = libc.lookupFunction<_MallocNative, _MallocDart>('malloc');
  final free = libc.lookupFunction<_FreeNative, _FreeDart>('free');
  final prctl = libc.lookupFunction<_PrctlNative, _PrctlDart>('prctl');
  final syscall = libc.lookupFunction<_SyscallNative, _SyscallDart>('syscall');

  Pointer<Void> filtersMemory = nullptr;
  Pointer<Void> programMemory = nullptr;
  try {
    filtersMemory = malloc(sizeOf<SockFilter>() * 6);
    programMemory = malloc(sizeOf<SockFprog>());
    if (filtersMemory == nullptr || programMemory == nullptr) {
      throw StateError('Could not allocate the seccomp filter.');
    }

    final filters = filtersMemory.cast<SockFilter>();
    void instruction(int index, int code, int jt, int jf, int value) {
      (filters + index).ref
        ..code = code
        ..jumpIfTrue = jt
        ..jumpIfFalse = jf
        ..value = value;
    }

    instruction(0, _bpfLoadWordAbsolute, 0, 0, 0); // seccomp_data.nr
    instruction(1, _bpfJumpEqual, 0, 3, _linuxMprotectArm64);
    instruction(2, _bpfLoadWordAbsolute, 0, 0, 32); // args[2]: prot
    instruction(3, _bpfJumpBitsSet, 0, 1, _protExecute);
    instruction(4, _bpfReturn, 0, 0, _seccompReturnErrno | _linuxErrnoAccess);
    instruction(5, _bpfReturn, 0, 0, _seccompReturnAllow);

    final program = programMemory.cast<SockFprog>();
    program.ref
      ..length = 6
      ..filter = filters;

    final noNewPrivileges = prctl(_prSetNoNewPrivileges, 1, 0, 0, 0);
    if (noNewPrivileges != 0) {
      throw StateError('PR_SET_NO_NEW_PRIVS failed: $noNewPrivileges');
    }

    final seccompResult = syscall(
      _linuxSeccompArm64,
      _seccompSetModeFilter,
      _seccompFilterFlagTsync,
      program.cast<Void>(),
    );
    if (seccompResult != 0) {
      throw StateError('Installing the seccomp filter failed: $seccompResult');
    }
  } finally {
    if (programMemory != nullptr) free(programMemory);
    if (filtersMemory != nullptr) free(filtersMemory);
  }
}
