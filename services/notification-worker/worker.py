import os
import json
import time
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
import pika
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST

RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://guest:guest@rabbitmq:5672")
QUEUE_NAME = "order_events"
PORT = int(os.getenv("PORT", "8083"))

EVENTS_PROCESSED = Counter(
    "cloudpulse_notifications_sent_total",
    "Total number of order notifications processed from RabbitMQ"
)

class HealthAndMetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"healthy","service":"notification-worker"}')
        elif self.path == "/metrics":
            self.send_response(200)
            self.send_header("Content-Type", CONTENT_TYPE_LATEST)
            self.end_headers()
            self.wfile.write(generate_latest())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        return

def start_http_server():
    server = HTTPServer(("0.0.0.0", PORT), HealthAndMetricsHandler)
    server.serve_forever()

def consume_loop():
    while True:
        try:
            params = pika.URLParameters(RABBITMQ_URL)
            connection = pika.BlockingConnection(params)
            channel = connection.channel()
            channel.queue_declare(queue=QUEUE_NAME, durable=True)
            print("Notification Worker connected to RabbitMQ. Waiting for events...", flush=True)

            def callback(ch, method, properties, body):
                event = json.loads(body.decode("utf-8"))
                print(f"[AUDIT NOTIFICATION] Order #{event.get('order_id')} for user '{event.get('user')}' ($ {event.get('amount')}) processed via {event.get('version')}", flush=True)
                EVENTS_PROCESSED.inc()
                ch.basic_ack(delivery_tag=method.delivery_tag)

            channel.basic_qos(prefetch_count=1)
            channel.basic_consume(queue=QUEUE_NAME, on_message_callback=callback)
            channel.start_consuming()
        except Exception as exc:
            print(f"RabbitMQ connection retry in 5s: {exc}", flush=True)
            time.sleep(5)

if __name__ == "__main__":
    http_thread = threading.Thread(target=start_http_server, daemon=True)
    http_thread.start()
    consume_loop()
