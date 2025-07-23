<?php
// Simple OpenVPN web GUI
// Usage: place this file on a PHP-enabled web server

// --- Configuration ---
$USERNAME = 'admin';
$PASSWORD = 'change_this_password';
$SCRIPT = __DIR__ . '/opvpn-setup.sh';
$CLIENT_DIR = '/root/clients';
$EASYRSA_DIR = '/root/openvpn-ca';
$CCD_DIR = '/etc/openvpn/ccd';
$IP_MAP_FILE = '/etc/openvpn/client_ips.txt';

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

// Helper: run shell command and capture output
function run_cmd($cmd) {
    $output = [];
    $ret = 0;
    exec($cmd . ' 2>&1', $output, $ret);
    return [implode("\n", $output), $ret === 0];
}

$message = '';

// Handle download
if (isset($_GET['download'])) {
    $name = preg_replace('/[^a-zA-Z0-9_-]/', '', $_GET['download']);
    $path = "$CLIENT_DIR/$name.ovpn";
    if (is_file($path)) {
        header('Content-Type: application/x-openvpn-profile');
        header('Content-Disposition: attachment; filename="' . $name . '.ovpn"');
        readfile($path);
        exit;
    } else {
        $message = 'File not found';
    }
}

// Handle actions
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Create new client
    if (isset($_POST['create'])) {
        $name = preg_replace('/[^a-zA-Z0-9_-]/', '', $_POST['name']);
        $proto = ($_POST['proto'] === 'tcp') ? 'tcp' : 'udp';
        if ($name) {
            $cmd = "source $SCRIPT && load_existing_config && create_client_config '$name' '$proto' \$RANDOM_PORT";
            list($out, $ok) = run_cmd('bash -c ' . escapeshellarg($cmd));
            $message = $out;
        }
    }
    // Remove client
    if (isset($_POST['delete'])) {
        $name = preg_replace('/[^a-zA-Z0-9_-]/', '', $_POST['delete']);
        if ($name) {
            $cmd = "rm -f $EASYRSA_DIR/pki/issued/{$name}.crt $EASYRSA_DIR/pki/private/{$name}.key \"$EASYRSA_DIR/pki/reqs/{$name}.req\" $CLIENT_DIR/{$name}.ovpn $CCD_DIR/{$name} && sed -i '/^$name /d' $IP_MAP_FILE";
            list($out, $ok) = run_cmd('bash -c ' . escapeshellarg($cmd));
            $message = $out;
        }
    }
}

$clients = list_clients($CLIENT_DIR);
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
<?php if($message) echo '<pre>'.htmlspecialchars($message).'</pre>'; ?>
<h2>Create Client</h2>
<form method="post">
<label>Name: <input type="text" name="name" required></label>
<label>Protocol:
<select name="proto">
<option value="udp">UDP</option>
<option value="tcp">TCP</option>
</select>
</label>
<button class="btn-primary" type="submit" name="create">Create</button>
</form>
<h2>Existing Clients</h2>
<table class="table">
<tr><th>Client</th><th>Actions</th></tr>
<?php foreach($clients as $c): ?>
<tr>
<td><?php echo htmlspecialchars($c); ?></td>
<td>
<a class="btn-primary" href="?download=<?php echo urlencode($c); ?>">Download</a>
<form method="post" style="display:inline">
<input type="hidden" name="delete" value="<?php echo htmlspecialchars($c); ?>">
<button class="btn-danger" type="submit">Delete</button>
</form>
</td>
</tr>
<?php endforeach; ?>
</table>
</div>
</body>
</html>
