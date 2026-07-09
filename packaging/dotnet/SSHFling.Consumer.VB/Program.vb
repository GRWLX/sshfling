Imports System
Imports System.Linq
Imports SSHFling

Module Program
    Function Main(args As String()) As Integer
        If args.Length < 1 Then
            Console.Error.WriteLine("expected package version argument")
            Return 2
        End If

        Dim expectedVersion = args(0)
        If Not String.Equals(SSHFlingRunner.Version, expectedVersion, StringComparison.Ordinal) Then
            Console.Error.WriteLine($"library version mismatch: {SSHFlingRunner.Version} != {expectedVersion}")
            Return 1
        End If

        Return SSHFlingRunner.Run(args.Skip(1))
    End Function
End Module
