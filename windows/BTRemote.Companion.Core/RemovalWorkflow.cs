namespace BTRemote.Companion.Core;

public interface IRemovalSteps
{
    Task Stop();
    Task UnpairSelectedMac();
    Task Unregister();
    Task FinishFiles();
}

public static class RemovalWorkflow
{
    // Keep selection/retry state until unpairing succeeds. Never claim success
    // or delete the executable if an earlier cleanup step failed.
    public static async Task Run(IRemovalSteps steps)
    {
        await steps.Stop();
        await steps.UnpairSelectedMac();
        await steps.Unregister();
        await steps.FinishFiles();
    }
}
