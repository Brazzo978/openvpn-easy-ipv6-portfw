<?php
// Simple OpenVPN web GUI with auto-refresh and Material Design style

// --- Configuration ---
$USERNAME    = 'admin';
$PASSWORD    = '123';
$CLIENT_DIR  = '/root/clients';
$UDP_STATUS  = '/var/log/openvpn-udp-status.log';
$TCP_STATUS  = '/var/log/openvpn-tcp-status.log';

// Auto-refresh interval in seconds
$REFRESH_INTERVAL = 10;

// --- Basic Authentication ---
if (!isset($_SERVER['PHP_AUTH_USER']) ||
    $_SERVER['PHP_AUTH_USER'] !== $USERNAME ||
    $_SERVER['PHP_AUTH_PW']   !== $PASSWORD) {
    header('WWW-Authenticate: Basic realm="OpenVPN GUI"');
    header('HTTP/1.0 401 Unauthorized');
    echo 'Unauthorized';
    exit;
}

// Helper: list profiles
define('CLIENT_DIR', $CLIENT_DIR);
function list_clients($dir) {
    $c = [];
    if (is_dir($dir)) {
        foreach (glob("$dir/*.ovpn") as $f) {
            $c[] = basename($f, '.ovpn');
        }
    }
    sort($c);
    return $c;
}

// format bytes to GB
function bytes_to_gb($bytes, $dec = 2) {
    return number_format($bytes / (1024**3), $dec) . ' GB';
}

// parse status logs
function get_all_clients_status(array $files) {
    $info = [];
    foreach ($files as $file) {
        if (!is_readable($file)) continue;
        foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
            $p = explode(',', trim($line));
            if ($p[0] === 'CLIENT_LIST') {
                $cn = $p[1];
                $rec = [
                    'real'    => $p[2],
                    'virtual' => $p[3],
                    'since'   => $p[7],
                    'traffic' => (int)$p[5] + (int)$p[6],
                ];
                if (!isset($info[$cn]) || strtotime($rec['since']) > strtotime($info[$cn]['since'])) {
                    $info[$cn] = $rec;
                }
            } elseif ($p[0] === 'ROUTING_TABLE') {
                $cn = $p[2];
                if (isset($info[$cn])) {
                    $info[$cn]['virtual'] = $p[1];
                }
            }
        }
    }
    return $info;
}

// handle download
if (isset($_GET['download'])) {
    $n = preg_replace('/[^a-zA-Z0-9_-]/','', $_GET['download']);
    $f = CLIENT_DIR . "/$n.ovpn";
    if (is_file($f)) {
        header('Content-Type: application/x-openvpn-profile');
        header("Content-Disposition: attachment; filename=\"$n.ovpn\"");
        readfile($f);
        exit;
    }
}

// main
$clients = list_clients(CLIENT_DIR);
$status  = get_all_clients_status([$UDP_STATUS, $TCP_STATUS]);
?><!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>OpenVPN GUI</title>
    <meta http-equiv="refresh" content="<?= $REFRESH_INTERVAL ?>">
    <!-- Google Fonts -->
    <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">
    <style>
      :root {
        --primary: #6200ea;
        --primary-light: #9d46ff;
        --surface: #ffffff;
        --on-surface: #000000;
        --background: #f5f5f5;
      }
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body { font-family: 'Roboto', sans-serif; background: var(--background); color: var(--on-surface); padding: 20px; }
      .container { max-width: 1000px; margin: auto; }
      .card { background: var(--surface); border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); padding: 24px; margin-bottom: 20px; }
      h1 { font-size: 2rem; margin-bottom: 16px; color: var(--primary); }
      table { width: 100%; border-collapse: collapse; margin-top: 12px; }
      th, td { text-align: left; padding: 12px; }
      th { background: var(--primary-light); color: #fff; font-weight: 500; }
      tr:nth-child(even) td { background: #f9f9f9; }
      a.btn { text-decoration: none; padding: 8px 16px; border-radius: 4px; font-weight: 500; }
      .btn-download { background: var(--primary); color: #fff; }
    </style>
</head>
<body>
  <div class="container">
    <h1>OpenVPN Web GUI</h1>

    <div class="card">
      <h2>Available Profiles</h2>
      <table>
        <tr><th>Client</th><th>Download</th></tr>
        <?php foreach($clients as $c): ?>
        <tr>
          <td><?=htmlspecialchars($c)?></td>
          <td><a class="btn btn-download" href="?download=<?=urlencode($c)?>">Download</a></td>
        </tr>
        <?php endforeach; ?>
      </table>
    </div>

    <div class="card">
      <h2>Connected Clients</h2>
      <table>
        <tr>
          <th>Client</th><th>Virtual IP</th><th>Real IP</th><th>Since</th><th>Traffico</th>
        </tr>
        <?php foreach($status as $name => $i): ?>
        <tr>
          <td><?=htmlspecialchars($name)?></td>
          <td><?=htmlspecialchars($i['virtual'])?></td>
          <td><?=htmlspecialchars($i['real'])?></td>
          <td><?=htmlspecialchars($i['since'])?></td>
          <td><?=bytes_to_gb($i['traffic'])?></td>
        </tr>
        <?php endforeach; ?>
      </table>
    </div>

    <div style="text-align:center;color:gray;font-size:0.9rem;">
      Auto-refresh ogni <?= $REFRESH_INTERVAL ?> secondi
    </div>
  </div>
</body>
</html>
