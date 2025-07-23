<?php
// Simple OpenVPN web GUI
// Usage: place this file on a PHP-enabled web server

// --- Configuration ---
$USERNAME   = 'admin';
$PASSWORD   = '123';
$CLIENT_DIR = '/root/clients';
$EASYRSA_DIR = '/root/openvpn-ca';
$IP_MAP_FILE = '/etc/openvpn/client_ips.txt';
$UDP_STATUS = '/var/log/openvpn-udp-status.log';
$TCP_STATUS = '/var/log/openvpn-tcp-status.log';

// --- Basic Authentication ---
if (!isset($_SERVER['PHP_AUTH_USER']) ||
    $_SERVER['PHP_AUTH_USER'] !== $USERNAME ||
    $_SERVER['PHP_AUTH_PW'] !== $PASSWORD) {
    header('WWW-Authenticate: Basic realm="OpenVPN GUI"');
    header('HTTP/1.0 401 Unauthorized');
    echo 'Unauthorized';
    exit;
}

// Helper: list existing clients
function list_clients($dir) {
    $clients = [];
    if (is_dir($dir)) {
        foreach (glob($dir . '/*.ovpn') as $file) {
            $clients[] = basename($file, '.ovpn');
        }
    }
    sort($clients);
    return $clients;
}

// Parse OpenVPN status file and return array of client info
function parse_status($file) {
    $info = [];
    if (!is_file($file)) {
        return $info;
    }
    foreach (file($file) as $line) {
        if (strpos($line, 'CLIENT_LIST,') === 0) {
            $parts = explode(',', trim($line));
            $info[$parts[1]] = [
                'real' => $parts[2],
                'since' => $parts[5]
            ];
        } elseif (strpos($line, 'ROUTING_TABLE,') === 0) {
            $parts = explode(',', trim($line));
            $client = $parts[3];
            if (isset($info[$client])) {
                $info[$client]['virtual'] = $parts[1];
            }
        }
    }
    return $info;
}

// Handle download
if (isset($_GET['download'])) {
    $name = preg_replace('/[^a-zA-Z0-9_-]/', '', $_GET['download']);
    $path = "$CLIENT_DIR/$name.ovpn";
    if (is_file($path)) {
        header('Content-Type: application/x-openvpn-profile');
        header('Content-Disposition: attachment; filename="' . $name . '.ovpn"');
        readfile($path);
        exit;
    }
}

// No write actions - read only GUI

$clients = list_clients($CLIENT_DIR);
$status = array_merge(parse_status($UDP_STATUS), parse_status($TCP_STATUS));
?>
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>OpenVPN Web GUI</title>
<style>
body {font-family: Arial, sans-serif; background:#f5f5f5; margin:40px;}
.container{background:#fff;padding:20px;border-radius:8px;max-width:800px;margin:auto;box-shadow:0 0 10px rgba(0,0,0,0.1);} 
button{padding:6px 12px;border:none;border-radius:4px;cursor:pointer;} 
.btn-danger{background:#dc3545;color:#fff;} 
.btn-primary{background:#007bff;color:#fff;} 
.table{width:100%;border-collapse:collapse;margin-top:10px;} 
.table th,.table td{padding:8px;border-bottom:1px solid #ddd;text-align:left;} 
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
<td><?php echo htmlspecialchars($c); ?></td>
<td><a class="btn-primary" href="?download=<?php echo urlencode($c); ?>">Download</a></td>
</tr>
<?php endforeach; ?>
</table>
<h2>Connected Clients</h2>
<table class="table">
<tr><th>Client</th><th>Virtual IP</th><th>Real IP</th><th>Since</th></tr>
<?php foreach($status as $name => $info): ?>
<tr>
<td><?php echo htmlspecialchars($name); ?></td>
<td><?php echo htmlspecialchars($info['virtual'] ?? ''); ?></td>
<td><?php echo htmlspecialchars($info['real']); ?></td>
<td><?php echo htmlspecialchars($info['since']); ?></td>
</tr>
<?php endforeach; ?>
</table>
</div>
</body>
</html>
