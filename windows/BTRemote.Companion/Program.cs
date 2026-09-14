using System.ServiceProcess;

namespace BTRemote.Companion;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args is ["--service"])
        {
            ServiceBase.Run(new CompanionService());
            return 0;
        }

        // a dedicated STA with a message loop satisfies WinRT's UI-thread contract.
        // it runs under the service identity/session, with no interactive windows.
        ApplicationConfiguration.Initialize();
        if (args is ["--ble-worker"])
        {
            using var worker = new BluetoothWorker();
            Application.Run(worker);
            return worker.ExitCode;
        }

        try
        {
            if (args.Length > 0) return ServiceCommands.Execute(args);
            using var singleInstance = new Mutex(true, "Local\\BTRemoteCompanionTray", out var created);
            if (!created) return 0;
            using var tray = new TrayContext();
            Application.Run(tray);
            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "BTRemote Companion", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
