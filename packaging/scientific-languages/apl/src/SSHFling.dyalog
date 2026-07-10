:Namespace SSHFling
    ⎕IO←1

    ∇ value←ConfiguredOr(name fallback);configured
      configured←System.Environment.GetEnvironmentVariable name
      :If 0=≢configured
          value←fallback
      :Else
          value←configured
      :EndIf
    ∇

    ∇ path←RuntimePath;root
      root←ConfiguredOr 'SSHFLING_PACKAGE_ROOT' '.'
      path←ConfiguredOr 'SSHFLING_RUNTIME' (root,'/runtime/sshfling.py')
    ∇

    ∇ path←TemplateDirectory;root
      root←ConfiguredOr 'SSHFLING_PACKAGE_ROOT' '.'
      path←ConfiguredOr 'SSHFLING_TEMPLATE_DIR' (root,'/runtime/templates')
    ∇

    ∇ status←Run args;info;process;argument
      :Access Public Shared
      ⎕USING←'System' 'System.Diagnostics'
      info←ProcessStartInfo
      info.FileName←ConfiguredOr 'SSHFLING_PYTHON' 'python3'
      info.UseShellExecute←0
      info.ArgumentList.Add RuntimePath
      :For argument :In args
          info.ArgumentList.Add argument
      :EndFor
      info.Environment['SSHFLING_TEMPLATE_DIR']←TemplateDirectory
      info.Environment['PYTHONUNBUFFERED']←'1'
      :Trap 0
          process←Process.Start info
          process.WaitForExit
          status←process.ExitCode
          process.Dispose
      :Else
          status←127
      :EndTrap
    ∇
:EndNamespace
