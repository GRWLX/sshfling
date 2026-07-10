args = argv();
if ~isempty(args) && strcmp(args{1}, '--')
    args = args(2:end);
end
status = sshfling.run(args);
exit(status);
