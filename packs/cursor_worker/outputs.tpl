[[- /* Rendered after a successful nomad-pack run. */ -]]
Deployed [[ template "job_id" . ]] ([[ var "count" . ]] allocation[[ if gt (int (var "count" .)) 1 ]]s[[ end ]], driver [[ var "driver" . ]]).

Store a Cursor API key before the worker can connect. My Machines needs a
personal user API key (Cursor Dashboard → API Keys). A pool worker needs a
service account key. The pack never contains the key.

  nomad var put -force [[ template "api_key_path" . ]] [[ var "api_key_key" . ]]=<user-api-key>

Run that same command again to rotate the key. The variable is read in the
job's namespace. Create it before the worker task starts, or the task waits
on the template.

Logs take an allocation id and a task name. Do not pass -job.

  nomad job status [[ template "job_id" . ]]
  nomad alloc status <alloc-id>
  nomad alloc logs <alloc-id> install-cli
  nomad alloc logs <alloc-id> worker
