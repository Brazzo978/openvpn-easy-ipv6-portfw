<?php
session_start();
// Simple OpenVPN web GUI with custom login and theme toggles

// --- Configuration ---
$USERNAME    = 'admin';
$PASSWORD    = '123';
$CLIENT_DIR  = '/root/clients';
$UDP_STATUS  = '/var/log/openvpn-udp-status.log';
$TCP_STATUS  = '/var/log/openvpn-tcp-status.log';
$REFRESH_INTERVAL = 10;

// Handle logout
if (isset($_GET['logout'])) {
    session_destroy();
    header('Location: ' . basename(__FILE__));
    exit;
}

// Handle login submission
if (!isset($_SESSION['loggedin'])) {
    if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['user'], $_POST['pass'])) {
        if ($_POST['user'] === $USERNAME && $_POST['pass'] === $PASSWORD) {
            $_SESSION['loggedin'] = true;
            header('Location: ' . basename(__FILE__));
            exit;
        } else {
            $loginError = 'Credenziali errate';
        }
    }
}

// If not authenticated, show login page
if (!isset($_SESSION['loggedin'])):
?><!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Login - OpenVPN GUI</title>
  <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    body { font-family:'Roboto',sans-serif; background:#fafafa; display:flex; align-items:center; justify-content:center; height:100vh; }
    .login-card { background:#fff; padding:24px; border-radius:8px; box-shadow:0 2px 8px rgba(0,0,0,0.1); width:300px; }
    h2 { margin-bottom:16px; color:#6200ea; }
    label { display:block; margin-bottom:8px; font-weight:500; }
    input { width:100%; padding:8px; margin-bottom:16px; border:1px solid #ccc; border-radius:4px; }
    .btn { width:100%; padding:10px; background:#6200ea; color:#fff; border:none; border-radius:4px; cursor:pointer; font-weight:500; }
    .error { color:#d32f2f; margin-bottom:16px; }
  </style>
</head>
<body>
  <div class="login-card">
    <h2>OpenVPN GUI Login</h2>
    <?php if (!empty($loginError)): ?><div class="error"><?=htmlspecialchars($loginError)?></div><?php endif; ?>
    <form method="post">
      <label for="user">Username</label>
      <input type="text" name="user" id="user" required autofocus>
      <label for="pass">Password</label>
      <input type="password" name="pass" id="pass" required>
      <button type="submit" class="btn">Accedi</button>
    </form>
  </div>
</body>
</html>
<?php
exit;
endif;

// format bytes to GB
function bytes_to_gb($bytes, $dec = 2) {
    return number_format($bytes / (1024**3), $dec) . ' GB';
}

// list profiles
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

// parse logs
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

$clients = list_clients(CLIENT_DIR);
$status  = get_all_clients_status([$UDP_STATUS, $TCP_STATUS]);
?><!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>OpenVPN Web GUI</title>
  <meta http-equiv="refresh" content="<?= $REFRESH_INTERVAL ?>">
  <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --primary: #6200ea;
      --surface: #ffffff;
      --on-surface: #000000;
      --background: #f5f5f5;
    }
    [data-theme="dark"] {
      --surface: #121212;
      --on-surface: #ffffff;
      --background: #181818;
    }
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:'Roboto',sans-serif;background:var(--background);color:var(--on-surface);padding:20px;transition:background .3s,color .3s}
    .topbar{display:flex;justify-content:space-between;align-items:center;margin-bottom:20px}
    .toggles button{margin-left:8px;cursor:pointer;padding:6px 12px;border:none;border-radius:4px;background:var(--primary);color:#fff}
    .container{max-width:1000px;margin:auto}
    .card{background:var(--surface);border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1);padding:24px;margin-bottom:20px;}
    h1{font-size:2rem;margin-bottom:8px;color:var(--primary)}
    h2{margin-bottom:12px}
    table{width:100%;border-collapse:collapse}
    th,td{text-align:left;padding:12px}
    th{background:var(--primary);color:#fff;font-weight:500}
    tr:nth-child(even) td{background:rgba(0,0,0,0.03)}
    a.btn{text-decoration:none;padding:8px 16px;border-radius:4px;font-weight:500;background:var(--primary);color:#fff}
    .logout{background:#d32f2f}
  </style>
</head>
<body>
  <div class="topbar">
    <h1>OpenVPN Web GUI</h1>
    <div class="toggles">
      <button onclick="toggleTheme()">🌙 Dark/Light</button>
      <button onclick="toggleAccent()">🎨 Accent</button>
      <a class="btn logout" href="?logout=1">Logout</a>
    </div>
  </div>
  <div class="container">
    <div class="card">
      <h2>Available Profiles</h2>
      <table><tr><th>Client</th><th>Download</th></tr>
      <?php foreach($clients as $c): ?><tr>
        <td><?=htmlspecialchars($c)?></td>
        <td><a class="btn" href="?download=<?=urlencode($c)?>">Download</a></td>
      </tr><?php endforeach; ?></table>
    </div>
    <div class="card">
      <h2>Connected Clients</h2>
      <table>
        <tr><th>Client</th><th>Virtual IP</th><th>Real IP</th><th>Since</th><th>Traffico</th></tr>
        <?php foreach($status as $name => $i): ?><tr>
          <td><?=htmlspecialchars($name)?></td>
          <td><?=htmlspecialchars($i['virtual'])?></td>
          <td><?=htmlspecialchars($i['real'])?></td>
          <td><?=htmlspecialchars($i['since'])?></td>
          <td><?=bytes_to_gb($i['traffic'])?></td>
        </tr><?php endforeach; ?>
      </table>
    </div>
  </div>
  <script>
    const root = document.documentElement;
    // initialize theme and accent from localStorage
    const savedTheme = localStorage.getItem('ovpn-theme') || 'light';
    const savedAccent = localStorage.getItem('ovpn-accent') === 'true';
    root.setAttribute('data-theme', savedTheme);
    if (savedAccent) root.style.setProperty('--primary', '#03a9f4');

    function toggleTheme() {
      const current = root.getAttribute('data-theme');
      const next = current === 'light' ? 'dark' : 'light';
      root.setAttribute('data-theme', next);
      localStorage.setItem('ovpn-theme', next);
    }

    function toggleAccent() {
      const useAlt = !(localStorage.getItem('ovpn-accent') === 'true');
      localStorage.setItem('ovpn-accent', useAlt);
      root.style.setProperty('--primary', useAlt ? '#03a9f4' : '#6200ea');
    }
  </script>
</body>
</html>
