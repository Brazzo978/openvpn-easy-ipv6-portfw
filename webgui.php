<?php
// Simple OpenVPN web GUI
// Usage: place this file on a PHP-enabled web server

// --- Configuration ---
$USERNAME    = 'admin';
$PASSWORD    = '123';
$CLIENT_DIR  = '/root/clients';
$UDP_STATUS  = '/var/log/openvpn-udp-status.log';
$TCP_STATUS  = '/var/log/openvpn-tcp-status.log';

// --- Basic Authentication ---
if (!isset($_SERVER['PHP_AUTH_USER']) ||
    $_SERVER['PHP_AUTH_USER'] !== $USERNAME ||
    $_SERVER['PHP_AUTH_PW']   !== $PASSWORD) {
    header('WWW-Authenticate: Basic realm="OpenVPN GUI"');
    header('HTTP/1.0 401 Unauthorized');
    echo 'Unauthorized';
    exit;
}

// lista profili esistenti
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

// formatta byte in GB
function bytes_to_gb($bytes, $dec = 2) {
    return number_format($bytes / (1024**3), $dec) . ' GB';
}

// legge e unisce status UDP+TCP
function get_all_clients_status(array $files) {
    $info = [];
    foreach ($files as $file) {
        if (!is_readable($file)) continue;
        foreach (file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
            $p = explode(',', trim($line));
            if ($p[0] === 'CLIENT_LIST') {
                // 1=CN,2=Real,3=Virt,5=In,6=Out,7=Since(str)
                $cn  = $p[1];
                $rec = [
                    'real'    => $p[2],
                    'virtual' => $p[3],
                    'since'   => $p[7],
                    'traffic' => (int)$p[5] + (int)$p[6],
                ];
                // tieni la sessione più recente
                if (!isset($info[$cn]) || strtotime($rec['since']) > strtotime($info[$cn]['since'])) {
                    $info[$cn] = $rec;
                }
            }
            elseif ($p[0] === 'ROUTING_TABLE') {
                // 1=Virt,2=CN
                $cn = $p[2];
                if (isset($info[$cn])) {
                    $info[$cn]['virtual'] = $p[1];
                }
            }
        }
    }
    return $info;
}

// download profilo
if (isset($_GET['download'])) {
    $n = preg_replace('/[^a-zA-Z0-9_-]/','', $_GET['download']);
    $f = "$CLIENT_DIR/$n.ovpn";
    if (is_file($f)) {
        header('Content-Type: application/x-openvpn-profile');
        header("Content-Disposition: attachment; filename=\"$n.ovpn\"");
        readfile($f);
        exit;
    }
}

// main
$clients = list_clients($CLIENT_DIR);
$status  = get_all_clients_status([$UDP_STATUS, $TCP_STATUS]);
?>
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>OpenVPN Web GUI</title>
<style>
body{font-family:Arial,sans-serif;background:#f5f5f5;margin:40px}
.container{max-width:800px;margin:auto;background:#fff;padding:20px;border-radius:8px;box-shadow:0 0 10px rgba(0,0,0,0.1)}
button{padding:6px 12px;border:none;border-radius:4px;cursor:pointer}
.btn-primary{background:#007bff;color:#fff}
.table{width:100%;border-collapse:collapse;margin-top:10px}
.table th,.table td{padding:8px;border-bottom:1px solid #ddd;text-align:left}
</style>
</head>
<body>
<div class="container">
  <h1>OpenVPN Web GUI</h1>

  <h2>Available Profiles</h2>
  <table class="table">
    <tr><th>Client</th><th>Download</th></tr>
    <?php foreach($clients as $c): ?>
      <tr>
        <td><?=htmlspecialchars($c)?></td>
        <td><a class="btn-primary" href="?download=<?=urlencode($c)?>">Download</a></td>
      </tr>
    <?php endforeach; ?>
  </table>

  <h2>Connected Clients</h2>
  <table class="table">
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
</body>
</html>
