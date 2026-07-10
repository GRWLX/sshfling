<!--- This template runs on a CFML server. It delegates to Node; it is not browser code. --->
<cfset bridgePath = getDirectoryFromPath(getCurrentTemplatePath()) & "bridge.cjs">
<cfexecute
  name="node"
  arguments='"#bridgePath#"'
  timeout="30"
  variable="bridgeOutput"
  errorVariable="bridgeError">
</cfexecute>

<cfif len(trim(bridgeError))>
  <cfthrow message="SSHFling Node bridge failed" detail="#bridgeError#">
</cfif>

<cfset result = deserializeJSON(bridgeOutput)>
<cfif result.runtime neq "node" or result.status neq 0 or not result.templatesAvailable>
  <cfthrow message="SSHFling Node bridge returned an invalid result">
</cfif>

<cfoutput>CFML server consumer verified the SSHFling Node API.</cfoutput>
