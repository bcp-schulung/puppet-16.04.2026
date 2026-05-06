'use strict';

require('dotenv').config();

const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');

const pool = new Pool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     parseInt(process.env.DB_PORT || '5432', 10),
  user:     process.env.DB_USER     || 'postgres',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME     || 'jokes',
});

const SEED_JOKES = [
  { setup: "Why don't scientists trust atoms?",           punchline: "Because they make up everything!" },
  { setup: "Why did the scarecrow win an award?",         punchline: "Because he was outstanding in his field!" },
  { setup: "Why don't eggs tell jokes?",                  punchline: "They'd crack each other up." },
  { setup: "What do you call fake spaghetti?",            punchline: "An impasta!" },
  { setup: "Why did the bicycle fall over?",              punchline: "Because it was two-tired!" },
  { setup: "How does a penguin build its house?",         punchline: "Igloos it together." },
  { setup: "Why can't you give Elsa a balloon?",          punchline: "Because she'll let it go." },
  { setup: "What do you call cheese that isn't yours?",   punchline: "Nacho cheese." },
  { setup: "Why did the math book look so sad?",          punchline: "Because it had too many problems." },
  { setup: "What do you call a fish without eyes?",       punchline: "A fsh." },
  { setup: "Why did the coffee file a police report?",    punchline: "It got mugged." },
  { setup: "How do you organize a space party?",          punchline: "You planet." },
  { setup: "What do you call a sleeping dinosaur?",       punchline: "A dino-snore!" },
  { setup: "Why are ghosts bad liars?",                   punchline: "Because you can see right through them." },
  { setup: "What do you call a bear with no teeth?",      punchline: "A gummy bear!" },
];

async function initDatabase(client) {
  await client.query(`
    CREATE TABLE IF NOT EXISTS jokes (
      id        SERIAL PRIMARY KEY,
      setup     TEXT NOT NULL,
      punchline TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  const { rows } = await client.query('SELECT COUNT(*) AS cnt FROM jokes');
  if (parseInt(rows[0].cnt, 10) === 0) {
    const values = SEED_JOKES.map((j, i) => `($${i * 2 + 1}, $${i * 2 + 2})`).join(', ');
    const params = SEED_JOKES.flatMap(j => [j.setup, j.punchline]);
    await client.query(`INSERT INTO jokes (setup, punchline) VALUES ${values}`, params);
    console.log(`Seeded ${SEED_JOKES.length} jokes into the database.`);
  }
}

async function start() {
  // Fail fast if the database is unreachable
  let client;
  try {
    client = await pool.connect();
    console.log('Connected to PostgreSQL.');
    await initDatabase(client);
  } catch (err) {
    console.error('ERROR: Could not connect to PostgreSQL database.');
    console.error(err.message);
    process.exit(1);
  } finally {
    if (client) client.release();
  }

  const app = express();

  app.use(cors({
    origin: process.env.FRONTEND_ORIGIN || '*',
  }));

  app.get('/api/joke', async (req, res) => {
    try {
      const { rows } = await pool.query(
        'SELECT id, setup, punchline FROM jokes ORDER BY RANDOM() LIMIT 1'
      );
      if (rows.length === 0) {
        return res.status(404).json({ error: 'No jokes found.' });
      }
      res.json(rows[0]);
    } catch (err) {
      console.error('Database error:', err.message);
      res.status(500).json({ error: 'Internal server error.' });
    }
  });

  app.get('/health', (req, res) => {
    res.json({ status: 'ok' });
  });

  const PORT = parseInt(process.env.PORT || '3001', 10);
  app.listen(PORT, () => {
    console.log(`Joke backend listening on port ${PORT}`);
  });
}

start();
