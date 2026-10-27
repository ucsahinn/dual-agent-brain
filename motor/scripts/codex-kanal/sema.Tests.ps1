. (Join-Path $PSScriptRoot 'sema.ps1')
Describe 'Read-only schema drift gate' {
 It 'warns for missing schemas and a changed installed version without invoking a CLI' {
  $ctx=@{State=$TestDrive};$pin=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'schema-lock.json'))|ConvertFrom-Json
  $missing=Get-KanalSchemaStatus $ctx $pin.version;$missing.Generated|Should Be $false;$missing.Changed|Should Be $false
  $dir=Join-Path $TestDrive ('schemas/'+$pin.version);New-Item -ItemType Directory -Force $dir|Out-Null
  $schema=Join-Path $dir 'fixture.json';'{"fixture":true}'|Set-Content $schema
  @{version=$pin.version;files=@(@{path=$schema;sha256=(Get-FileHash $schema).Hash})}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $dir 'version.json')
  (Get-KanalSchemaStatus $ctx $pin.version).Generated|Should Be $true
  '{"fixture":false}'|Set-Content $schema
  (Get-KanalSchemaStatus $ctx $pin.version).Generated|Should Be $false
  (Get-KanalSchemaStatus $ctx '999.0.0').Changed|Should Be $true
 }
}
