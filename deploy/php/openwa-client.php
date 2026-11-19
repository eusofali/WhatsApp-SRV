<?php
/**
 * Minimal PHP client for your OpenWA server. Works on ANY cPanel shared hosting (needs only cURL).
 * This is the "Hybrid" setup: OpenWA runs on a VPS, your PHP/WordPress site on cPanel calls it.
 *
 * Put the key in an environment variable or a file OUTSIDE public_html, never in the web root.
 *   $wa = new OpenWA('https://wa.example.com', getenv('OPENWA_KEY'));
 *   $wa->sendText('SESSION_ID', '15551234567@c.us', 'Hello from cPanel');
 *
 * Endpoints follow OpenWA's REST API (see https://YOUR_HOST/api/docs when ENABLE_SWAGGER=true).
 * Verify the exact paths in your version; the send-text route below comes from OpenWA's FAQ.
 */
final class OpenWA
{
    public function __construct(private string $baseUrl, private string $apiKey, private int $timeout = 30) {}

    private function call(string $method, string $path, ?array $body = null): array
    {
        $ch = curl_init(rtrim($this->baseUrl, '/') . $path);
        curl_setopt_array($ch, [
            CURLOPT_CUSTOMREQUEST  => $method,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => $this->timeout,
            CURLOPT_HTTPHEADER     => ['X-API-Key: ' . $this->apiKey, 'Content-Type: application/json'],
            CURLOPT_SSL_VERIFYPEER => true,
        ]);
        if ($body !== null) curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body));
        $raw  = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $err  = curl_error($ch);
        curl_close($ch);
        if ($raw === false) throw new RuntimeException("OpenWA request failed: $err");
        $json = json_decode($raw, true);
        if ($code >= 400) throw new RuntimeException("OpenWA HTTP $code: $raw");
        return is_array($json) ? $json : ['raw' => $raw];
    }

    public function sessions(): array { return $this->call('GET', '/api/sessions'); }

    public function sendText(string $sessionId, string $chatId, string $text): array
    {
        return $this->call('POST', "/api/sessions/$sessionId/messages/send-text", [
            'chatId' => $chatId, 'text' => $text,
        ]);
    }
}

/**
 * Receiving messages: set a webhook in the OpenWA dashboard to https://yourcpanelsite.com/wa-webhook.php
 * and verify the HMAC signature header before trusting the body (header name/algorithm: see OpenWA docs
 * "webhooks"). Skeleton:
 *
 *   $raw = file_get_contents('php://input');
 *   $sig = $_SERVER['HTTP_X_OPENWA_SIGNATURE'] ?? '';          // confirm header name in your version
 *   if (!hash_equals(hash_hmac('sha256', $raw, getenv('OPENWA_WEBHOOK_SECRET')), $sig)) { http_response_code(401); exit; }
 *   $event = json_decode($raw, true);  // handle, then:
 *   http_response_code(200);
 */
