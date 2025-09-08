<?php
session_start();

// --- Configuration and Helpers ---

// Set a default timezone to avoid warnings
date_default_timezone_set('UTC');

// Simple rate limiting: seconds to wait between API calls
define('RATE_LIMIT_SECONDS', 0.5);

// Function to make API requests to Canvas
function canvas_api_request($endpoint, $method = 'GET', $data = null) {
    if (!isset($_SESSION['canvas_url']) || !isset($_SESSION['api_token'])) {
        return ['error' => 'API credentials not set.'];
    }

    // Rate limiting check
    $now = microtime(true);
    if (isset($_SESSION['last_api_call']) && ($now - $_SESSION['last_api_call']) < RATE_LIMIT_SECONDS) {
        usleep((RATE_LIMIT_SECONDS - ($now - $_SESSION['last_api_call'])) * 1000000);
    }
    $_SESSION['last_api_call'] = microtime(true);

    $url = rtrim($_SESSION['canvas_url'], '/') . '/api/v1/' . ltrim($endpoint, '/');
    
    $ch = curl_init();
    $headers = [
        'Authorization: Bearer ' . $_SESSION['api_token'],
        'Content-Type: application/json'
    ];

    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);

    if ($method === 'POST') {
        curl_setopt($ch, CURLOPT_POST, true);
        if ($data) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
        }
    }

    $response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($http_code >= 200 && $http_code < 300) {
        return json_decode($response, true);
    } else {
        $error_details = json_decode($response, true);
        $error_message = isset($error_details['errors'][0]['message']) 
            ? $error_details['errors'][0]['message'] 
            : "API request failed with HTTP code {$http_code}.";
        return ['error' => $error_message];
    }
}

// Function to get courses based on type
function get_courses($type = 'all') {
    $endpoint = '/courses?enrollment_state=active&per_page=100';
    if ($type === 'favorites') {
        $endpoint .= '&include[]=favorites';
    }
    
    $courses = canvas_api_request($endpoint);

    if (isset($courses['error'])) {
        return $courses;
    }

    if ($type === 'favorites') {
        return array_filter($courses, function($course) {
            return !empty($course['is_favorite']);
        });
    }
    
    return $courses;
}

// --- Logic for Handling POST Requests ---

$login_error = null;
$assignment_results = [];

// Handle logout
if (isset($_GET['action']) && $_GET['action'] === 'logout') {
    session_unset();
    session_destroy();
    header('Location: ' . strtok($_SERVER["REQUEST_URI"], '?'));
    exit;
}

// Handle login form submission
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['canvas_url'])) {
    $_SESSION['canvas_url'] = $_POST['canvas_url'];
    $_SESSION['api_token'] = $_POST['api_token'];

    // Test connection
    $test_connection = canvas_api_request('/users/self');
    if (isset($test_connection['error'])) {
        $login_error = "Login failed: " . $test_connection['error'];
        session_unset();
        session_destroy();
    } else {
        header('Location: ' . strtok($_SERVER["REQUEST_URI"], '?'));
        exit;
    }
}

// Handle assignment creation
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['assignment_name'])) {
    $selected_courses = isset($_POST['courses']) ? $_POST['courses'] : [];
    
    if (empty($selected_courses)) {
        $assignment_results[] = ['error' => 'Please select at least one course.'];
    } else {
        $assignment_details = [
            'assignment' => [
                'name' => $_POST['assignment_name'],
                'description' => $_POST['description'],
                'points_possible' => (int)$_POST['points_possible'],
                'published' => isset($_POST['published']),
                'submission_types' => ['online_upload'] // Default, can be expanded
            ]
        ];

        if (!empty($_POST['due_at'])) {
            $assignment_details['assignment']['due_at'] = date('c', strtotime($_POST['due_at']));
        }

        foreach ($selected_courses as $course_id) {
            $result = canvas_api_request("/courses/{$course_id}/assignments", 'POST', $assignment_details);
            if (isset($result['error'])) {
                $assignment_results[] = ['error' => "Course {$course_id}: Failed - " . $result['error']];
            } else {
                $assignment_results[] = ['success' => "Course {$course_id}: Assignment '{$result['name']}' created successfully."];
            }
        }
    }
}

$is_logged_in = isset($_SESSION['api_token']);

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Canvas Assignment Creator</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; line-height: 1.6; margin: 0; background-color: #f8f9fa; color: #333; }
        .container { max-width: 900px; margin: 20px auto; padding: 20px; background-color: #fff; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1, h2 { color: #0056b3; }
        .login-form { max-width: 400px; margin: 40px auto; padding: 20px; border: 1px solid #ddd; border-radius: 8px; }
        .form-group { margin-bottom: 15px; }
        label { display: block; margin-bottom: 5px; font-weight: bold; }
        input[type="text"], input[type="password"], input[type="number"], input[type="datetime-local"], textarea { width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box; }
        button { background-color: #007bff; color: white; padding: 10px 15px; border: none; border-radius: 4px; cursor: pointer; font-size: 16px; }
        button:hover { background-color: #0056b3; }
        .logout-btn { background-color: #dc3545; float: right; }
        .logout-btn:hover { background-color: #c82333; }
        .tabs { display: flex; border-bottom: 2px solid #dee2e6; margin-bottom: 20px; }
        .tab-link { padding: 10px 20px; cursor: pointer; border: 1px solid transparent; border-bottom: none; margin-bottom: -2px; }
        .tab-link.active { font-weight: bold; border-color: #dee2e6 #dee2e6 #fff; border-radius: 4px 4px 0 0; background-color: #fff; }
        .tab-content { display: none; }
        .tab-content.active { display: block; }
        .course-list { max-height: 300px; overflow-y: auto; border: 1px solid #ddd; padding: 10px; border-radius: 4px; }
        .course-item { margin-bottom: 5px; }
        .alert { padding: 15px; margin-bottom: 20px; border-radius: 4px; }
        .alert-danger { background-color: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .alert-success { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
    </style>
</head>
<body>

<div class="container">
    <?php if (!$is_logged_in): ?>
        <div class="login-form">
            <h1>Login to Canvas</h1>
            <p>Enter your Canvas URL and API token.</p>
            <?php if ($login_error): ?>
                <div class="alert alert-danger"><?php echo htmlspecialchars($login_error); ?></div>
            <?php endif; ?>
            <form action="" method="POST">
                <div class="form-group">
                    <label for="canvas_url">Canvas URL</label>
                    <input type="text" id="canvas_url" name="canvas_url" placeholder="https://your.instructure.com" required>
                </div>
                <div class="form-group">
                    <label for="api_token">API Token</label>
                    <input type="password" id="api_token" name="api_token" required>
                </div>
                <button type="submit">Login</button>
            </form>
        </div>
    <?php else: ?>
        <a href="?action=logout"><button class="logout-btn">Logout</button></a>
        <h1>Canvas Assignment Creator</h1>

        <?php if (!empty($assignment_results)): ?>
            <h2>Assignment Creation Status</h2>
            <?php foreach ($assignment_results as $result): ?>
                <?php if (isset($result['error'])): ?>
                    <div class="alert alert-danger"><?php echo htmlspecialchars($result['error']); ?></div>
                <?php else: ?>
                    <div class="alert alert-success"><?php echo htmlspecialchars($result['success']); ?></div>
                <?php endif; ?>
            <?php endforeach; ?>
        <?php endif; ?>

        <form action="" method="POST">
            <h2>1. Select Courses</h2>
            <div class="tabs">
                <div class="tab-link active" onclick="openTab(event, 'favorites')">Favorites</div>
                <div class="tab-link" onclick="openTab(event, 'active')">Active Courses</div>
                <div class="tab-link" onclick="openTab(event, 'all')">All Courses</div>
            </div>

            <div id="favorites" class="tab-content active">
                <div class="course-list">
                    <?php
                    $fav_courses = get_courses('favorites');
                    if (isset($fav_courses['error'])) {
                        echo "<p class='alert alert-danger'>Error: " . htmlspecialchars($fav_courses['error']) . "</p>";
                    } elseif (empty($fav_courses)) {
                        echo "<p>No favorited courses found.</p>";
                    } else {
                        foreach ($fav_courses as $course) {
                            echo "<div class='course-item'><label><input type='checkbox' name='courses[]' value='{$course['id']}'> " . htmlspecialchars($course['name']) . "</label></div>";
                        }
                    }
                    ?>
                </div>
            </div>
            <div id="active" class="tab-content">
                <div class="course-list">
                    <?php
                    $active_courses = get_courses('active');
                     if (isset($active_courses['error'])) {
                        echo "<p class='alert alert-danger'>Error: " . htmlspecialchars($active_courses['error']) . "</p>";
                    } else {
                        foreach ($active_courses as $course) {
                            echo "<div class='course-item'><label><input type='checkbox' name='courses[]' value='{$course['id']}'> " . htmlspecialchars($course['name']) . "</label></div>";
                        }
                    }
                    ?>
                </div>
            </div>
            <div id="all" class="tab-content">
                 <div class="course-list">
                    <?php
                    $all_courses = get_courses('all');
                     if (isset($all_courses['error'])) {
                        echo "<p class='alert alert-danger'>Error: " . htmlspecialchars($all_courses['error']) . "</p>";
                    } else {
                        foreach ($all_courses as $course) {
                            echo "<div class='course-item'><label><input type='checkbox' name='courses[]' value='{$course['id']}'> " . htmlspecialchars($course['name']) . "</label></div>";
                        }
                    }
                    ?>
                </div>
            </div>

            <h2 style="margin-top: 30px;">2. Assignment Details</h2>
            <div class="form-group">
                <label for="assignment_name">Assignment Name</label>
                <input type="text" id="assignment_name" name="assignment_name" required>
            </div>
            <div class="form-group">
                <label for="description">Description</label>
                <textarea id="description" name="description" rows="4"></textarea>
            </div>
            <div class="form-group">
                <label for="points_possible">Points</label>
                <input type="number" id="points_possible" name="points_possible" value="10" required>
            </div>
            <div class="form-group">
                <label for="due_at">Due Date (Optional)</label>
                <input type="datetime-local" id="due_at" name="due_at">
            </div>
            <div class="form-group">
                <label><input type="checkbox" name="published" checked> Publish Immediately</label>
            </div>

            <button type="submit">Create Assignment(s)</button>
        </form>
    <?php endif; ?>
</div>

<script>
    function openTab(evt, tabName) {
        var i, tabcontent, tablinks;
        tabcontent = document.getElementsByClassName("tab-content");
        for (i = 0; i < tabcontent.length; i++) {
            tabcontent[i].style.display = "none";
        }
        tablinks = document.getElementsByClassName("tab-link");
        for (i = 0; i < tablinks.length; i++) {
            tablinks[i].className = tablinks[i].className.replace(" active", "");
        }
        document.getElementById(tabName).style.display = "block";
        evt.currentTarget.className += " active";
    }
</script>

</body>
</html>
