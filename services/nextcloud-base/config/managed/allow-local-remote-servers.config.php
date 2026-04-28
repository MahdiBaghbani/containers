<?php
$mode = getenv('NEXTCLOUD_ALLOW_LOCAL_REMOTE_SERVERS_MODE');
$mode = $mode === false ? 'off' : strtolower(trim((string) $mode));

if ($mode === 'allow') {
  $CONFIG['allow_local_remote_servers'] = true;
} else {
  $CONFIG['allow_local_remote_servers'] = false;
}
