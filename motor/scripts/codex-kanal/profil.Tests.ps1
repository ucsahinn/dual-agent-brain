$repo=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
. (Join-Path $repo 'motor/hooks/lib.ps1');. (Join-Path $PSScriptRoot 'core.ps1')
Describe 'Role MCP diet and brief budget' {
 It 'reads model and review_model without changing config or reading nested model overrides' {
  $ctx=New-KanalContext $repo;$ctx.ConfigPath=Join-Path $TestDrive 'models.toml'
  "model = 'unsupported-model'`nreview_model = 'review-model'`n[profiles.other]`nmodel = 'unrelated-model'"|Set-Content -Encoding UTF8 $ctx.ConfigPath
  $before=(Get-FileHash $ctx.ConfigPath).Hash;$profile=Get-KanalModelProfile $ctx
  $profile.Model|Should Be 'unsupported-model';$profile.ReviewModel|Should Be 'review-model'
  (Get-FileHash $ctx.ConfigPath).Hash|Should Be $before
 }
 It 'accounts for mandatory catalog policy separately without truncating it' {
  $ctx=New-KanalContext $repo;$role='r'*22084;$brief=New-KanalBrief 'task' 'C:/fixture'
  $compiled=New-KanalCompiledPrompt $ctx $role $brief
  $compiled.Text.StartsWith($role)|Should Be $true
  $compiled.MandatoryRoleCharacters|Should Be 22084
  $compiled.Characters -le $compiled.CharacterBudget|Should Be $true
  {New-KanalCompiledPrompt $ctx $role (New-KanalBrief ('x'*12001) 'C:/fixture')}|Should Throw
 }
 It 'writes only known server enable flags, preserves config and excludes plugin transports' {
  $ctx=New-KanalContext $repo;$ctx.ConfigPath=Join-Path $TestDrive 'config.toml';$ctx.State=$TestDrive
  "[mcp_servers.node_repl]`ncommand='fixture'`n[mcp_servers.serena]`ncommand='fixture'`n[mcp_servers.serena.tools.find_symbol]`nenabled=true`n[mcp_servers.context7]`ncommand='fixture'`n[mcp_servers.database]`ncommand='fixture'"|Set-Content -Encoding UTF8 $ctx.ConfigPath
  $before=(Get-FileHash $ctx.ConfigPath).Hash
  $profile=New-KanalMcpProfile $ctx 'code-mapper' (Join-Path $TestDrive 'profile')
  $profile.Enabled -contains 'serena'|Should Be $true
  $profile.Disabled -contains 'node_repl'|Should Be $true
  $profile.Disabled -contains 'database'|Should Be $true
  (Get-Content -Raw $profile.Path)|Should Not Match 'cua_repl|command='
  (Get-FileHash $ctx.ConfigPath).Hash|Should Be $before
 }
 It 'keeps all mandatory brief fields and drops oversized optional memory first' {
  $ctx=New-KanalContext $repo;$ctx.BriefBudget=2000;$ctx.MemoryCandidates=@(@{path='approved.md';text=('x'*5000);score=1})
  $text=New-KanalCompiledPrompt $ctx '' (New-KanalBrief 'first' 'C:/fixture')
  (Test-KanalBrief $text.Text)|Should Be $true
  $text.Text.Length -le 2000|Should Be $true
  $text.Injected.Count|Should Be 0
 }
 It 'fails closed on an unparsed quoted MCP server table' {
  $ctx=New-KanalContext $repo;$ctx.ConfigPath=Join-Path $TestDrive 'quoted.toml'
  '[mcp_servers."team.tools"]'|Set-Content -Encoding UTF8 $ctx.ConfigPath
  {New-KanalMcpProfile $ctx 'code-mapper' (Join-Path $TestDrive 'quoted-profile')}|Should Throw 'Unrecognized MCP table'
 }
}
