vcl 4.0;

import directors;
import std;

# -----------------------------------------------------------------------------
# Healthcheck probe (basic)
# -----------------------------------------------------------------------------
probe healthcheck {
	.interval = 5s;
	.timeout = 2s;
	.window = 5;
	.threshold = 3;
	.initial = 2;
	.expected_response = 200;
	.request =
		"GET / HTTP/1.1"
		"Host: localhost.localdomain"
		"Connection: close"
		"User-Agent: Varnish"
		"Accept-Encoding: gzip, deflate";
}

# -----------------------------------------------------------------------------
# HTTP Backends
# -----------------------------------------------------------------------------
backend http_1 { .host = "httpd_1"; .port = "80"; .first_byte_timeout = 300s; .probe = healthcheck; }

# -----------------------------------------------------------------------------
# HTTP (HTTPS Terminated) Backends
# -----------------------------------------------------------------------------
backend terminated_https_1 { .host = "httpd_1"; .port = "8443"; .first_byte_timeout = 300s; .probe = healthcheck; }

# -----------------------------------------------------------------------------
# Directors
# -----------------------------------------------------------------------------
sub vcl_init {
	new director_http = directors.round_robin();
	director_http.add_backend(http_1);

	new director_terminated_https = directors.round_robin();
	director_terminated_https.add_backend(terminated_https_1);
}

# -----------------------------------------------------------------------------
# Client side
# -----------------------------------------------------------------------------
sub vcl_recv {
	if (req.method == "PRI") {
		# Reject SPDY or HTTP/2.0 with Method Not Allowed
		return (synth(405));
	}

	unset req.http.Forwarded;
	unset req.http.X-Forwarded-Port;
	unset req.http.X-Forwarded-Proto;

	if (std.port(server.ip) == 8443 ||
		std.port(local.ip) == 8443) {
		# SSL Terminated upstream so indcate this with a custom header
		set req.http.X-Forwarded-Port = "443";
		set req.http.X-Forwarded-Proto = "https";
		set req.backend_hint = director_terminated_https.backend();
	} else if (std.port(server.ip) == 80 ||
		std.port(local.ip) == 80) {
		# Default to HTTP
		set req.http.X-Forwarded-Port = "80";
		set req.backend_hint = director_http.backend();
	} else {
		return (synth(403));
	}

	# set req.http.X-Varnish-Grace = "none";

	if (req.method != "GET" &&
		req.method != "HEAD" &&
		req.method != "PUT" &&
		req.method != "POST" &&
		req.method != "TRACE" &&
		req.method != "OPTIONS" &&
		req.method != "DELETE") {
		# Non-RFC2616 or CONNECT which is weird.
		return (pipe);
	}

	if (req.method != "GET" && 
		req.method != "HEAD") {
		# Only deal with GET and HEAD by default
		return (pass);
	}

	# Handle Expect request
	if (req.http.Expect) {
		return (pipe);
	}

	# Cache-Control
	if (req.http.Cache-Control ~ "(private|no-cache|no-store)") {
		return (pass);
	}

	# Cache static assets
	if (req.url ~ "\.(gif|png|jpe?g|ico|swf|css|js|html?|txt)$") {
		unset req.http.Cookie;
		return (hash);
	}

	# Remove all cookies that we doesn't need to know about. e.g. 3rd party analytics cookies
	if (req.http.Cookie) {
		set req.http.Cookie = ";" + req.http.Cookie;
		set req.http.Cookie = regsuball(req.http.Cookie, "; +", ";");
		set req.http.Cookie = regsuball(req.http.Cookie, ";(PHPSESSID|app-session)=", "; \1=");
		set req.http.Cookie = regsuball(req.http.Cookie, ";[^ ][^;]*", "");
		set req.http.Cookie = regsuball(req.http.Cookie, "^[; ]+|[; ]+$", "");

		if (req.http.Cookie == "") {
			unset req.http.Cookie;
		}
	}

	# Non-cacheable requests
	if (req.http.Authorization || 
		req.http.Cookie) {
		return (pass);
	}

	return (hash);
}

sub vcl_hash {
	hash_data(req.url);

	if (req.http.host) {
		hash_data(req.http.host);
	} else {
		hash_data(server.ip);
	}

	if (req.http.X-Forwarded-Proto) {
		hash_data(req.http.X-Forwarded-Proto);
	}

	return (lookup);
}

sub vcl_hit {
	if (obj.ttl >= 0s) {
		return (deliver);
	}

	if (std.healthy(req.backend_hint) && 
		obj.ttl + 15s > 0s) {
		# set req.http.X-Varnish-Grace = "normal";
		return (deliver);
	} else if (obj.ttl + obj.grace > 0s) {
		# set req.http.X-Varnish-Grace = "full";
		return (deliver);
	}

	return (miss);
}

sub vcl_deliver {
	# set resp.http.X-Varnish-Grace = req.http.X-Varnish-Grace;

	return (deliver);
}

# Errors: 413, 417 & 503
sub vcl_synth {
	set resp.http.Content-Type = "text/html; charset=utf-8";
	set resp.http.Retry-After = "5";
	synthetic( {"<!DOCTYPE html>
<html>
	<head>
		<title>Error</title>
		<style>
			body{font-family:sans-serif;color:#666;background-color:#f1f1f1;margin:12%;max-width:50%;}
			h1{color:#333;font-size:1.5em;font-weight:400;text-transform:uppercase;}
		</style>
	</head>
	<body>
		<h1>"} + resp.status + " " + resp.reason + {"</h1>
		<p>"} + resp.reason + {"</p>
		<p>XID: "} + req.xid + {"</p>
	</body>
</html>
"} );
	return (deliver);
}

# -----------------------------------------------------------------------------
# Backend
# -----------------------------------------------------------------------------
sub vcl_backend_response {
	# Keep objects beyond their ttl
	set beresp.grace = 12h;

	if (beresp.ttl <= 0s ||
		beresp.http.Set-Cookie ||
		beresp.http.Surrogate-control ~ "no-store" ||
		( ! beresp.http.Surrogate-Control && 
			beresp.http.Cache-Control ~ "(private|no-cache|no-store)") ||
		beresp.http.Vary == "*") {
		# Mark as "Hit-For-Pass" for the next 2 minutes
		set beresp.uncacheable = true;
		set beresp.ttl = 120s;
		return (deliver);
	}

	return (deliver);
}

sub vcl_backend_error {
	set beresp.http.Content-Type = "text/html; charset=utf-8";
	set beresp.http.Retry-After = "5";
	synthetic( {"<!DOCTYPE html>
<html>
	<style>
		body{font-family:sans-serif;color:#666;background-color:#f1f1f1;margin:12%;max-width:50%;}
		h1{color:#333;font-size:1.5em;font-weight:400;text-transform:uppercase;}
	</style>
	<head>
		<title>Error</title>
	</head>
	<body>
		<h1>"} + beresp.status + " " + beresp.reason + {"</h1>
		<p>"} + beresp.reason + {"</p>
		<p>XID: "} + bereq.xid + {"</p>
	</body>
</html>
"} );
	return (deliver);
}
