using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class GptNiangResourceJob {
 [StructLayout(LayoutKind.Sequential)] struct Basic {
  public long ProcessTime,JobTime; public uint Flags;
  public UIntPtr MinWorkingSet,MaxWorkingSet; public uint ActiveProcesses;
  public UIntPtr Affinity; public uint Priority,Scheduling;
 }
 [StructLayout(LayoutKind.Sequential)] struct Io {public ulong ReadOps,WriteOps,OtherOps,ReadBytes,WriteBytes,OtherBytes;}
 [StructLayout(LayoutKind.Sequential)] struct Extended {
  public Basic Basic; public Io Io;
  public UIntPtr ProcessMemory,JobMemory,PeakProcessMemory,PeakJobMemory;
 }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes,string name);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int info,ref Extended value,uint size);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job,int info,out Extended value,uint size,IntPtr returned);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool IsProcessInJob(IntPtr process,IntPtr job,out bool inside);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenJobObject(uint access,bool inherit,string name);
 [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
 static IntPtr handle;
 public static bool CurrentIsMember(string name) {
  IntPtr job=OpenJobObject(4,false,name);if(job==IntPtr.Zero)return false;
  try{bool inside;return IsProcessInJob(GetCurrentProcess(),job,out inside)&&inside;}
  finally{CloseHandle(job);}
 }
 public static void Enter(string name,ulong processBytes,ulong totalBytes) {
  if(handle!=IntPtr.Zero)return;
  IntPtr job=CreateJobObject(IntPtr.Zero,name);
  if(job==IntPtr.Zero)throw new Win32Exception();
  try {
   var limits=new Extended();limits.Basic.Flags=0x100|0x200;
   limits.ProcessMemory=new UIntPtr(processBytes);limits.JobMemory=new UIntPtr(totalBytes);
   if(!SetInformationJobObject(job,9,ref limits,(uint)Marshal.SizeOf(typeof(Extended))))throw new Win32Exception();
   bool inside;
   if(!IsProcessInJob(GetCurrentProcess(),job,out inside))throw new Win32Exception();
   if(!inside&&!AssignProcessToJobObject(job,GetCurrentProcess()))throw new Win32Exception();
   handle=job;job=IntPtr.Zero;
  }finally{if(job!=IntPtr.Zero)CloseHandle(job);}
 }
 public static ulong[] Limits() {
  Extended value;
  if(!QueryInformationJobObject(handle,9,out value,(uint)Marshal.SizeOf(typeof(Extended)),IntPtr.Zero))throw new Win32Exception();
  return new ulong[]{value.ProcessMemory.ToUInt64(),value.JobMemory.ToUInt64(),value.PeakJobMemory.ToUInt64()};
 }
}
