const express = require('express');
const { Pool } = require('pg');
const amqp = require('amqplib');
const client = require('prom-client');

const app = express();
app.use(express.json());

const register = new client.Registry();
client.collectDefaultMetrics({ register });

const orderCounter = new client.Counter({
  name: 'cloudpulse_orders_created_total',
  help: 'Total number of processed financial orders',
  labelNames: ['version', 'status'],
  registers: [register]
});

const SERVICE_VERSION = process.env.SERVICE_VERSION || 'v1.0.0-stable';
const PORT = process.env.PORT || 8082;

const pool = new Pool({
  host: process.env.DB_HOST || 'postgresql',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  user: process.env.DB_USER || 'cloudpulse',
  password: process.env.DB_PASSWORD || 'cloudpulse_secret_db_pass',
  database: process.env.DB_NAME || 'cloudpulsedb',
});

let rabbitChannel = null;
const QUEUE_NAME = 'order_events';

async function initInfrastructure() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS orders (
        id SERIAL PRIMARY KEY,
        username VARCHAR(100) NOT NULL,
        product_id VARCHAR(50) NOT NULL,
        quantity INT NOT NULL,
        amount NUMERIC(10, 2) NOT NULL,
        processed_by_version VARCHAR(50) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);
    console.log('PostgreSQL orders table verified.');
  } catch (err) {
    console.error('Database initialization warning:', err.message);
  }

  try {
    const rabbitUrl = process.env.RABBITMQ_URL || 'amqp://guest:guest@rabbitmq:5672';
    const conn = await amqp.connect(rabbitUrl);
    rabbitChannel = await conn.createChannel();
    await rabbitChannel.assertQueue(QUEUE_NAME, { durable: true });
    console.log('Connected to RabbitMQ broker.');
  } catch (err) {
    console.error('RabbitMQ connection warning:', err.message);
  }
}

app.get('/healthz', (req, res) => {
  res.status(200).json({ status: 'healthy', service: 'order-service', version: SERVICE_VERSION });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.post('/orders', async (req, res) => {
  const { user, product_id, quantity, amount } = req.body;
  try {
    const result = await pool.query(
      'INSERT INTO orders (username, product_id, quantity, amount, processed_by_version) VALUES ($1, $2, $3, $4, $5) RETURNING *',
      [user || 'anonymous', product_id, quantity, amount, SERVICE_VERSION]
    );
    const savedOrder = result.rows[0];

    if (rabbitChannel) {
      const eventPayload = JSON.stringify({
        event: 'ORDER_CREATED',
        order_id: savedOrder.id,
        user: savedOrder.username,
        product_id: savedOrder.product_id,
        amount: savedOrder.amount,
        version: SERVICE_VERSION,
        timestamp: new Date().toISOString()
      });
      rabbitChannel.sendToQueue(QUEUE_NAME, Buffer.from(eventPayload), { persistent: true });
    }

    orderCounter.inc({ version: SERVICE_VERSION, status: 'success' });
    res.status(201).json({
      status: 'Order Processed & Event Published',
      canary_version: SERVICE_VERSION,
      order: savedOrder
    });
  } catch (err) {
    orderCounter.inc({ version: SERVICE_VERSION, status: 'error' });
    res.status(500).json({ error: err.message, canary_version: SERVICE_VERSION });
  }
});

app.get('/orders', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM orders ORDER BY created_at DESC LIMIT 20');
    res.status(200).json({
      canary_version: SERVICE_VERSION,
      orders: result.rows
    });
  } catch (err) {
    res.status(500).json({ error: err.message, canary_version: SERVICE_VERSION });
  }
});

app.listen(PORT, () => {
  console.log(`Order Service (${SERVICE_VERSION}) listening on port ${PORT}`);
  initInfrastructure();
});
