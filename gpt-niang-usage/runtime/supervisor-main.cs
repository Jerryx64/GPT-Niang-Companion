using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Management;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

// The resident watchdog needs no PowerShell runspace or WPF assemblies.
public static class GptNiangSupervisor {
 static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
 static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);
 static string app, data, sid, verifiedIdentity;
 static string FileAt(string name) { return Path.Combine(data, name); }
 static object Read(string name) {
  string file = FileAt(name);
  if (!File.Exists(file)) return null;
  try { return Json.DeserializeObject(System.IO.File.ReadAllText(file, Encoding.UTF8)); }
  catch { return null; }
 }
 static object Value(object obj, string key) {
  var map = obj as Dictionary<string, object>;
  object value; return map != null && map.TryGetValue(key, out value) ? value : null;
 }
 static string Text(object obj, string key) { return Convert.ToString(Value(obj, key), CultureInfo.InvariantCulture); }
 static long Number(object obj, string key) {
  long value; return Int64.TryParse(Text(obj, key), out value) ? value : 0;
 }
 static bool Flag(object obj, string key) { return Object.Equals(Value(obj, key), true); }
 static void Write(string name, object value) {
  string file = FileAt(name), temp = file + "." + Guid.NewGuid().ToString("N") + ".tmp";
  try {
   System.IO.File.WriteAllText(temp, Json.Serialize(value), Utf8);
   if (File.Exists(file)) File.Replace(temp, file, null); else File.Move(temp, file);
  } finally { if (File.Exists(temp)) File.Delete(temp); }
 }
 static void Block(string reason) { System.IO.File.WriteAllText(FileAt("resource-block.flag"), reason, Utf8); }
 static DateTime Utc(string value) {
  return DateTime.Parse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind).ToUniversalTime();
 }
 static bool Paused(object pause, GptWidgetSupervisorHost[] hosts) {
  if (pause == null) return false;
  if (Flag(pause, "desktop")) return true;
  foreach (var host in hosts) {
   if (Number(pause, "host") <= 0 || host.handle != Number(pause, "host")) continue;
   if (Number(pause, "hostPid") > 0 && host.pid != Number(pause, "hostPid")) continue;
   if (Number(pause, "hostStarted") > 0 && host.started != Number(pause, "hostStarted")) continue;
   return true;
  }
  return false;
 }
 static string Identity(Process process) {
  return process.Id + "|" + process.StartTime.ToUniversalTime().Ticks + "|" + app;
 }
 static bool RunningWidget() {
  var runtime = Read("runtime.json");
  int pid = (int)Number(runtime, "pid");
  IntPtr window = new IntPtr(Number(runtime, "widget"));
  if (pid <= 0 || !GptWidgetSupervisorNative.IsWindow(window) || GptWidgetSupervisorNative.ProcessId(window) != pid) return false;
  try {
   using (var process = Process.GetProcessById(pid)) {
    if (!process.ProcessName.Equals("powershell", StringComparison.OrdinalIgnoreCase) && !process.ProcessName.Equals("pwsh", StringComparison.OrdinalIgnoreCase)) return false;
    var start = process.StartTime.ToUniversalTime();
    string recorded = Text(runtime, "processStartedAt");
    if (recorded.Length > 0) { if (Utc(recorded) != start) return false; }
    else {
     double gap = (Utc(Text(runtime, "startedAt")) - start).TotalSeconds;
     if (gap < 0 || gap > 120) return false;
    }
    string identity = Identity(process);
    if (verifiedIdentity != identity) {
     using (var item = new ManagementObject("Win32_Process.Handle='" + pid + "'")) {
      string command = Convert.ToString(item["CommandLine"]);
      if (command.IndexOf("\"" + Path.Combine(app, "widget.ps1") + "\"", StringComparison.OrdinalIgnoreCase) < 0) return false;
     }
     verifiedIdentity = identity;
    }
    if (process.PrivateMemorySize64 > 320L * 1024 * 1024) {
     Block("Widget exceeded 320 MiB. Stopped to protect the computer. Use the launcher to resume.");
     process.Kill(); return false;
    }
    return true;
   }
  } catch { return false; }
 }
 static bool LaunchAllowed(DateTime now) {
  var saved = Read("supervisor-launches.json") as IEnumerable;
  if (File.Exists(FileAt("supervisor-launches.json")) && !(saved is object[])) {
   Block("Invalid restart history. Use the launcher to resume."); return false;
  }
  var recent = new List<DateTime>();
  if (saved != null) foreach (object item in saved) {
   DateTime time = Utc(Convert.ToString(item));
   if (time > now.AddMinutes(-10)) recent.Add(time);
  }
  if (recent.Count >= 3) {
   Block("Stopped after 3 launches within 10 minutes. Use the launcher to resume."); return false;
  }
  recent.Add(now); Write("supervisor-launches.json", recent.Select(x => x.ToString("o")).ToArray());
  return true;
 }
 static Process StartWidget() {
  var info = new ProcessStartInfo {
   FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32\\WindowsPowerShell\\v1.0\\powershell.exe"),
   Arguments = "-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + Path.Combine(app, "runtime\\start-widget.ps1") + "\" -WidgetPath \"" + Path.Combine(app, "widget.ps1") + "\"",
   WorkingDirectory = app, UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden
  };
  var process = Process.Start(info);
  try { verifiedIdentity = Identity(process); return process; }
  catch { process.Dispose(); throw; }
 }
 static void Run() {
  int pid; string started;
  using (var self = Process.GetCurrentProcess()) { pid = self.Id; started = self.StartTime.ToUniversalTime().ToString("o"); }
  bool owned = false;
  using (var mutex = new Mutex(false, "Local\\GPTNiangSupervisor-" + sid)) {
   try { owned = mutex.WaitOne(0); } catch (AbandonedMutexException) { owned = true; }
   if (!owned) return;
   Process pending = null;
   try {
    GptNiangResourceJob.Enter("Local\\GPTNiangResources-" + sid, 384UL * 1024 * 1024, 448UL * 1024 * 1024);
    DateTime nextLaunch = DateTime.MinValue, nextStatus = DateTime.MinValue;
    string previousHosts = "";
    while (!File.Exists(FileAt("supervisor-disabled.flag")) && !File.Exists(FileAt("supervisor-stop.flag"))) {
     try {
      var hosts = GptWidgetSupervisorNative.Hosts();
      var visible = hosts.Where(x => x.visible).OrderBy(x => x.handle).ToArray();
      var settings = Read("settings.json");
      bool desktop = Object.Equals(Value(settings, "followHost"), false);
      var pause = Read("supervisor-pause.json");
      bool paused = Paused(pause, hosts);
      if (pause != null && !paused) File.Delete(FileAt("supervisor-pause.json"));
      string hostKey = String.Join("|", visible.Select(x => x.handle + ":" + x.pid + ":" + x.started));
      if (hostKey != previousHosts) { previousHosts = hostKey; nextLaunch = DateTime.MinValue; }
      bool running = RunningWidget();
      if (pending != null && (running || pending.HasExited)) { pending.Dispose(); pending = null; }
      bool blocked = File.Exists(FileAt("resource-block.flag"));
      paused |= blocked;
      if (!paused && (desktop || visible.Length > 0) && !running && pending == null && DateTime.UtcNow >= nextLaunch) {
       nextLaunch = DateTime.UtcNow.AddSeconds(10);
       if (LaunchAllowed(DateTime.UtcNow)) pending = StartWidget();
       else { paused = true; blocked = true; }
      }
      if (DateTime.UtcNow >= nextStatus) {
       Write("supervisor-status.json", new {
        pid, processStartedAt = started, at = DateTime.UtcNow.ToString("o"),
        mainWindows = hosts.Length, visibleWindows = visible.Length, paused, widgetRunning = running,
        resourceBlocked = blocked, processLimitMiB = 384, totalLimitMiB = 448,
        taskName = "GPT Niang Usage - " + sid, implementation = "native-dotnet"
       });
       nextStatus = DateTime.UtcNow.AddSeconds(5);
      }
     } catch (Exception error) { System.IO.File.WriteAllText(FileAt("supervisor-error.txt"), error.Message, Utf8); }
     Thread.Sleep(1500);
    }
   } finally {
    if (pending != null) pending.Dispose();
    try { if (Number(Read("supervisor-status.json"), "pid") == pid) File.Delete(FileAt("supervisor-status.json")); } catch { }
    if (owned) mutex.ReleaseMutex();
   }
  }
 }
 static int SelfTest() {
  data = Path.Combine(Path.GetTempPath(), "gpt-native-supervisor-test-" + Guid.NewGuid().ToString("N"));
  Directory.CreateDirectory(data);
  try {
   var now = DateTime.UtcNow;
   if (!LaunchAllowed(now) || !LaunchAllowed(now.AddSeconds(1)) || !LaunchAllowed(now.AddSeconds(2)) || LaunchAllowed(now.AddSeconds(3))) throw new Exception("Restart budget failed");
   if (!File.Exists(FileAt("resource-block.flag")) || !LaunchAllowed(now.AddMinutes(11))) throw new Exception("Persistent restart block or expiration failed");
   System.IO.File.WriteAllText(FileAt("supervisor-launches.json"), "invalid");
   if (LaunchAllowed(now)) throw new Exception("Corrupt history allowed a restart");
   var host = new GptWidgetSupervisorHost { handle = 7, pid = 8, started = 9 };
   if (!Paused(Json.DeserializeObject("{\"desktop\":true}"), new GptWidgetSupervisorHost[0])) throw new Exception("Desktop pause failed");
   if (!Paused(Json.DeserializeObject("{\"host\":7,\"hostPid\":8,\"hostStarted\":9}"), new[] {host})) throw new Exception("Host pause failed");
   if (Paused(Json.DeserializeObject("{\"host\":7,\"hostPid\":99}"), new[] {host})) throw new Exception("Reused host pause matched");
   GptNiangResourceJob.Enter("Local\\GPTNiangNativeTest-" + Guid.NewGuid().ToString("N"), 384UL * 1024 * 1024, 448UL * 1024 * 1024);
   var limits = GptNiangResourceJob.Limits();
   if (limits[0] != 384UL * 1024 * 1024 || limits[1] != 448UL * 1024 * 1024) throw new Exception("Memory budget failed");
   Console.WriteLine("PASS: native restart budget, persisted block, expiry, host/desktop pause, identity and memory limits.");
   return 0;
  } finally {
   foreach (string file in Directory.GetFiles(data)) File.Delete(file);
   Directory.Delete(data);
  }
 }
 [STAThread] public static int Main(string[] args) {
  try {
   if (args.Length == 1 && args[0] == "--self-test") return SelfTest();
   if (args.Length != 2) throw new ArgumentException("Expected app and data directories.");
   app = Path.GetFullPath(args[0]).TrimEnd(Path.DirectorySeparatorChar);
   data = Path.GetFullPath(args[1]); Directory.CreateDirectory(data);
   using (var identity = WindowsIdentity.GetCurrent()) sid = identity.User.Value;
   Run(); return 0;
  } catch (Exception error) {
   if (data != null) try { System.IO.File.WriteAllText(FileAt("supervisor-error.txt"), error.ToString(), Utf8); } catch { }
   Console.Error.WriteLine(error.Message); return 1;
  }
 }
}
