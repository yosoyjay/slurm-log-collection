## Notes on configuring OTel for Azure Monitor

These steps are a more focused version of those found in [Azure Learn - Ingest OpenTelemetry Protocol signals into Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/collect-use-observability-data).

This assumes that you have preexisting resources like Log Analytics Workspace and Azure Monitor that you want to reuse (Option 2 in above link).  If not, they can be created when creating the Application Insights (Option 1 in the above link).

Note the Resources IDs for the Log Analytics Workspace and Azure Monitor Workspace that you will reuse as these will be entered into a template in step 3 below.

1. Register for OTel feature:

```bash
az feature register --name OtlpApplicationInsights --namespace Microsoft.Insights
# Make sure feature is registered
az feature list -o table --query "[?contains(name, 'Microsoft.Insights/OtlpApplicationInsights')].{Name:name,State:properties.state}"
# Make sure sub is registered for Insights
az provider register -n Microsoft.Insights
```


2. Create Application Insights which helps configures connections between Log Analytics and Azure Monitor.

Create a new "Application Insights" resource in the portal.  If you already have a Log Analytics Workspace and Azure Monitor that will be used, ensure the "Enable OTLP support" is **unchecked** because this will create new resources of those types and specify the Log Analytics Workspace you want to use for "Workspace Details".

After deployment completes, navigate to the created Application Insights and note its Resource ID from the Overview page.

3. Deploy Data Collection Endpoint and Rule
 
- 3.A: In the Azure portal, search for "Deploy a custom template" and select it.
- 3.B: Select "Build your own template in the editor".
- 3.C: Copy the template content from the [Azure Monitor Community repository](https://github.com/microsoft/AzureMonitorCommunity/blob/master/Azure%20Services/Azure%20Monitor/OpenTelemetry/OTLP_DCE_DCR_ARM_Template.txt).
- 3.D: Paste the template into the editor and update the parameters with your workspace resource IDs and Application Insights resource ID.
  -> Set "parameters.location.defaultValue" to match your workspace region (e.g. 'centralus')
  -> Set "parameters.applicationInsightsResourceId.defaultValue" to Resource ID for Application Insights that was just created.
  -> Set "parameters.azureMonitorWorkspaceResourceID.defaultValue" to Resource ID for your Azure Monitor workspace
  -> Set "parameters.logAnalyticsWorkspaceResourceID.defaultValue" to Resource ID for your Log Analytics workspace
- 3.F: Review and create the deployment.

After deployment completes, navigate to the created Data Collection Rule and note its Resource ID from the Overview page.

4. Ensure the user assigned managed identity for VM and VMSS can write to Azure Monitor and Log Analytics (if none, create a new managed identity):
    - Log Analytics Contributor (logs) add to MI
    - Monitor Contributor (metrics)  add to MI
    
5. Install [Azure Monitor Agent to VM and VMSS](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-manage?tabs=azure-portal).

VM:
```bash
az vm extension set \
  --name AzureMonitorLinuxAgent \
  --publisher Microsoft.Azure.Monitor \
  --ids <vm-resource-id> \
  --enable-auto-upgrade true \
  --settings '{"authentication":{"managedIdentity":{"identifier-name":"mi_res_id","identifier-value":"/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<user-assigned-identity>"}}}'
```

VMSS:

Install the extension:

```bash
az vmss extension set \
  --name AzureMonitorLinuxAgent \
  --publisher Microsoft.Azure.Monitor \
  --vmss-name <vmss-name> \
  --resource-group <resource-group> \
  --enable-auto-upgrade true \
  --settings '{"authentication":{"managedIdentity":{"identifier-name":"mi_res_id","identifier-value":"/subscriptions/<my-subscription-id>/resourceGroups/<my-resource-group>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<my-user-assigned-identity>"}}}'
```

Update the VMSS instances so they actually get the extension:

```bash
az vmss update-instances \
  --resource-group <resource-group> \
  --name <vmss-name> \
  --instance-ids '*'
```

6. Associate DCR with VM and VMSS
- In Azure Portal find otlpDcr -> Configuration -> Resources.  Click "+ Add" and add VMs and VMSS that will have logs forwarded.


7. Verify Azure Monitor Agent is configured on VM and/or VMSS

After a few minutes, check on VM check that azuremonitoragent systemd service is working
```bash
sudo systemctl status azuremonitoragent
```

Check logs for Azure Monitor Agent to ensure it's configured for OTLP. You should see rows with 'OtlpTokenFetcher' in output.

```bash
sudo cat /var/opt/microsoft/azuremonitoragent/log/mdsd.info  | grep Otlp
```

8.  Required changes for config of otel_logging:

In addition to the import of the OTel GRPC (opentelemetry.exporter.otlp.proto.grpc._log_exporter.OTLPLogExporter)

```bash
$ cat .env
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4319
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
#OTEL_EXPORTER_OTLP_HEADERS: Authentication headers  # not required for this
APPLICATIONINSIGHTS_CONNECTION_STRING=microsoft.applicationId=<application-id-from-application-insight>
```

9.  Run test

```bash
$ python otel_logging.py
2025-12-17 00:40:20,538 - root - INFO - Azure Monitor Agent logging configured: test-service
2025-12-17 00:40:20,538 - root - INFO -    Agent Endpoint: http://localhost:4319
2025-12-17 00:40:20,538 - root - INFO -    Protocol: grpc
2025-12-17 00:40:20,538 - root - INFO -    Application ID: 94c0ec1d-f77f-41d4-a783-0647cae9b4aa
2025-12-17 00:40:20,538 - root - INFO -    Environment: dev
2025-12-17 00:40:20,539 - root - INFO - This is an info message
2025-12-17 00:40:20,539 - root - WARNING - This is a warning message
2025-12-17 00:40:20,539 - root - ERROR - This is an error message
2025-12-17 00:40:20,539 - __main__ - INFO - This is from a named logger
```
