<?hh

<<__EntryPoint>>
function main(): void {
  // HHVM launches this bridge on the server; no browser runtime is involved.
  $configured_node = \getenv('NODE');
  $node = $configured_node === false || $configured_node === ''
    ? 'node'
    : $configured_node;
  $bridge = __DIR__.'/../bridge.cjs';
  $command = \escapeshellarg($node).' '.\escapeshellarg($bridge);
  $output = \shell_exec($command);

  if ($output === null ||
      \strpos($output, '"runtime":"node"') === false ||
      \strpos($output, '"status":0') === false ||
      \strpos($output, '"templatesAvailable":true') === false) {
    throw new \RuntimeException('SSHFling Node bridge returned an invalid result.');
  }

  \printf("Hack server consumer verified the SSHFling Node API.\n");
}
