using System;using System.Collections.Generic;using System.Diagnostics;using System.Runtime.InteropServices;using System.Text;
public sealed class GptWidgetSupervisorHost {public long handle;public int pid;public long started;public bool visible;}
public static class GptWidgetSupervisorNative {
 static readonly int Session=CurrentSession();
 static int CurrentSession(){using(var process=Process.GetCurrentProcess())return process.SessionId;}
 public delegate bool EnumProc(IntPtr h,IntPtr p);
 [DllImport("user32.dll")]static extern bool EnumWindows(EnumProc cb,IntPtr p);
 [DllImport("user32.dll")]public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")]static extern IntPtr GetWindowLongPtr(IntPtr h,int index);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetClassName(IntPtr h,StringBuilder text,int size);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetWindowText(IntPtr h,StringBuilder text,int size);
 [DllImport("dwmapi.dll")]static extern int DwmGetWindowAttribute(IntPtr h,int attribute,out uint value,int size);
 public static bool MainWindowStyle(long style,long extended){return (extended&0x80)==0&&(extended&0x08000000)==0&&(extended&0x40000)!=0&&(style&0x10000)!=0;}
 public static int ProcessId(IntPtr h){uint value;GetWindowThreadProcessId(h,out value);return (int)value;}
 static bool CodexProcess(Process process){
  if(process.SessionId!=Session)return false;
  if(!process.ProcessName.Equals("ChatGPT",StringComparison.OrdinalIgnoreCase)&&!process.ProcessName.Equals("Codex",StringComparison.OrdinalIgnoreCase))return false;
  string file=process.MainModule.FileName;
  return file.IndexOf("\\OpenAI.Codex_",StringComparison.OrdinalIgnoreCase)>=0||file.IndexOf("\\OpenAI\\Codex\\",StringComparison.OrdinalIgnoreCase)>=0;
 }
 public static GptWidgetSupervisorHost Inspect(IntPtr h){
  try{
   if(!IsWindow(h)||!MainWindowStyle(GetWindowLongPtr(h,-16).ToInt64(),GetWindowLongPtr(h,-20).ToInt64()))return null;
   var text=new StringBuilder(256);GetWindowText(h,text,256);if(text.Length==0)return null;
   var cls=new StringBuilder(128);GetClassName(h,cls,128);if(cls.ToString()!="Chrome_WidgetWin_1")return null;
   using(var process=Process.GetProcessById(ProcessId(h))){
    if(!CodexProcess(process))return null;
    uint cloaked;bool visible=IsWindowVisible(h)&&!IsIconic(h)&&(DwmGetWindowAttribute(h,14,out cloaked,4)!=0||cloaked==0);
    return new GptWidgetSupervisorHost{handle=h.ToInt64(),pid=process.Id,started=process.StartTime.ToUniversalTime().Ticks,visible=visible};
   }
  }catch{return null;}
 }
 public static GptWidgetSupervisorHost[] Hosts(){var hosts=new List<GptWidgetSupervisorHost>();EnumWindows((h,p)=>{var host=Inspect(h);if(host!=null)hosts.Add(host);return true;},IntPtr.Zero);return hosts.ToArray();}
}
