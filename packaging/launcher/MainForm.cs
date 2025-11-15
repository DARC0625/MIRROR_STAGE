using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace MirrorStageLauncher;

public class MainForm : Form
{
    private readonly HttpClient _httpClient = new();
    private readonly TextBox _logBox;
    private readonly Button _installButton;
    private readonly Label _statusLabel;
    private bool _isInstalling;

    private string InstallRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MIRROR_STAGE");
    private string LogsDirectory => Path.Combine(InstallRoot, "logs");

    public MainForm()
    {
        Text = "MIRROR STAGE Launcher";
        MinimumSize = new System.Drawing.Size(720, 520);
        StartPosition = FormStartPosition.CenterScreen;

        var description = new Label
        {
            Text = "MIRROR STAGE 설치/업데이트 도구입니다. 아래 버튼을 눌러 설치를 시작하세요.",
            Dock = DockStyle.Top,
            Height = 40,
            TextAlign = System.Drawing.ContentAlignment.MiddleLeft
        };

        _statusLabel = new Label
        {
            Text = InstallationStateText(),
            Dock = DockStyle.Top,
            Height = 30,
            ForeColor = System.Drawing.Color.SteelBlue,
            TextAlign = System.Drawing.ContentAlignment.MiddleLeft
        };

        _logBox = new TextBox
        {
            Multiline = true,
            ReadOnly = true,
            ScrollBars = ScrollBars.Vertical,
            Dock = DockStyle.Fill,
            BackColor = System.Drawing.Color.FromArgb(20, 20, 20),
            ForeColor = System.Drawing.Color.FromArgb(205, 210, 214),
            Font = new System.Drawing.Font("Consolas", 9)
        };

        _installButton = new Button
        {
            Text = "설치 시작",
            Width = 140,
            Height = 36,
            BackColor = System.Drawing.Color.FromArgb(0, 122, 204),
            ForeColor = System.Drawing.Color.White,
            FlatStyle = FlatStyle.Flat
        };
        _installButton.Click += async (_, _) => await RunInstallationAsync();

        var openInstallLink = new LinkLabel
        {
            Text = "설치 폴더 열기",
            AutoSize = true,
            LinkColor = System.Drawing.Color.CornflowerBlue
        };
        openInstallLink.LinkClicked += (_, _) => OpenInstallFolder();

        var openLogLink = new LinkLabel
        {
            Text = "로그 보기",
            AutoSize = true,
            LinkColor = System.Drawing.Color.CornflowerBlue
        };
        openLogLink.LinkClicked += (_, _) => OpenLatestLog();

        var bottomPanel = new FlowLayoutPanel
        {
            Dock = DockStyle.Bottom,
            Height = 48,
            FlowDirection = FlowDirection.LeftToRight
        };
        bottomPanel.Controls.Add(_installButton);
        bottomPanel.Controls.Add(openInstallLink);
        bottomPanel.Controls.Add(openLogLink);

        Controls.Add(_logBox);
        Controls.Add(bottomPanel);
        Controls.Add(_statusLabel);
        Controls.Add(description);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _httpClient.Dispose();
        }
        base.Dispose(disposing);
    }

    private string InstallationStateText()
    {
        return Directory.Exists(InstallRoot)
            ? "상태: 설치됨"
            : "상태: 미설치";
    }

    private void AppendLog(string line)
    {
        if (InvokeRequired)
        {
            BeginInvoke(new Action<string>(AppendLog), line);
            return;
        }
        var builder = new StringBuilder();
        builder.Append('[').Append(DateTime.Now.ToString("HH:mm:ss")).Append("] ").Append(line);
        _logBox.AppendText(builder.ToString() + Environment.NewLine);
    }

    private async Task RunInstallationAsync()
    {
        if (_isInstalling)
        {
            return;
        }

        _isInstalling = true;
        _installButton.Enabled = false;
        AppendLog("설치 스크립트를 다운로드하는 중...");

        try
        {
            var tempDir = Path.Combine(Path.GetTempPath(), "MirrorStageLauncher");
            Directory.CreateDirectory(tempDir);
            var scriptPath = Path.Combine(tempDir, "install-mirror-stage-ego.ps1");
            await DownloadInstallerAsync(scriptPath);

            AppendLog("PowerShell 설치 스크립트를 실행합니다...");
            var exitCode = await ExecuteInstallerAsync(scriptPath);
            AppendLog($"설치 스크립트 종료 코드: {exitCode}");

            if (exitCode == 0)
            {
                _statusLabel.Text = InstallationStateText();
                MessageBox.Show(this, "MIRROR STAGE 설치가 완료되었습니다.", "설치 완료", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            else
            {
                MessageBox.Show(this, "설치 과정에서 오류가 발생했습니다. 로그를 확인하세요.", "설치 실패", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
        catch (Exception ex)
        {
            AppendLog($"오류: {ex.Message}");
            MessageBox.Show(this, ex.Message, "실패", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            _installButton.Enabled = true;
            _isInstalling = false;
        }
    }

    private async Task DownloadInstallerAsync(string destinationPath)
    {
        var scriptUrl = "https://raw.githubusercontent.com/DARC0625/MIRROR_STAGE/main/packaging/install-mirror-stage-ego.ps1";
        using var response = await _httpClient.GetAsync(scriptUrl);
        response.EnsureSuccessStatusCode();
        await using var fs = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.None);
        await response.Content.CopyToAsync(fs);
    }

    private Task<int> ExecuteInstallerAsync(string scriptPath)
    {
        var tcs = new TaskCompletionSource<int>();
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\" -InstallRoot \"{InstallRoot}\"",
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = Path.GetDirectoryName(scriptPath) ?? Environment.CurrentDirectory
        };

        var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        process.OutputDataReceived += (_, e) => { if (!string.IsNullOrEmpty(e.Data)) AppendLog(e.Data); };
        process.ErrorDataReceived += (_, e) => { if (!string.IsNullOrEmpty(e.Data)) AppendLog(e.Data); };
        process.Exited += (_, _) =>
        {
            tcs.TrySetResult(process.ExitCode);
            process.Dispose();
        };

        if (!process.Start())
        {
            throw new InvalidOperationException("PowerShell 프로세스를 시작할 수 없습니다.");
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        return tcs.Task;
    }

    private void OpenInstallFolder()
    {
        if (!Directory.Exists(InstallRoot))
        {
            MessageBox.Show(this, "아직 설치되지 않았습니다.", "경고", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        Process.Start("explorer.exe", InstallRoot);
    }

    private void OpenLatestLog()
    {
        if (!Directory.Exists(LogsDirectory))
        {
            MessageBox.Show(this, "로그 폴더가 없습니다.", "정보", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        var dir = new DirectoryInfo(LogsDirectory);
        var log = dir.GetFiles("*.log").OrderByDescending(f => f.LastWriteTimeUtc).FirstOrDefault();
        if (log == null)
        {
            MessageBox.Show(this, "로그 파일을 찾을 수 없습니다.", "정보", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        Process.Start(new ProcessStartInfo
        {
            FileName = log.FullName,
            UseShellExecute = true
        });
    }
}
